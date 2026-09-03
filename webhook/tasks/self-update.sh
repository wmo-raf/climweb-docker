#!/bin/bash
set -uo pipefail

# =============================================================================
# Task: self-update
#
# Brings this server's copy of climweb-docker up to date with its remote branch,
# then regenerates the webhook hook list. That is what makes every later
# capability arrive without anyone opening a terminal: the ClimWeb team commits
# a new task to webhook/tasks/ and a new hook to webhook/hooks.yaml.sample, the
# focal point presses this button, and the new task becomes available.
#
# Deliberately conservative:
#   * fast-forward only, on the branch the server is already on
#   * refuses if tracked files were edited locally (nothing is discarded)
#   * refuses if history diverged
#   * never touches .env, docker-compose.yml, nginx.conf, containers or data
#
# It does not restart the stack and does not change the ClimWeb version. Those
# are separate, deliberate actions.
# =============================================================================

# shellcheck source=webhook/scripts/task-lib.sh
source "$REPO_DIR/webhook/scripts/task-lib.sh"
task_init "self-update"

cd "$REPO_DIR" || task_fail "Cannot enter the project directory $REPO_DIR."

task_step "Checking the repository..."

command -v git >/dev/null 2>&1 || task_fail "git is not installed on this server."
[[ -d .git ]] || task_fail "$REPO_DIR is not a git repository."

# Running as root against a repo owned by another user trips git's ownership
# check. Allow this one path rather than turning the check off globally.
if ! git status --porcelain >/dev/null 2>&1; then
  if ! git config --global --get-all safe.directory 2>/dev/null | grep -qxF "$REPO_DIR"; then
    git config --global --add safe.directory "$REPO_DIR" 2>/dev/null || true
    task_log "Marked $REPO_DIR as a safe git directory for this user."
  fi
  git status --porcelain >/dev/null 2>&1 || task_fail "Cannot read the git repository in $REPO_DIR."
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
[[ -n "$BRANCH" && "$BRANCH" != "HEAD" ]] || task_fail "This checkout is not on a branch (detached HEAD). A person needs to look at it."

OLD_COMMIT="$(git rev-parse HEAD)"
task_log "Branch: $BRANCH at $OLD_COMMIT"

# Only tracked files matter. docker-compose.yml, nginx/nginx.conf and .env are
# untracked or gitignored on purpose, and stay exactly as they are.
if ! git diff --quiet HEAD 2>/dev/null; then
  git diff --stat HEAD >> "$TASK_LOG_FILE" 2>&1 || true
  task_fail "Tracked files in $REPO_DIR have local edits. Refusing to update so nothing is discarded - the ClimWeb team should review them first (see the log for the list)."
fi

# --- Fetch -------------------------------------------------------------------
task_step "Fetching the latest $BRANCH from the remote..."
if ! git fetch --prune origin "$BRANCH" >> "$TASK_LOG_FILE" 2>&1; then
  task_fail "Could not reach the git remote. Check that this server has internet access to github.com."
fi

REMOTE_COMMIT="$(git rev-parse "origin/$BRANCH" 2>/dev/null || true)"
[[ -n "$REMOTE_COMMIT" ]] || task_fail "The remote has no branch called $BRANCH."

if [[ "$OLD_COMMIT" == "$REMOTE_COMMIT" ]]; then
  task_step "Already up to date (no new changes on $BRANCH)."
  task_log "Nothing to do."
  exit 0
fi

# --- Fast-forward only -------------------------------------------------------
if ! git merge-base --is-ancestor HEAD "origin/$BRANCH" 2>/dev/null; then
  task_fail "This server's history has diverged from origin/$BRANCH - it has commits the remote does not. Refusing to update automatically; the ClimWeb team should look at it."
fi

task_step "Updating $BRANCH: $(git rev-parse --short HEAD) -> $(git rev-parse --short "origin/$BRANCH")..."
if ! git merge --ff-only "origin/$BRANCH" >> "$TASK_LOG_FILE" 2>&1; then
  task_fail "git could not fast-forward to origin/$BRANCH. See $TASK_LOG_FILE."
fi

NEW_COMMIT="$(git rev-parse HEAD)"
task_log "Updated: $OLD_COMMIT -> $NEW_COMMIT"
task_log "To undo by hand: git reset --hard $OLD_COMMIT"
git --no-pager log --oneline "$OLD_COMMIT..$NEW_COMMIT" >> "$TASK_LOG_FILE" 2>&1 || true

# --- Regenerate the hook list ------------------------------------------------
# This is the point of the whole task: hooks.yaml.sample may now define hooks
# this server has never heard of.
task_step "Refreshing the list of jobs this server accepts..."

HOOKS_FILE="$REPO_DIR/webhook/hooks.yaml"
HOOKS_BACKUP="$REPO_DIR/webhook/hooks.yaml.prev"
[[ -f "$HOOKS_FILE" ]] && cp "$HOOKS_FILE" "$HOOKS_BACKUP"

# bash, not sh: webhook-config.sh uses parameter expansion that dash cannot parse.
if ! bash "$REPO_DIR/webhook-config.sh" >> "$TASK_LOG_FILE" 2>&1; then
  if [[ -f "$HOOKS_BACKUP" ]]; then
    cp "$HOOKS_BACKUP" "$HOOKS_FILE"
    task_log "Restored the previous webhook/hooks.yaml."
  fi
  task_fail "Updated the code, but could not regenerate webhook/hooks.yaml. The previous hook list is still in place. See $TASK_LOG_FILE."
fi

# --- Make sure the new hooks are actually picked up --------------------------
# webhook reads hooks.yaml once at startup unless it was started with
# -hotreload. Instances set up before that flag existed need the supervisor
# config corrected once, here, or every future task would need a terminal again
# -- exactly the problem this mechanism exists to remove.
SUPERVISOR_CONF="/etc/supervisor/conf.d/webhook.conf"
RESTART_NEEDED="true"

if [[ -f "$SUPERVISOR_CONF" ]] && command -v supervisorctl >/dev/null 2>&1; then
  if grep -q -- "-hotreload" "$SUPERVISOR_CONF"; then
    task_log "webhook runs with -hotreload; it will pick up hooks.yaml on its own."
    RESTART_NEEDED="false"
  elif [[ "$(id -u)" -eq 0 ]]; then
    task_step "Teaching the webhook listener to notice future changes by itself..."
    cp "$SUPERVISOR_CONF" "$SUPERVISOR_CONF.prev" 2>/dev/null || true
    if sed -i.bak -E 's|^(command=.*webhook .*-hooks [^ ]+)(.*)$|\1 -hotreload\2|' "$SUPERVISOR_CONF" 2>/dev/null \
       && grep -q -- "-hotreload" "$SUPERVISOR_CONF"; then
      task_log "Added -hotreload to $SUPERVISOR_CONF."
      supervisorctl reread >> "$TASK_LOG_FILE" 2>&1 || true
      supervisorctl update >> "$TASK_LOG_FILE" 2>&1 || true
    else
      task_log "WARNING: could not add -hotreload to $SUPERVISOR_CONF automatically. Restarting webhook instead."
      [[ -f "$SUPERVISOR_CONF.prev" ]] && cp "$SUPERVISOR_CONF.prev" "$SUPERVISOR_CONF"
    fi
  else
    task_log "WARNING: not running as root, so $SUPERVISOR_CONF was left alone."
  fi
else
  task_log "No supervisor webhook config found - skipping the listener refresh."
  RESTART_NEEDED="false"
fi

if [[ "$RESTART_NEEDED" == "true" ]] && command -v supervisorctl >/dev/null 2>&1; then
  # Safe from here: this task runs in its own session (setsid), so restarting
  # webhook does not kill it.
  task_step "Restarting the webhook listener to load the new job list..."
  supervisorctl restart webhook >> "$TASK_LOG_FILE" 2>&1 || \
    task_log "WARNING: supervisorctl restart webhook failed - new jobs may not be available until webhook restarts."
  supervisorctl status webhook >> "$TASK_LOG_FILE" 2>&1 || true
fi

AVAILABLE=""
for t in "$REPO_DIR"/webhook/tasks/*.sh; do
  [[ -e "$t" ]] || continue
  t="$(basename "$t" .sh)"
  AVAILABLE="${AVAILABLE:+$AVAILABLE }$t"
done
task_log "Tasks now available: $AVAILABLE"

task_step "Updated to $(git rev-parse --short HEAD). Available tasks: $AVAILABLE"
exit 0
