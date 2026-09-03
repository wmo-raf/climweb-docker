#!/bin/bash
set -uo pipefail

# =============================================================================
# ClimWeb maintenance-task dispatcher
#
# Triggered by the `cms-task` webhook when the CMS Admin asks for a named
# maintenance task. The name selects a script from webhook/tasks/ IN THIS REPO
# and nothing else -- no payload ever supplies a command, a path or a URL.
#
#   POST /hooks/cms-task  {"task_name": "self-update"}
#     -> bash webhook/tasks/self-update.sh
#
# So adding a server-side capability is a commit to climweb-docker, reviewed
# like any other code, delivered to instances by the self-update task itself.
# Nothing here can be talked into running something that is not in the repo.
#
# This script validates, locks and hands off; task-runner.sh does the running.
# Progress lands in <BACKUP_VOLUME>/task-status.json (mounted into the CMS
# container, so the admin page can poll it) and logs/climweb-tasks.log.
#
# Manual use, identical to pressing the button:
#   sudo bash webhook/scripts/cms-task.sh self-update
# =============================================================================

# Supervisor runs webhook with a minimal environment.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/homebrew/bin:/Applications/Docker.app/Contents/Resources/bin:$PATH"

REPO_DIR="$(pwd -P)"
export REPO_DIR

SCRIPT_DIR="$REPO_DIR/webhook/scripts"
TASKS_DIR="$REPO_DIR/webhook/tasks"
LOCKDIR="/tmp/climweb-task.lock"
UPGRADE_LOCK="/tmp/climweb-upgrade.lock"
MIGRATE_LOCK="/tmp/climweb-migrate.lock"

# shellcheck source=webhook/scripts/task-lib.sh
source "$SCRIPT_DIR/task-lib.sh" || { echo "Cannot source task-lib.sh" >&2; exit 1; }

task_init "${1:-}"

reject() {
  task_log "REJECTED (${1:-}): $2"
  task_write_status "rejected" "$2"
  echo "$2" >&2
  exit 1
}

# --- Validate the task name --------------------------------------------------
# The hook applies this regex too. It is repeated here because the script is
# also runnable by hand, and because one validated chokepoint beats two
# half-trusted ones. No dots and no slashes are accepted, so escaping out of
# webhook/tasks/ is impossible by construction rather than by sanitising.
TASK_NAME_IN="${1:-}"
[[ -n "$TASK_NAME_IN" ]] || reject "" "No task name given. Usage: cms-task.sh <task-name>"

if [[ ! "$TASK_NAME_IN" =~ ^[a-z0-9][a-z0-9-]{0,63}$ ]]; then
  reject "$TASK_NAME_IN" "Invalid task name (allowed: lowercase letters, digits and hyphens)."
fi

TASK_SCRIPT="$TASKS_DIR/$TASK_NAME_IN.sh"

[[ -f "$TASK_SCRIPT" ]] || reject "$TASK_NAME_IN" \
  "Unknown task '$TASK_NAME_IN' - this deployment has no webhook/tasks/$TASK_NAME_IN.sh. Run the self-update task first if you expect a newer task list."
[[ ! -L "$TASK_SCRIPT" ]] || reject "$TASK_NAME_IN" \
  "Task '$TASK_NAME_IN' is a symlink - refusing to run it."

# --- Refuse to overlap with an upgrade or a migration ------------------------
[[ -e "$UPGRADE_LOCK" ]] && reject "$TASK_NAME_IN" "A CMS upgrade is in progress. Try again when it finishes."
[[ -e "$MIGRATE_LOCK" ]] && reject "$TASK_NAME_IN" "A migration is in progress. Try again when it finishes."

# --- One task at a time ------------------------------------------------------
# mkdir is atomic, so two near-simultaneous clicks cannot both win.
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  reject "$TASK_NAME_IN" "Another task is already running (lock: $LOCKDIR). If you are certain nothing is running, remove that directory."
fi

task_log "============================================================"
task_log "Task accepted: $TASK_NAME_IN"
task_write_status "running" "Starting task '$TASK_NAME_IN'..."
printf '%s' "Starting task '$TASK_NAME_IN'..." > "$TASK_STEP_FILE" 2>/dev/null || true

# --- Hand off, detached ------------------------------------------------------
# setsid gives the task its own session, so it survives `supervisorctl restart
# webhook` (or anything else that signals webhook's process group) part-way
# through. Tasks that restart the stack need that; it is cheap insurance for
# the rest. The runner owns the lock from here and removes it when done.
LAUNCH=(bash "$SCRIPT_DIR/task-runner.sh" "$TASK_NAME_IN")
if command -v setsid >/dev/null 2>&1; then
  LAUNCH=(setsid "${LAUNCH[@]}")
fi

TASK_STARTED_AT="$TASK_STARTED_AT" nohup "${LAUNCH[@]}" < /dev/null >> "$TASK_LOG_FILE" 2>&1 &
disown 2>/dev/null || true

echo "Task '$TASK_NAME_IN' started. Progress: $TASK_STATUS_FILE"
exit 0
