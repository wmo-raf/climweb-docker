#!/bin/bash
set -euo pipefail

# =============================================================================
# ClimWeb Plugin Removal Script
# Usage: ./webhook/scripts/plugin-remove.sh <plugin_folder_name>
#
# Safely removes an installed plugin:
#   1. Reverses its database migrations
#   2. Deletes its directory from CLIMWEB_PLUGIN_VOLUME
#   3. Removes its repo URL from CLIMWEB_PLUGIN_GIT_REPOS in .env
#   4. Restarts containers
# =============================================================================

# --- Configuration -----------------------------------------------------------
env_file=".env"
LOG_FILE="./logs/climweb-plugin.log"
LOCKFILE="/tmp/climweb-plugin.lock"

export PATH="/Applications/Docker.app/Contents/Resources/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"

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

# --- Cleanup on exit ---------------------------------------------------------
cleanup() {
  rm -f "$LOCKFILE"
}
trap cleanup EXIT

# --- Input validation --------------------------------------------------------
PLUGIN_NAME="${1:-}"

if [[ -z "$PLUGIN_NAME" ]]; then
  echo "Usage: plugin-remove.sh <plugin_name>"
  echo "  plugin_name: the folder name of the plugin, e.g. dataset_helper_plugin"
  exit 1
fi

# --- Prevent concurrent operations -------------------------------------------
if [[ -e "$LOCKFILE" ]]; then
  log_error "Another plugin operation is already in progress. Exiting."
  exit 1
fi
touch "$LOCKFILE"

# --- Resolve plugin directory ------------------------------------------------
CLIMWEB_PLUGIN_VOLUME=$(grep -E "^CLIMWEB_PLUGIN_VOLUME=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || true)
CLIMWEB_PLUGIN_VOLUME="${CLIMWEB_PLUGIN_VOLUME:-./climweb/plugins}"
PLUGIN_PATH="$CLIMWEB_PLUGIN_VOLUME/$PLUGIN_NAME"

if [[ ! -d "$PLUGIN_PATH" ]]; then
  log_error "Plugin '$PLUGIN_NAME' not found at $PLUGIN_PATH."
  exit 1
fi

log "============================================================"
log "Removing plugin: $PLUGIN_NAME"

# --- 1. Reverse database migrations ------------------------------------------
log "Reversing database migrations for '$PLUGIN_NAME'..."
docker compose exec -T climweb climweb migrate "$PLUGIN_NAME" zero >> "$LOG_FILE" 2>&1 || \
  log "No migrations to reverse for '$PLUGIN_NAME' (or reversal not supported) — continuing."

# --- 2. Determine repo URL before deleting the directory ---------------------
REPO_URL=""
if [[ -f "$PLUGIN_PATH/.plugin_repo_url" ]]; then
  REPO_URL=$(cat "$PLUGIN_PATH/.plugin_repo_url")
elif [[ -d "$PLUGIN_PATH/.git" ]]; then
  REPO_URL=$(git -C "$PLUGIN_PATH" remote get-url origin 2>/dev/null || true)
fi

# Fallback: match plugin name against repo URLs in CLIMWEB_PLUGIN_GIT_REPOS.
# Normalises each repo's basename (strip .git, replace hyphens with underscores)
# and compares against the plugin folder name.
if [[ -z "$REPO_URL" ]]; then
  CURRENT_REPOS=$(grep -E "^CLIMWEB_PLUGIN_GIT_REPOS=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || true)
  if [[ -n "$CURRENT_REPOS" ]]; then
    while IFS= read -r candidate; do
      candidate=$(echo "$candidate" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
      [[ -z "$candidate" ]] && continue
      # Extract basename, strip .git suffix, normalise hyphens to underscores
      basename="${candidate##*/}"
      basename="${basename%.git}"
      normalized=$(echo "$basename" | tr '-' '_')
      if [[ "$normalized" == "$PLUGIN_NAME" ]]; then
        REPO_URL="$candidate"
        log "Matched repo URL by name: $REPO_URL"
        break
      fi
    done < <(echo "$CURRENT_REPOS" | tr ',' '\n')
  fi
fi

# --- 3. Remove plugin directory ----------------------------------------------
log "Removing plugin directory $PLUGIN_PATH ..."
rm -rf "$PLUGIN_PATH"

# --- 4. Remove repo URL from CLIMWEB_PLUGIN_GIT_REPOS in .env ---------------
if [[ -n "$REPO_URL" ]]; then
  log "Removing $REPO_URL from CLIMWEB_PLUGIN_GIT_REPOS in .env ..."

  CURRENT_REPOS=$(grep -E "^CLIMWEB_PLUGIN_GIT_REPOS=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || true)

  # Split on commas, drop the matching URL, rejoin — handles leading/trailing spaces.
  # grep -vF returns exit 1 when all lines are filtered (e.g. only one URL was listed);
  # wrap in a subshell with || true so pipefail doesn't abort the script.
  NEW_REPOS=$(echo "$CURRENT_REPOS" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | { grep -vF "$REPO_URL" || true; } | paste -sd ',' -)

  env_content=$(sed "s|^CLIMWEB_PLUGIN_GIT_REPOS=.*|CLIMWEB_PLUGIN_GIT_REPOS=${NEW_REPOS}|" "$env_file")
  echo "$env_content" > "$env_file"
  log "CLIMWEB_PLUGIN_GIT_REPOS updated."
else
  log "WARNING: Could not determine repo URL for '$PLUGIN_NAME'."
  log "Please manually remove its entry from CLIMWEB_PLUGIN_GIT_REPOS in .env."
fi

# --- 5. Restart containers ---------------------------------------------------
log "Restarting containers..."
docker compose up -d --force-recreate >> "$LOG_FILE" 2>&1

log_success "Plugin '$PLUGIN_NAME' removed successfully."

exit 0
