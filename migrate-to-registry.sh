#!/bin/bash
# =============================================================================
# ClimWeb: migrate from source-build deployment (deploy/no-registry branch)
# to the registry-based deployment (main branch, ghcr.io images).
#
# Run ONCE per server, from the climweb-docker project root, as root:
#
#   sudo bash migrate-to-registry.sh [options]
#
# Options:
#   --version <X.Y.Z>          ClimWeb version (image tag) to deploy.
#                              Default: keep CLIMWEB_VERSION from .env
#   --ssl-mode <mode>          plain | letsencrypt | npm | custom
#                              Default: plain (plain HTTP on port 80)
#   --plugin-repos <urls>      Comma-separated git repo URLs for plugins.
#                              Default: https://github.com/fgg-consultant/dataset-helper-plugin
#   --healthcheck-url <url>    Default: derived from CMS_BASE_URL, else
#                              http://localhost:<CMS_PORT>/api/_health/
#   --skip-backup              Skip db/media backup snapshot (NOT recommended)
#   -h | --help                Show help
#
# What it does (in order):
#   1. Preflight checks (root, repo, docker, git, running stack)
#   2. Latest db + media backup snapshot, copied to ../climweb-backup-<date>
#   3. Saves current nginx.conf, docker-compose.yml, Dockerfiles, .env as *.old
#   4. Patches .env with new required variables
#   5. Stops the old stack
#   6. Fixes volume ownership (1001:1001)
#   7. Switches the repo to origin/main
#   8. Installs new docker-compose.yml + nginx.conf from samples (per ssl-mode)
#   9. Configures the webhook listener + supervisor (CMS-triggered upgrades)
#  10. Installs make if missing, starts the new stack (pulls ghcr images)
#  11. Health check; automatic ROLLBACK to the old deployment on failure
#
# Log: logs/migrate-to-registry-<timestamp>.log
# =============================================================================

set -uo pipefail

# --- Defaults ----------------------------------------------------------------
SSL_MODE="plain"
PLUGIN_REPOS="https://github.com/fgg-consultant/dataset-helper-plugin"
TARGET_VERSION=""
HEALTHCHECK_URL=""
SKIP_BACKUP="false"
NEW_BRANCH="main"
RUN_UID=1001
RUN_GID=1001

HEALTH_RETRIES=45          # 45 x 10s = ~7.5 min (first image pull can be slow)
HEALTH_INTERVAL=10

TS="$(date +%Y%m%d-%H%M%S)"
LOCKFILE="/tmp/climweb-migrate.lock"

usage() { sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

# --- Parse args ----------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)          TARGET_VERSION="${2:-}"; shift 2 ;;
    --ssl-mode)         SSL_MODE="${2:-}"; shift 2 ;;
    --plugin-repos)     PLUGIN_REPOS="${2:-}"; shift 2 ;;
    --healthcheck-url)  HEALTHCHECK_URL="${2:-}"; shift 2 ;;
    --skip-backup)      SKIP_BACKUP="true"; shift ;;
    -h|--help)          usage ;;
    *) echo "Unknown option: $1 (see --help)"; exit 1 ;;
  esac
done

case "$SSL_MODE" in plain|letsencrypt|npm|custom) ;; *)
  echo "Invalid --ssl-mode '$SSL_MODE'. Use: plain | letsencrypt | npm | custom"; exit 1 ;;
esac

# --- Logging -------------------------------------------------------------------
mkdir -p logs
LOG_FILE="logs/migrate-to-registry-$TS.log"
log()   { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOG_FILE"; }
fail()  { echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ERROR: $*" | tee -a "$LOG_FILE" >&2; exit 1; }

run() { log "+ $*"; "$@" >> "$LOG_FILE" 2>&1; }

# --- .env helper ---------------------------------------------------------------
env_file=".env"

get_env() { grep -E "^$1=" "$env_file" 2>/dev/null | head -1 | cut -d'=' -f2- | tr -d '"'; }

set_env() {
  local key="$1" value="$2"
  if grep -qE "^$key=" "$env_file"; then
    # portable in-place edit (no sed -i differences)
    local tmp; tmp="$(mktemp)"
    sed "s|^$key=.*|$key=$value|" "$env_file" > "$tmp" && cat "$tmp" > "$env_file" && rm -f "$tmp"
  else
    # ensure trailing newline, then append
    [[ -n "$(tail -c1 "$env_file")" ]] && echo >> "$env_file"
    echo "$key=$value" >> "$env_file"
  fi
  log "  .env: $key set"
}

# =============================================================================
# 1. PREFLIGHT
# =============================================================================
log "=== ClimWeb migration to registry-based deployment (log: $LOG_FILE) ==="

[[ $EUID -eq 0 ]] || fail "Must run as root: sudo bash migrate-to-registry.sh"
[[ -e "$LOCKFILE" ]] && fail "Another migration appears to be running (rm $LOCKFILE if stale)."
touch "$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

[[ -f "$env_file" ]] || fail "No .env found. Run this from the climweb-docker project root."
[[ -d .git ]] || fail "Not a git repository. Run this from the climweb-docker project root."
command -v docker >/dev/null || fail "docker not found on PATH."
docker compose version >/dev/null 2>&1 || fail "docker compose (v2 plugin) not available."
command -v git >/dev/null || fail "git not found."
command -v curl >/dev/null || fail "curl not found."

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
CURRENT_COMMIT="$(git rev-parse HEAD)"
log "Current branch: $CURRENT_BRANCH ($CURRENT_COMMIT)"

if [[ "$CURRENT_BRANCH" == "$NEW_BRANCH" ]] && grep -q "ghcr.io/wmo-raf/climweb" docker-compose.yml 2>/dev/null; then
  log "Already on '$NEW_BRANCH' with a registry-based docker-compose.yml. Nothing to do."
  exit 0
fi

run git fetch origin "$NEW_BRANCH" || fail "Cannot reach git remote. Check internet access."

CURRENT_VERSION="$(get_env CLIMWEB_VERSION)"
[[ -n "$CURRENT_VERSION" ]] || fail "CLIMWEB_VERSION not set in .env"
DEPLOY_VERSION="${TARGET_VERSION:-$CURRENT_VERSION}"
log "ClimWeb version: current=$CURRENT_VERSION target=$DEPLOY_VERSION"

# Verify the target image tag exists in the registry before touching anything
log "Verifying image ghcr.io/wmo-raf/climweb:v$DEPLOY_VERSION exists..."
if ! docker manifest inspect "ghcr.io/wmo-raf/climweb:v$DEPLOY_VERSION" >> "$LOG_FILE" 2>&1; then
  fail "Image tag v$DEPLOY_VERSION not found in ghcr.io/wmo-raf/climweb. Pass a valid --version."
fi

if ! docker compose ps --status running 2>/dev/null | grep -q climweb; then
  log "WARNING: climweb containers do not appear to be running. Backup snapshot may fail."
fi

# Record the UID/GID the old deployment ran with (for permission-safe rollback)
OLD_UID="$(get_env UID)"
OLD_GID="$(get_env GID)"

# Pre-pull the new images while the old stack is still serving, to keep the
# downtime window as short as possible.
log "Pre-pulling registry images (site stays up during this)..."
run docker pull "ghcr.io/wmo-raf/climweb:v$DEPLOY_VERSION" || fail "Failed to pull climweb image."
run docker pull "ghcr.io/wmo-raf/geomapviewer:latest" || log "WARNING: could not pre-pull geomapviewer image."

# Healthcheck URL: flag > derived from CMS_BASE_URL > localhost
if [[ -z "$HEALTHCHECK_URL" ]]; then
  CMS_PORT="$(get_env CMS_PORT)"; CMS_PORT="${CMS_PORT:-80}"
  BASE_URL="$(get_env CMS_BASE_URL)"
  if [[ -n "$BASE_URL" ]]; then
    HEALTHCHECK_URL="${BASE_URL%/}/api/_health/"
  else
    HEALTHCHECK_URL="http://localhost:${CMS_PORT}/api/_health/"
  fi
fi
log "Healthcheck URL: $HEALTHCHECK_URL"

# =============================================================================
# 2. BACKUP SNAPSHOT (db + media)
# =============================================================================
if [[ "$SKIP_BACKUP" == "true" ]]; then
  log "Skipping backup snapshot (--skip-backup)."
else
  log "Creating latest db + media backup snapshot..."
  run docker compose exec -T climweb /bin/bash -c "climweb dbbackup --clean --noinput" \
    || fail "dbbackup failed — aborting before making any changes. Check $LOG_FILE."
  run docker compose exec -T climweb /bin/bash -c "climweb mediabackup --clean --noinput" \
    || fail "mediabackup failed — aborting before making any changes. Check $LOG_FILE."

  BACKUP_SRC="$(get_env BACKUP_VOLUME)"; BACKUP_SRC="${BACKUP_SRC:-./climweb/backup}"
  BACKUP_DEST="../climweb-backup-$TS"

  # Disk space check: need room for the backup copy plus ~2GB headroom.
  # A full disk is far more dangerous than a failed migration.
  backup_kb="$(du -sk "$BACKUP_SRC" 2>/dev/null | cut -f1)"; backup_kb="${backup_kb:-0}"
  avail_kb="$(df -Pk .. | awk 'NR==2 {print $4}')"
  needed_kb=$(( backup_kb + 2097152 ))
  if [[ "$avail_kb" -lt "$needed_kb" ]]; then
    fail "Not enough disk space to copy backups safely (need ~$((needed_kb/1024)) MB, have $((avail_kb/1024)) MB). Free up space first."
  fi

  log "Copying backups to $BACKUP_DEST ..."
  run mkdir -p "$BACKUP_DEST"
  run cp -r "$BACKUP_SRC/." "$BACKUP_DEST/" || fail "Failed to copy backup dir."
  log "Backup snapshot saved: $BACKUP_DEST"
fi

# =============================================================================
# 3. SAVE CURRENT CONFIG FILES AS *.old
# =============================================================================
log "Saving current config files as *.old ..."
cp nginx/nginx.conf nginx/nginx.conf.old 2>/dev/null       && log "  nginx/nginx.conf.old"
cp docker-compose.yml docker-compose.yml.old 2>/dev/null   && log "  docker-compose.yml.old"
cp climweb/Dockerfile climweb-dockerfile.old 2>/dev/null   && log "  climweb-dockerfile.old"
cp mapviewer/Dockerfile mapviewer-dockerfile.old 2>/dev/null && log "  mapviewer-dockerfile.old"
cp "$env_file" ".env.old"                                  && log "  .env.old"

# =============================================================================
# 4. PATCH .env
# =============================================================================
log "Patching .env ..."
set_env CMS_UPGRADE_HOOK_URL "http://host.docker.internal:9000/hooks/cms-upgrade"
set_env CMS_PLUGIN_MANAGE_HOOK_URL "http://host.docker.internal:9000/hooks/plugin-remove"
set_env CMS_HEALTHCHECK_URL "$HEALTHCHECK_URL"
set_env CLIMWEB_PLUGIN_GIT_REPOS "$PLUGIN_REPOS"
set_env CLIMWEB_PLUGIN_VOLUME "./climweb/plugins"
set_env UID "$RUN_UID"
set_env GID "$RUN_GID"
set_env IS_METEOROLOGICAL "True"
[[ -n "$TARGET_VERSION" ]] && set_env CLIMWEB_VERSION "$TARGET_VERSION"

# =============================================================================
# 5. STOP OLD STACK
# =============================================================================
log "Stopping old stack..."
run docker compose stop || fail "docker compose stop failed."

# =============================================================================
# 6. FIX VOLUME OWNERSHIP
# =============================================================================
log "Fixing volume ownership ($RUN_UID:$RUN_GID)..."
mkdir -p climweb/plugins climweb/backup climweb/media climweb/static
for d in climweb/backup climweb/media climweb/static climweb/plugins; do
  run chown -R "$RUN_UID:$RUN_GID" "$d" || fail "chown failed on $d"
done

# =============================================================================
# 7. SWITCH REPO TO main
# =============================================================================
log "Switching repository to origin/$NEW_BRANCH ..."
# .env, docker-compose.yml, nginx/nginx.conf and *.old are gitignored/untracked
# and survive the switch. Local edits to tracked files are discarded (backed
# up above). Previous state recorded at $CURRENT_COMMIT for rollback.

# Preserve any local edits to tracked files as a patch, in case this instance
# had customizations beyond the files backed up above.
if ! git diff --quiet HEAD 2>/dev/null; then
  git diff HEAD > "local-changes-$TS.patch" 2>/dev/null || true
  log "Local changes to tracked files saved to local-changes-$TS.patch"
fi
run git checkout -f "$NEW_BRANCH" || run git checkout -f -b "$NEW_BRANCH" "origin/$NEW_BRANCH" \
  || fail "git checkout $NEW_BRANCH failed."
run git reset --hard "origin/$NEW_BRANCH" || fail "git reset to origin/$NEW_BRANCH failed."
log "Now at: $(git rev-parse HEAD)"

# =============================================================================
# ROLLBACK HANDLER (available from here on)
# =============================================================================
rollback() {
  log "!!! ROLLING BACK to previous deployment ($CURRENT_BRANCH @ $CURRENT_COMMIT) !!!"
  docker compose down --remove-orphans >> "$LOG_FILE" 2>&1 || true
  # move the original branch pointer back to the pre-migration commit
  git checkout -f "$CURRENT_BRANCH" >> "$LOG_FILE" 2>&1 || true
  git reset --hard "$CURRENT_COMMIT" >> "$LOG_FILE" 2>&1 || true
  [[ -f docker-compose.yml.old ]] && cp docker-compose.yml.old docker-compose.yml
  [[ -f nginx/nginx.conf.old ]] && cp nginx/nginx.conf.old nginx/nginx.conf
  [[ -f .env.old ]] && cp .env.old "$env_file"
  [[ -f climweb-dockerfile.old ]] && mkdir -p climweb && cp climweb-dockerfile.old climweb/Dockerfile
  [[ -f mapviewer-dockerfile.old ]] && mkdir -p mapviewer && cp mapviewer-dockerfile.old mapviewer/Dockerfile
  # restore volume ownership to what the old deployment ran with
  if [[ -n "$OLD_UID" && "$OLD_UID" != "$RUN_UID" ]]; then
    log "Restoring volume ownership to $OLD_UID:${OLD_GID:-$OLD_UID} ..."
    for d in climweb/backup climweb/media climweb/static; do
      chown -R "$OLD_UID:${OLD_GID:-$OLD_UID}" "$d" >> "$LOG_FILE" 2>&1 || true
    done
  fi
  docker compose up -d >> "$LOG_FILE" 2>&1 \
    && log "Rollback complete — old stack restarted (using existing local images)." \
    || log "Rollback attempted but 'docker compose up -d' failed. MANUAL INTERVENTION NEEDED. See $LOG_FILE."
  exit 1
}

# =============================================================================
# 8. INSTALL NEW docker-compose.yml + nginx.conf
# =============================================================================
log "Installing new compose/nginx config (ssl-mode: $SSL_MODE)..."
case "$SSL_MODE" in
  plain)
    cp docker-compose.yml.sample docker-compose.yml || rollback
    cp nginx/nginx.conf.sample nginx/nginx.conf || rollback
    ;;
  letsencrypt)
    cp docker-compose.letsencrypt.yml docker-compose.yml || rollback
    # keep existing nginx.conf (has the site's SSL config); it was saved as .old too
    log "  Kept existing nginx/nginx.conf (Let's Encrypt SSL). Review against nginx/nginx.certbot.conf if needed."
    ;;
  npm)
    cp docker-compose.yml.sample docker-compose.yml || rollback
    cp nginx/nginx.conf.sample nginx/nginx.conf || rollback
    log "  NOTE: Nginx Proxy Manager stack (nginx-proxy-manager/docker-compose.yaml) is managed separately."
    ;;
  custom)
    cp docker-compose.yml.sample docker-compose.yml || rollback
    log "  Kept existing nginx/nginx.conf (custom SSL). Old copy: nginx/nginx.conf.old"
    ;;
esac

# =============================================================================
# 9. WEBHOOK LISTENER + SUPERVISOR (enables CMS-Admin driven upgrades)
# =============================================================================
log "Setting up webhook listener..."

export DEBIAN_FRONTEND=noninteractive
if ! command -v webhook >/dev/null; then
  log "Installing webhook package..."
  run apt-get update -y
  run apt-get install -y webhook || rollback
fi
if ! command -v supervisorctl >/dev/null; then
  log "Installing supervisor..."
  run apt-get install -y supervisor || rollback
fi

run sh webhook-config.sh || rollback

SUPERVISOR_CONF="/etc/supervisor/conf.d/webhook.conf"
if [[ ! -f "$SUPERVISOR_CONF" ]]; then
  log "Creating $SUPERVISOR_CONF ..."
  cat > "$SUPERVISOR_CONF" << EOF
[program:webhook]
command=$(command -v webhook) -hooks $(pwd)/webhook/hooks.yaml -verbose
directory=$(pwd)
autostart=true
autorestart=true
startretries=3
startsecs=0
EOF
fi
run supervisorctl reread
run supervisorctl update
# restart so the running webhook picks up the regenerated hooks.yaml
run supervisorctl restart webhook || true
supervisorctl status webhook | tee -a "$LOG_FILE" || true

# =============================================================================
# 10. START NEW STACK
# =============================================================================
command -v make >/dev/null || { log "Installing make..."; run apt-get install -y make || rollback; }

log "Pulling registry images and starting new stack (this may take a while)..."
run make start || rollback

# =============================================================================
# 11. HEALTH CHECK
# =============================================================================
log "Waiting for CMS to become healthy at $HEALTHCHECK_URL ..."
healthy="false"
for i in $(seq 1 "$HEALTH_RETRIES"); do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$HEALTHCHECK_URL" || true)"
  if [[ "$code" == "200" ]]; then healthy="true"; break; fi
  log "  attempt $i/$HEALTH_RETRIES: HTTP ${code:-timeout} — retrying in ${HEALTH_INTERVAL}s"
  sleep "$HEALTH_INTERVAL"
done

if [[ "$healthy" != "true" ]]; then
  log "Health check FAILED after $HEALTH_RETRIES attempts."
  rollback
fi

log "============================================================"
log "SUCCESS: migrated to registry-based deployment (v$DEPLOY_VERSION)"
log "  - Backup snapshot: ../climweb-backup-$TS"
log "  - Old configs kept: *.old files in project root and nginx/"
log "  - Webhook listener running — upgrades can now be triggered from CMS Admin"
log "  - Log file: $LOG_FILE"
log "============================================================"
