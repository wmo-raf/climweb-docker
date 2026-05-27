#!/bin/bash
set -euo pipefail

# =============================================================================
# ClimWeb Upgrade Script
# Triggered by the cms-upgrade webhook when a new version is available.
# =============================================================================

# --- Configuration -----------------------------------------------------------
env_file=".env"
LOG_FILE="./logs/climweb-upgrade.log"
LOCKFILE="/tmp/climweb-upgrade.lock"

# Ensure docker is on PATH (supervisor runs with a minimal environment)
export PATH="/Applications/Docker.app/Contents/Resources/bin:/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:$PATH"
HEALTH_CHECK_RETRIES=12   # 12 x 10s = 2 minutes
HEALTH_CHECK_INTERVAL=10  # seconds between retries

# Status file written into the backup volume so Django can read it
BACKUP_VOLUME=$(grep -E "^BACKUP_VOLUME=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || true)
BACKUP_DIR="${BACKUP_VOLUME:-./climweb/backup}"
STATUS_FILE="$BACKUP_DIR/upgrade-status.json"

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

# --- Status file -------------------------------------------------------------
write_status() {
  local status="$1"   # in_progress | success | failed | rolling_back
  local step="$2"     # human-readable description of current step

  mkdir -p "$BACKUP_DIR"
  cat > "$STATUS_FILE" << EOF
{
  "status": "$status",
  "step": "$step",
  "from_version": "${CURRENT_CLIMWEB_VERSION:-unknown}",
  "to_version": "${NEW_CLIMWEB_VERSION:-unknown}",
  "updated_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
}

# --- Rollback ----------------------------------------------------------------
_rollback() {
  local rollback_version="$1"
  log "Rolling back to v$rollback_version..."
  write_status "rolling_back" "Rolling back to v$rollback_version..."

  # Restore version in .env
  local restored_env
  restored_env=$(sed "s/^CLIMWEB_VERSION=.*/CLIMWEB_VERSION=$rollback_version/" "$env_file")
  echo "$restored_env" > "$env_file"

  # Pull and restart with the old image
  CLIMWEB_VERSION="$rollback_version" docker compose pull >> "$LOG_FILE" 2>&1 || true
  docker compose up -d --force-recreate >> "$LOG_FILE" 2>&1 || true

  log_error "Rolled back to v$rollback_version. Manual intervention may be needed. Check $LOG_FILE."
  write_status "failed" "Rolled back to v$rollback_version. Upgrade failed — check server logs."
  notify "ClimWeb upgrade FAILED — rolled back to v$rollback_version" \
    "Upgrade to v$NEW_CLIMWEB_VERSION failed. The system has been rolled back to v$rollback_version. Check $LOG_FILE for details."
}

# --- Cleanup on exit ---------------------------------------------------------
cleanup() {
  rm -f "$LOCKFILE"
}
trap cleanup EXIT

# --- Input validation --------------------------------------------------------
NEW_CLIMWEB_VERSION="${1:-}"

if [[ -z "$NEW_CLIMWEB_VERSION" ]]; then
  log_error "No version passed. Usage: cms-upgrade.sh <version>"
  exit 1
fi

# --- Prevent concurrent upgrades ---------------------------------------------
if [[ -e "$LOCKFILE" ]]; then
  log_error "Another upgrade is already in progress (lockfile: $LOCKFILE). Exiting."
  exit 1
fi
touch "$LOCKFILE"

log "============================================================"
log "Upgrade requested: $NEW_CLIMWEB_VERSION"
write_status "in_progress" "Upgrade requested: v$NEW_CLIMWEB_VERSION"

# --- Read current version from .env ------------------------------------------
if [[ ! -f "$env_file" ]]; then
  log_error ".env file not found at $env_file"
  exit 1
fi

CURRENT_CLIMWEB_VERSION=$(grep -E "^CLIMWEB_VERSION=" "$env_file" | cut -d'=' -f2- | tr -d '"')

if [[ -z "$CURRENT_CLIMWEB_VERSION" ]]; then
  log_error "CLIMWEB_VERSION not found in $env_file"
  exit 1
fi

log "Current version: $CURRENT_CLIMWEB_VERSION"

if [[ "$NEW_CLIMWEB_VERSION" == "$CURRENT_CLIMWEB_VERSION" ]]; then
  log "Already on version $CURRENT_CLIMWEB_VERSION — nothing to do."
  write_status "success" "Already on v$CURRENT_CLIMWEB_VERSION — nothing to do."
  exit 0
fi

# --- Read health check URL from .env -----------------------------------------
CMS_HEALTHCHECK_URL=$(grep -E "^CMS_HEALTHCHECK_URL=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || true)
CMS_PORT=$(grep -E "^CMS_PORT=" "$env_file" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || true)
CMS_PORT="${CMS_PORT:-80}"

if [[ -z "$CMS_HEALTHCHECK_URL" ]]; then
  CMS_HEALTHCHECK_URL="http://localhost:${CMS_PORT}/api/_health/"
fi

# --- Pre-upgrade backup ------------------------------------------------------
log "Taking pre-upgrade backup..."
write_status "in_progress" "Taking pre-upgrade database backup..."
if docker compose exec -T climweb climweb dbbackup --clean --noinput >> "$LOG_FILE" 2>&1; then
  log "Database backup complete."
else
  log_error "Database backup failed. Aborting upgrade to protect data."
  write_status "failed" "Database backup failed. Upgrade aborted to protect data."
  notify "ClimWeb upgrade ABORTED (v$CURRENT_CLIMWEB_VERSION → v$NEW_CLIMWEB_VERSION)" \
    "Pre-upgrade database backup failed. Upgrade was aborted. Check $LOG_FILE for details."
  exit 1
fi

write_status "in_progress" "Taking pre-upgrade media backup..."
if docker compose exec -T climweb climweb mediabackup --clean --noinput >> "$LOG_FILE" 2>&1; then
  log "Media backup complete."
else
  log "Media backup failed — continuing (media can be re-synced if needed)."
fi

# --- Pull new image from registry --------------------------------------------
log "Pulling new image: ghcr.io/wmo-raf/climweb:v$NEW_CLIMWEB_VERSION ..."
write_status "in_progress" "Pulling image ghcr.io/wmo-raf/climweb:v$NEW_CLIMWEB_VERSION..."

env_content=$(sed "s/^CLIMWEB_VERSION=.*/CLIMWEB_VERSION=$NEW_CLIMWEB_VERSION/" "$env_file")

if ! CLIMWEB_VERSION="$NEW_CLIMWEB_VERSION" docker compose pull >> "$LOG_FILE" 2>&1; then
  log_error "Failed to pull image for version $NEW_CLIMWEB_VERSION. The registry may not have this tag yet."
  write_status "failed" "Failed to pull image for v$NEW_CLIMWEB_VERSION. No changes were made."
  notify "ClimWeb upgrade FAILED (v$CURRENT_CLIMWEB_VERSION → v$NEW_CLIMWEB_VERSION)" \
    "Could not pull image for v$NEW_CLIMWEB_VERSION from the registry. No changes were made. Check $LOG_FILE for details."
  exit 1
fi

log "Image pull successful."

# --- Update .env with new version --------------------------------------------
log "Updating .env with new version..."
echo "$env_content" > "$env_file"

# --- Restart containers with new image ---------------------------------------
log "Restarting containers..."
write_status "in_progress" "Restarting containers with v$NEW_CLIMWEB_VERSION..."
if ! docker compose up -d --force-recreate >> "$LOG_FILE" 2>&1; then
  log_error "docker compose up failed. Rolling back to v$CURRENT_CLIMWEB_VERSION..."
  _rollback "$CURRENT_CLIMWEB_VERSION"
  exit 1
fi

# --- Post-upgrade health check -----------------------------------------------
log "Waiting for application to become healthy at $CMS_HEALTHCHECK_URL ..."
write_status "in_progress" "Waiting for application to become healthy..."

healthy=false
for ((i=1; i<=HEALTH_CHECK_RETRIES; i++)); do
  if curl -sf --max-time 5 "$CMS_HEALTHCHECK_URL" > /dev/null 2>&1; then
    healthy=true
    break
  fi
  log "Health check attempt $i/$HEALTH_CHECK_RETRIES failed — retrying in ${HEALTH_CHECK_INTERVAL}s..."
  write_status "in_progress" "Health check attempt $i/$HEALTH_CHECK_RETRIES — waiting for app to restart..."
  sleep "$HEALTH_CHECK_INTERVAL"
done

if [[ "$healthy" == false ]]; then
  log_error "Health check failed after $((HEALTH_CHECK_RETRIES * HEALTH_CHECK_INTERVAL))s. Rolling back to v$CURRENT_CLIMWEB_VERSION..."
  _rollback "$CURRENT_CLIMWEB_VERSION"
  exit 1
fi

# --- Success -----------------------------------------------------------------
log_success "Upgrade from v$CURRENT_CLIMWEB_VERSION to v$NEW_CLIMWEB_VERSION completed successfully."
write_status "success" "Upgrade to v$NEW_CLIMWEB_VERSION completed successfully."
notify "ClimWeb upgraded successfully to v$NEW_CLIMWEB_VERSION" \
  "ClimWeb has been upgraded from v$CURRENT_CLIMWEB_VERSION to v$NEW_CLIMWEB_VERSION successfully."

exit 0
