#!/bin/bash
set -euo pipefail

# =============================================================================
# ClimWeb Plugin Management Script
# Triggered by the plugin-manage webhook.
# Supports actions: install, update, remove
# =============================================================================

# --- Configuration -----------------------------------------------------------
env_file=".env"
LOG_FILE="/var/log/climweb-plugin.log"
LOCKFILE="/tmp/climweb-plugin.lock"

# --- Logging -----------------------------------------------------------------
log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOG_FILE"
}

log_success() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] SUCCESS: $*" | tee -a "$LOG_FILE"
}

log_error() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

# --- Notification ------------------------------------------------------------
notify() {
  local subject="$1"
  local body="$2"

  local admin_email
  admin_email=$(grep -E "^CMS_ADMINS=" "$env_file" 2>/dev/null | awk -F'=' '{print $2}' | tr -d '"' | awk -F'<' '{print $2}' | tr -d '>')

  if [[ -n "$admin_email" ]]; then
    echo "$body" | mail -s "$subject" "$admin_email" 2>/dev/null || true
  fi
}

# --- Cleanup on exit ---------------------------------------------------------
cleanup() {
  rm -f "$LOCKFILE"
}
trap cleanup EXIT

# --- Input validation --------------------------------------------------------
ACTION="${1:-}"       # install | update | remove
PLUGIN_REPO="${2:-}"  # git repo URL, e.g. https://github.com/org/my-plugin
PLUGIN_NAME="${3:-}"  # plugin folder name, e.g. my_plugin

if [[ -z "$ACTION" || -z "$PLUGIN_NAME" ]]; then
  log_error "Usage: plugin-manage.sh <action> <repo_url> <plugin_name>"
  log_error "  action: install | update | remove"
  exit 1
fi

if [[ "$ACTION" != "remove" && -z "$PLUGIN_REPO" ]]; then
  log_error "repo_url is required for install and update actions."
  exit 1
fi

# --- Prevent concurrent operations -------------------------------------------
if [[ -e "$LOCKFILE" ]]; then
  log_error "Another plugin operation is already in progress. Exiting."
  exit 1
fi
touch "$LOCKFILE"

log "============================================================"
log "Plugin action: $ACTION | plugin: $PLUGIN_NAME"

# --- Resolve plugin directory ------------------------------------------------
CLIMWEB_PLUGIN_DIR=$(grep -E "^CLIMWEB_PLUGIN_DIR=" "$env_file" 2>/dev/null | awk -F'=' '{print $2}' | tr -d '"')
CLIMWEB_PLUGIN_DIR="${CLIMWEB_PLUGIN_DIR:-./climweb/plugins}"
PLUGIN_PATH="$CLIMWEB_PLUGIN_DIR/$PLUGIN_NAME"

# =============================================================================
# INSTALL
# =============================================================================
if [[ "$ACTION" == "install" ]]; then
  if [[ -d "$PLUGIN_PATH" ]]; then
    log_error "Plugin '$PLUGIN_NAME' is already installed at $PLUGIN_PATH. Use 'update' to upgrade it."
    exit 1
  fi

  log "Cloning $PLUGIN_REPO into $PLUGIN_PATH ..."
  if ! git clone "$PLUGIN_REPO" "$PLUGIN_PATH" >> "$LOG_FILE" 2>&1; then
    log_error "Failed to clone $PLUGIN_REPO"
    notify "ClimWeb plugin install FAILED: $PLUGIN_NAME" \
      "Could not clone $PLUGIN_REPO. Check $LOG_FILE for details."
    exit 1
  fi

  log "Restarting containers to load new plugin..."
  docker compose up -d --force-recreate >> "$LOG_FILE" 2>&1

  log_success "Plugin '$PLUGIN_NAME' installed successfully."
  notify "ClimWeb plugin installed: $PLUGIN_NAME" \
    "Plugin '$PLUGIN_NAME' has been installed from $PLUGIN_REPO."

# =============================================================================
# UPDATE
# =============================================================================
elif [[ "$ACTION" == "update" ]]; then
  if [[ ! -d "$PLUGIN_PATH" ]]; then
    log_error "Plugin '$PLUGIN_NAME' is not installed at $PLUGIN_PATH. Use 'install' first."
    exit 1
  fi

  log "Pulling latest changes for '$PLUGIN_NAME' from $PLUGIN_REPO ..."

  # If the directory is a git repo, pull. Otherwise re-clone.
  if [[ -d "$PLUGIN_PATH/.git" ]]; then
    if ! git -C "$PLUGIN_PATH" pull >> "$LOG_FILE" 2>&1; then
      log_error "git pull failed for $PLUGIN_NAME"
      notify "ClimWeb plugin update FAILED: $PLUGIN_NAME" \
        "git pull failed for '$PLUGIN_NAME'. Check $LOG_FILE for details."
      exit 1
    fi
  else
    log "Plugin directory exists but is not a git repo — re-cloning..."
    rm -rf "$PLUGIN_PATH"
    if ! git clone "$PLUGIN_REPO" "$PLUGIN_PATH" >> "$LOG_FILE" 2>&1; then
      log_error "Failed to re-clone $PLUGIN_REPO"
      notify "ClimWeb plugin update FAILED: $PLUGIN_NAME" \
        "Could not re-clone $PLUGIN_REPO. Check $LOG_FILE for details."
      exit 1
    fi
  fi

  log "Restarting containers to apply plugin update..."
  docker compose up -d --force-recreate >> "$LOG_FILE" 2>&1

  log_success "Plugin '$PLUGIN_NAME' updated successfully."
  notify "ClimWeb plugin updated: $PLUGIN_NAME" \
    "Plugin '$PLUGIN_NAME' has been updated."

# =============================================================================
# REMOVE
# =============================================================================
elif [[ "$ACTION" == "remove" ]]; then
  if [[ ! -d "$PLUGIN_PATH" ]]; then
    log_error "Plugin '$PLUGIN_NAME' is not installed at $PLUGIN_PATH."
    exit 1
  fi

  log "Reversing migrations for '$PLUGIN_NAME' before removal..."
  docker compose exec -T climweb python manage.py migrate "$PLUGIN_NAME" zero >> "$LOG_FILE" 2>&1 || \
    log "No migrations to reverse for '$PLUGIN_NAME' (or migration reversal not supported) — continuing."

  log "Removing plugin directory $PLUGIN_PATH ..."
  rm -rf "$PLUGIN_PATH"

  log "Restarting containers..."
  docker compose up -d --force-recreate >> "$LOG_FILE" 2>&1

  log_success "Plugin '$PLUGIN_NAME' removed successfully."
  notify "ClimWeb plugin removed: $PLUGIN_NAME" \
    "Plugin '$PLUGIN_NAME' has been removed."

else
  log_error "Unknown action: '$ACTION'. Must be one of: install, update, remove"
  exit 1
fi

exit 0
