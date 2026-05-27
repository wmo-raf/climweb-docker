#!/bin/bash
set -euo pipefail

# =============================================================================
# ClimWeb Backup Script
# Runs a DB + media backup and writes a manifest recording the climweb version.
# This manifest is used by restore.sh to detect cross-version restores.
#
# Usage: bash scripts/backup.sh [--clean]
#   --clean   Pass --clean to dbbackup/mediabackup (keeps only the latest copy)
# =============================================================================

ENV_FILE=".env"
LOG_FILE="./logs/climweb-backup.log"

CLEAN_FLAG=""
for arg in "$@"; do
  [[ "$arg" == "--clean" ]] && CLEAN_FLAG="--clean"
done

mkdir -p "$(dirname "$LOG_FILE")"

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOG_FILE"
}

log_error() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

# ---------------------------------------------------------------------------
# Read config from .env
# ---------------------------------------------------------------------------
if [[ ! -f "$ENV_FILE" ]]; then
  log_error ".env not found. Run from the climweb-docker directory."
  exit 1
fi

CLIMWEB_VERSION=$(grep -E "^CLIMWEB_VERSION=" "$ENV_FILE" | cut -d'=' -f2- | tr -d '"')
BACKUP_VOLUME=$(grep -E "^BACKUP_VOLUME=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || true)
BACKUP_DIR="${BACKUP_VOLUME:-./climweb/backup}"

if [[ -z "$CLIMWEB_VERSION" ]]; then
  log_error "CLIMWEB_VERSION not found in $ENV_FILE"
  exit 1
fi

log "Starting backup for ClimWeb v$CLIMWEB_VERSION"

# ---------------------------------------------------------------------------
# Database backup
# ---------------------------------------------------------------------------
log "Running database backup..."
if docker compose exec -T climweb climweb dbbackup $CLEAN_FLAG --noinput >> "$LOG_FILE" 2>&1; then
  log "Database backup complete."
else
  log_error "Database backup failed."
  exit 1
fi

# ---------------------------------------------------------------------------
# Media backup
# ---------------------------------------------------------------------------
log "Running media backup..."
if docker compose exec -T climweb climweb mediabackup $CLEAN_FLAG --noinput >> "$LOG_FILE" 2>&1; then
  log "Media backup complete."
else
  log "Media backup failed — continuing (media can be re-synced if needed)."
fi

# ---------------------------------------------------------------------------
# Write version manifest alongside the backup files
# ---------------------------------------------------------------------------
MANIFEST_FILE="$BACKUP_DIR/backup-manifest.json"

# Find the most recently created .psql.bin file for reference
LATEST_DB_FILE=$(ls -t "$BACKUP_DIR"/*.psql.bin 2>/dev/null | head -1 || true)
LATEST_MEDIA_FILE=$(ls -t "$BACKUP_DIR"/*.tar 2>/dev/null | head -1 || true)

DB_FILENAME=$(basename "${LATEST_DB_FILE:-unknown}")
MEDIA_FILENAME=$(basename "${LATEST_MEDIA_FILE:-unknown}")

cat > "$MANIFEST_FILE" <<EOF
{
  "climweb_version": "$CLIMWEB_VERSION",
  "backup_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "db_file": "$DB_FILENAME",
  "media_file": "$MEDIA_FILENAME"
}
EOF

log "Manifest written to $MANIFEST_FILE"
log "Backup complete. Version: $CLIMWEB_VERSION | DB: $DB_FILENAME | Media: $MEDIA_FILENAME"
