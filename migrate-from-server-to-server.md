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

```bash
cd climweb
docker compose exec climweb /bin/bash
```

Inside the container:

```bash
climweb dbbackup --clean --noinput
climweb mediabackup --clean --noinput
exit
```

---

### Copy Backup Files to the New Server

```bash
scp climweb/backup/*.tar user@NEW_IP_ADDRESS:CLIMWEB_PATH/climweb/backup
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

### Build and Start Containers

```bash
docker network ls
docker compose up -d
```

---

### Fix Permissions for Backup,Static and Media Files

```bash
sudo chown -R UID:GID climweb/static

sudo chown -R UID:GID climweb/media

sudo chown -R UID:GID climweb/backup

sudo chown -R UID:GID climweb/plugins
```

*(Replace `UID` and `GID` with the values from your `.env` file.)*

---

## 🔄 Restore Backup Files

### Restore Database

```bash
docker compose exec climweb_db /bin/bash
```

```bash
psql -U <CMS_DB_USER> -d <CMS_DB_NAME>
```

> Replace `<CMS_DB_USER>` and `<CMS_DB_NAME>` with values from the `.env` file.

Run:

```sql
DROP EXTENSION IF EXISTS postgis_topology;
DROP EXTENSION IF EXISTS postgis_tiger_geocoder;
```

Exit:

```bash
exit
exit
```

---

### Restore Media and Database

```bash
docker compose exec climweb /bin/bash
```

```bash
climweb mediarestore
climweb dbrestore
```

---

## 🔐 Set Up Nginx Proxy Manager (SSL)

```bash
mv nginx-proxy-manager ..

cd ..

cd nginx-proxy-manager

docker compose up -d
```
