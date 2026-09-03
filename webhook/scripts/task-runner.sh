#!/bin/bash
set -uo pipefail

# =============================================================================
# Runs one maintenance task and reports the outcome.
#
# Started detached by cms-task.sh, which has already validated the name and
# taken /tmp/climweb-task.lock. This script owns that lock now: it releases it
# on the way out, whatever happens, so a crashed task cannot wedge the button.
#
# The terminal status is written here rather than by the task, so a task that
# dies unexpectedly (or is killed) is still reported as failed rather than
# leaving "running" on the admin page forever.
# =============================================================================

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/homebrew/bin:/Applications/Docker.app/Contents/Resources/bin:$PATH"

REPO_DIR="${REPO_DIR:-$(pwd -P)}"
export REPO_DIR

SCRIPT_DIR="$REPO_DIR/webhook/scripts"
LOCKDIR="/tmp/climweb-task.lock"

# shellcheck source=webhook/scripts/task-lib.sh
source "$SCRIPT_DIR/task-lib.sh" || { echo "Cannot source task-lib.sh" >&2; exit 1; }

TASK_NAME_IN="${1:-}"
task_init "$TASK_NAME_IN"

TASK_SCRIPT="$REPO_DIR/webhook/tasks/$TASK_NAME_IN.sh"

cleanup() { rm -rf "$LOCKDIR" 2>/dev/null || true; }
trap cleanup EXIT

cd "$REPO_DIR" || { task_write_status "failed" "Cannot enter $REPO_DIR"; exit 1; }

bash "$TASK_SCRIPT" >> "$TASK_LOG_FILE" 2>&1
rc=$?

last_step="$(cat "$TASK_STEP_FILE" 2>/dev/null || true)"
last_step="${last_step:-$TASK_NAME_IN}"

if [[ $rc -eq 0 ]]; then
  task_log "SUCCESS: $TASK_NAME_IN"
  task_write_status "success" "$last_step"
else
  task_log "FAILED: $TASK_NAME_IN (exit $rc)"
  task_write_status "failed" "$last_step" "Task exited with code $rc. See $TASK_LOG_FILE for the full output."
fi

rm -f "$TASK_STEP_FILE" 2>/dev/null || true
exit "$rc"
