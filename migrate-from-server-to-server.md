# Migrating ClimWeb from One Remote Server to Another

This guide walks through migrating **ClimWeb** from an old server to a new server using Docker and Docker Compose.

---

## 🖥️ On the New Server

### Prerequisites

1. **Docker Engine & Docker Compose Plugin**

   Ensure Docker Engine is installed and running on the new server:

   👉 [https://docs.docker.com/engine/install/](https://docs.docker.com/engine/install/)

   Docker Engine provides the runtime environment for containers.

---

### ClimWeb Installation

#### 1. Download from source

```bash
git clone https://github.com/wmo-raf/climweb-docker.git climweb
cd climweb
```

#### 2. Copy Docker Compose configuration

```bash
cp docker-compose.yml.sample docker-compose.yml
```

#### 3. Copy Nginx configuration

```bash
cp nginx/nginx.conf.sample nginx/nginx.conf
```

#### 4. Verify ClimWeb path

```bash
pwd
```

---

## 🖥️ On the Old Server

### Create the Latest Backup Snapshot

From the `climweb-docker` directory, run:

```bash
make backup
```

This creates a DB backup, a media backup, and a `backup-manifest.json` that records the climweb version the backup was taken from. The `--clean` flag keeps only the latest copy of each.

> **Manual alternative** (if you need to keep previous backups):
> ```bash
> bash scripts/backup.sh
> ```

---

### Copy Backup Files to the New Server

Copy the entire backup directory — this includes the DB dump, media archive, and the version manifest:

```bash
scp climweb/backup/* user@NEW_IP_ADDRESS:CLIMWEB_PATH/climweb/backup/
```

---

### Copy Plugins to the New Server

If you have any plugins installed, copy the plugins directory so they are available on the new server:

```bash
scp -r climweb/plugins user@NEW_IP_ADDRESS:CLIMWEB_PATH/climweb/plugins
```

> Plugins are loaded automatically on container startup. No reinstallation is needed after copying.

---

### Copy `.env` File to the New Server

```bash
scp climweb/.env user@NEW_IP_ADDRESS:CLIMWEB_PATH/.env
```

---

## 🖥️ Back on the New Server

### Check UID and GID

```bash
id
```

---

### Update `.env` File

Edit the `.env` file and update the `UID` and `GID` values to match the new server:

```bash
nano .env
```

Save and exit:

* **Ctrl + O**, press **Enter**
* **Ctrl + X**

---

### Fix Permissions for Backup, Static and Media Files

```bash
sudo chown -R UID:GID climweb/static
sudo chown -R UID:GID climweb/media
sudo chown -R UID:GID climweb/backup
sudo chown -R UID:GID climweb/plugins
```

*(Replace `UID` and `GID` with the values from your `.env` file.)*

---

### Build and Start Containers

```bash
docker compose up -d
```

Wait for all containers to be healthy before proceeding:

```bash
docker compose ps
```

---

## 🔄 Restore Backup Files

Run the restore script from the `climweb-docker` directory:

```bash
make restore
```

Or equivalently:

```bash
bash scripts/restore.sh
```

The script will:

1. Read the `backup-manifest.json` to detect the backup's source version
2. Warn you if the backup version differs from the currently running version
3. Drop any blocking PostGIS extensions automatically
4. Restore the database (`dbrestore`)
5. **Run Django migrations** to reconcile the schema if the versions differ
6. Restore media files (`mediarestore`)

> **Restoring to a different climweb version** is fully supported. The `migrate` step
> is what makes cross-version restores work — it applies any new migrations on top
> of the restored database so the schema matches the running version.

### Restore options

| Flag | Effect |
|------|--------|
| `--db-only` | Skip media restore |
| `--media-only` | Skip DB restore and migrations |
| `--no-migrate` | Skip post-restore migrations (only safe when versions match) |

Example — restore only the database, skip media:

```bash
bash scripts/restore.sh --db-only
```

---

## 🔐 Set Up Nginx Proxy Manager (SSL)

```bash
mv nginx-proxy-manager ..

cd ..

cd nginx-proxy-manager

docker compose up -d
```
