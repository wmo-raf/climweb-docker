# Migrating ClimWeb to the registry-based deployment

This guide migrates a ClimWeb server from the old source-build deployment (`deploy/no-registry` branch) to the new registry-based deployment (`main` branch, prebuilt images from `ghcr.io`). It takes one command and about 10–20 minutes, most of it image download time.

After this migration, future ClimWeb upgrades are triggered directly from the CMS Admin interface — no server access needed.

## Prerequisites

You need terminal access to the server with root (sudo) privileges, internet access from the server (github.com and ghcr.io), and roughly 5 GB of free disk space for the new images and the backup snapshot.

## Run the migration

From the climweb-docker project directory (where `.env` lives):

```bash
cd /path/to/climweb-docker
curl -fsSL https://raw.githubusercontent.com/wmo-raf/climweb-docker/main/migrate-to-registry.sh -o migrate-to-registry.sh
sudo bash migrate-to-registry.sh --ssl-mode plain
```

The instance should already have been upgraded to the latest ClimWeb version from the CMS Admin before running this (the ClimWeb team will confirm when). The script then keeps the current version — same application, new deployment mechanism — which makes the migration much safer. Only pass `--version <X.Y.Z>` if the ClimWeb team explicitly asks you to change version during migration.

### Options

| Flag | Values | Notes |
|---|---|---|
| `--version` | e.g. `1.1.6` | ClimWeb version to deploy. Omit to keep the current one. The script verifies the image tag exists before changing anything. |
| `--ssl-mode` | `plain` (default), `letsencrypt`, `npm`, `custom` | `plain` = HTTP on port 80. `letsencrypt` keeps your existing SSL nginx.conf and uses `docker-compose.letsencrypt.yml`. `custom` keeps your existing nginx.conf. `npm` = behind Nginx Proxy Manager. |
| `--plugin-repos` | comma-separated git URLs | Defaults to the dataset-helper-plugin repo. |
| `--healthcheck-url` | URL | Defaults to `<CMS_BASE_URL>/api/_health/`. |
| `--skip-backup` | — | Not recommended. |

## What the script does

It snapshots the database and media (copied to `../climweb-backup-<timestamp>`), saves your current `docker-compose.yml`, `nginx/nginx.conf`, Dockerfiles and `.env` as `*.old`, patches `.env` with the new required variables, stops the old stack, fixes volume permissions, switches the repo to `main`, installs the new compose/nginx config, sets up the webhook listener (this is what lets the CMS Admin trigger upgrades), pulls the prebuilt images and starts the stack. It then polls the health endpoint for up to ~8 minutes. If the health check fails, it automatically rolls back to the old deployment and restarts it.

Everything is logged to `logs/migrate-to-registry-<timestamp>.log`.

## Verify

After the script reports SUCCESS, confirm the website loads in a browser, log in to the CMS Admin and check the version shown in the admin, and run `docker compose ps` — all containers should be `running`.

## If something goes wrong

The script rolls back automatically on failure. If you need to roll back manually:

```bash
docker compose down --remove-orphans
# <OLD_COMMIT> is printed near the top of the migration log as
# "Current branch: main (<commit>)"
git reset --hard <OLD_COMMIT>
cp docker-compose.yml.old docker-compose.yml
cp nginx/nginx.conf.old nginx/nginx.conf
cp .env.old .env
cp climweb-dockerfile.old climweb/Dockerfile
cp mapviewer-dockerfile.old mapviewer/Dockerfile
docker compose up -d
```

The database itself is never touched by the migration, and a full db + media backup snapshot is kept in `../climweb-backup-<timestamp>`.

One edge case to know about: the new version applies database migrations when it first starts. If the migration fails *after* that point and the old stack is restored, the old version may not run correctly against the newer database schema. In that case restore the database from the snapshot (`make restore`, or `bash scripts/restore.sh`) and contact the ClimWeb team before retrying.

If you hit a problem, send the log file `logs/migrate-to-registry-<timestamp>.log` back to the ClimWeb team.
