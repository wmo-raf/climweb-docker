#!/bin/bash
# =============================================================================
# Shared helpers for ClimWeb maintenance tasks.
#
# Sourced by cms-task.sh (the dispatcher), task-runner.sh (the wrapper that
# actually runs a task) and by the task scripts in webhook/tasks/ themselves.
#
# After `task_init <task-name>` these are set:
#   REPO_DIR           project root (where .env and .git live)
#   TASK_NAME          the task being run
#   TASK_LOG_FILE      logs/climweb-tasks.log
#   TASK_STATUS_FILE   <BACKUP_VOLUME>/task-status.json  (read by the CMS)
#   TASK_STEP_FILE     last step, so a failure can name where it stopped
#   TASK_STARTED_AT    ISO timestamp
#
# Tasks report progress with task_step, and abort with task_fail. The terminal
# success/failed status is written by task-runner.sh from the exit code, so a
# task that dies unexpectedly still ends up reported as failed.
# =============================================================================

task_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Read a value from .env the way Docker Compose does: honour quotes, drop a
# trailing inline comment, tolerate CRLF. Same parser as migrate-to-registry.sh.
task_get_env() {
  local raw
  raw="$(grep -E "^[[:space:]]*(export[[:space:]]+)?$1=" "$REPO_DIR/.env" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '\r')"
  [[ -z "$raw" ]] && return 0
  raw="${raw#"${raw%%[![:space:]]*}"}"
  case "$raw" in
    \"*) raw="${raw#\"}"; raw="${raw%%\"*}" ;;
    \'*) raw="${raw#\'}"; raw="${raw%%\'*}" ;;
    *)   raw="${raw%%[[:space:]]#*}"
         raw="${raw%"${raw##*[![:space:]]}"}" ;;
  esac
  printf '%s' "$raw"
}

task_init() {
  TASK_NAME="${1:-${TASK_NAME:-unknown}}"
  REPO_DIR="${REPO_DIR:-$(pwd -P)}"

  TASK_LOG_FILE="$REPO_DIR/logs/climweb-tasks.log"
  mkdir -p "$REPO_DIR/logs" 2>/dev/null || true

  local backup_dir
  backup_dir="$(task_get_env BACKUP_VOLUME)"
  backup_dir="${backup_dir:-./climweb/backup}"
  # A relative BACKUP_VOLUME (the usual ./climweb/backup) is relative to the
  # project root, not to whatever directory this was invoked from.
  case "$backup_dir" in
    /*) ;;
    *) backup_dir="$REPO_DIR/${backup_dir#./}" ;;
  esac

  TASK_STATUS_FILE="$backup_dir/task-status.json"
  # One task runs at a time (cms-task.sh holds a global lock), so a fixed path
  # is safe and lets the runner read back what the task last reported.
  TASK_STEP_FILE="/tmp/climweb-task-step"
  TASK_STARTED_AT="${TASK_STARTED_AT:-$(task_now)}"

  export REPO_DIR TASK_NAME TASK_LOG_FILE TASK_STATUS_FILE TASK_STEP_FILE TASK_STARTED_AT
}

task_log() {
  echo "[$(task_now)] $*" >> "$TASK_LOG_FILE"
}

# JSON string escaping: backslashes first, then quotes, then drop control
# characters. Step text is written by us, but git and docker error messages get
# quoted into it and those contain anything.
task_json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr -d '\000-\037'
}

# task_write_status <status> <step> [detail]
#   status: running | success | failed | rejected
task_write_status() {
  local status="$1" step="$2" detail="${3:-}"
  local dir; dir="$(dirname "$TASK_STATUS_FILE")"
  mkdir -p "$dir" 2>/dev/null || true
  cat > "$TASK_STATUS_FILE" << JSONEOF
{
  "task": "$(task_json_escape "$TASK_NAME")",
  "status": "$(task_json_escape "$status")",
  "step": "$(task_json_escape "$step")",
  "detail": "$(task_json_escape "$detail")",
  "started_at": "$TASK_STARTED_AT",
  "updated_at": "$(task_now)",
  "log": "$(task_json_escape "$TASK_LOG_FILE")"
}
JSONEOF
  # The CMS reads this from inside its container as the non-root UID/GID from
  # .env, so match the owner of the backup directory it sits in.
  chown --reference="$dir" "$TASK_STATUS_FILE" 2>/dev/null || true
  chmod 0644 "$TASK_STATUS_FILE" 2>/dev/null || true
}

# task_step <human-readable step> -- log it, publish it, remember it
task_step() {
  task_log "$*"
  task_write_status "running" "$*"
  printf '%s' "$*" > "$TASK_STEP_FILE" 2>/dev/null || true
}

# task_fail <message> -- record why we stopped, then exit non-zero
task_fail() {
  task_log "ERROR: $*"
  printf '%s' "$*" > "$TASK_STEP_FILE" 2>/dev/null || true
  exit 1
}
