#!/bin/bash
set -euo pipefail

# =============================================================================
# ClimWeb Restore Script
# Restores a database and media backup, then runs Django migrations to
# reconcile any schema differences between the backup version and the
# currently running climweb version.
#
# Usage:
#   bash scripts/restore.sh                    # restore latest backup
#   bash scripts/restore.sh --db-only          # skip media restore
#   bash scripts/restore.sh --media-only       # skip DB restore
#   bash scripts/restore.sh --no-migrate       # skip post-restore migration
#                                               # (only safe if versions match)
# =============================================================================

ENV_FILE=".env"
LOG_FILE="./logs/climweb-restore.log"

# ---------------------------------------------------------------------------
# Parse flags
# ---------------------------------------------------------------------------
DO_DB=true
DO_MEDIA=true
DO_MIGRATE=true

for arg in "$@"; do
  case "$arg" in
    --db-only)      DO_MEDIA=false ;;
    --media-only)   DO_DB=false; DO_MIGRATE=false ;;
    --no-migrate)   DO_MIGRATE=false ;;
  esac
done

mkdir -p "$(dirname "$LOG_FILE")"

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOG_FILE"
}

log_error() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ERROR: $*" | tee -a "$LOG_FILE" >&2
}

log_warn() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] WARNING: $*" | tee -a "$LOG_FILE"
}

# ---------------------------------------------------------------------------
# Read config from .env
# ---------------------------------------------------------------------------
if [[ ! -f "$ENV_FILE" ]]; then
  log_error ".env not found. Run this script from the climweb-docker directory."
  exit 1
fi

CLIMWEB_VERSION=$(grep -E "^CLIMWEB_VERSION=" "$ENV_FILE" | cut -d'=' -f2- | tr -d '"')
CMS_DB_USER=$(grep -E "^CMS_DB_USER=" "$ENV_FILE" | cut -d'=' -f2- | tr -d '"')
CMS_DB_NAME=$(grep -E "^CMS_DB_NAME=" "$ENV_FILE" | cut -d'=' -f2- | tr -d '"')
BACKUP_VOLUME=$(grep -E "^BACKUP_VOLUME=" "$ENV_FILE" 2>/dev/null | cut -d'=' -f2- | tr -d '"' || true)
BACKUP_DIR="${BACKUP_VOLUME:-./climweb/backup}"

if [[ -z "$CLIMWEB_VERSION" ]]; then
  log_error "CLIMWEB_VERSION not found in $ENV_FILE"
  exit 1
fi

log "============================================================"
log "ClimWeb Restore — target version: v$CLIMWEB_VERSION"

# ---------------------------------------------------------------------------
# Check backup manifest for version mismatch warning
# ---------------------------------------------------------------------------
MANIFEST_FILE="$BACKUP_DIR/backup-manifest.json"
BACKUP_VERSION="unknown"

if [[ -f "$MANIFEST_FILE" ]]; then
  # Extract version from manifest (simple grep, no jq dependency)
  BACKUP_VERSION=$(grep '"climweb_version"' "$MANIFEST_FILE" | sed 's/.*"climweb_version": *"\([^"]*\)".*/\1/' || echo "unknown")
  BACKUP_DATE=$(grep '"backup_date"' "$MANIFEST_FILE" | sed 's/.*"backup_date": *"\([^"]*\)".*/\1/' || echo "unknown")
  log "Backup manifest found: version=$BACKUP_VERSION, date=$BACKUP_DATE"

  if [[ "$BACKUP_VERSION" != "unknown" && "$BACKUP_VERSION" != "$CLIMWEB_VERSION" ]]; then
    log_warn "Version mismatch detected!"
    log_warn "  Backup was created with : v$BACKUP_VERSION"
    log_warn "  Current running version : v$CLIMWEB_VERSION"
    log_warn "  Django migrations will be run after restore to reconcile the schema."
    if [[ "$DO_MIGRATE" == false ]]; then
      log_warn "  --no-migrate was passed. This may leave the database in an inconsistent state."
      log_warn "  Only use --no-migrate if you are certain the versions are compatible."
    fi
  fi
else
  log_warn "No backup-manifest.json found in $BACKUP_DIR."
  log_warn "Cannot verify backup version. Proceeding — migrations will still run after restore."
fi

# ---------------------------------------------------------------------------
# Confirm before proceeding (interactive only)
# ---------------------------------------------------------------------------
if [[ -t 0 ]]; then
  echo ""
  echo "  This will OVERWRITE the current database and/or media files."
  echo "  Backup version : ${BACKUP_VERSION}"
  echo "  Target version : ${CLIMWEB_VERSION}"
  echo ""
  read -r -p "  Are you sure you want to continue? [y/N] " CONFIRM
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "Restore cancelled."
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# DB Restore
# ---------------------------------------------------------------------------
if [[ "$DO_DB" == true ]]; then
  log "Preparing database for restore..."

  # Drop PostGIS topology and tiger extensions — they block a clean restore
  log "Dropping PostGIS auxiliary extensions (postgis_topology, postgis_tiger_geocoder)..."
  docker compose exec -T climweb_db psql -U "$CMS_DB_USER" -d "$CMS_DB_NAME" \
    -c "DROP EXTENSION IF EXISTS postgis_topology CASCADE;" \
    -c "DROP EXTENSION IF EXISTS postgis_tiger_geocoder CASCADE;" \
    >> "$LOG_FILE" 2>&1 || {
      log_warn "Could not drop PostGIS extensions (they may not exist — that is fine)."
    }

  log "Running dbrestore..."
  if docker compose exec -T climweb climweb dbrestore --noinput >> "$LOG_FILE" 2>&1; then
    log "Database restore complete."
  else
    log_error "dbrestore failed. Check $LOG_FILE for details."
    exit 1
  fi

  # -------------------------------------------------------------------------
  # Run Django migrations to reconcile schema after cross-version restore
  # -------------------------------------------------------------------------
  if [[ "$DO_MIGRATE" == true ]]; then
    log "Running Django migrations to reconcile schema..."
    if docker compose exec -T climweb climweb migrate --noinput >> "$LOG_FILE" 2>&1; then
      log "Migrations complete."
    else
      log_error "Migration failed. The database may be in an inconsistent state."
      log_error "Check $LOG_FILE and consider restoring again or contacting support."
      exit 1
    fi
  else
    log_warn "Skipping migrations (--no-migrate). Make sure the schema is compatible."
  fi
fi

# ---------------------------------------------------------------------------
# Media Restore
# ---------------------------------------------------------------------------
if [[ "$DO_MEDIA" == true ]]; then
  log "Running mediarestore..."
  if docker compose exec -T climweb climweb mediarestore --noinput >> "$LOG_FILE" 2>&1; then
    log "Media restore complete."
  else
    log_warn "mediarestore failed — check $LOG_FILE. Media can be re-synced manually if needed."
  fi
fi

log "============================================================"
log "Restore finished successfully."
log "  Restored from backup version : v${BACKUP_VERSION}"
log "  Running climweb version      : v${CLIMWEB_VERSION}"
if [[ "$BACKUP_VERSION" != "$CLIMWEB_VERSION" && "$DO_MIGRATE" == true ]]; then
  log "  Schema migrations were applied to bring the DB up to date."
fi
