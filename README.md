# ClimWeb Installation Guide

Content Management System for NMHSs in Africa

### 1. Install Docker Engine & Docker Compose Plugin (skip if docker is already installed)

**Docker Engine & Docker Compose Plugin :** Ensure that Docker Engine is installed and running on the machine where you plan to execute the docker-compose command https://docs.docker.com/engine/install/. Docker Engine is the runtime environment for containers.

>Note **Port 80** - Ensure **port 80** is available. No other services or applications should be running or listening on port 80.



### 2. Manage Docker as a non-root user

To create the docker group and add your user:

```bash
sudo groupadd docker

sudo usermod -aG docker $USER
```

Activate the changes to groups:

```bash
newgrp docker
```

---



### 3. Download climweb source:

```bash
git clone https://github.com/wmo-raf/climweb-docker.git climweb
```

```bash
cd climweb
```



### 4. Setup CLIMWEB

```bash
make setup

make permit
```

Input variables approriately when prompted. See [Environmental Variables](https://github.com/wmo-raf/climweb-docker/blob/main/environmental-variables.md#environmental-variables) 

```bash
make start
```

Once successfully completed, the instance can be found at `http://{IP_ADDRESS/HOST}`



### 5. Create superuser to access the CMS Admin interface:

Create superuser providing username, email and strong password

```bash
make createsuperuser
```

The admin instance can be found at `http://{IP_ADDRESS}/cms-admin`

---



**Next Steps** [Manage Climweb Version Upgrades](https://github.com/wmo-raf/climweb-docker/blob/main/webhook-setup.md#manage-climweb-upgrades)

## Useful Resources

- User Guide - [climweb.readthedocs.io](https://climweb.readthedocs.io/)
- [Environmental Variables](https://github.com/wmo-raf/climweb-docker/blob/main/environmental-variables.md#environmental-variables)
- [Backup Climweb to Google Drive / One Drive everyday](https://github.com/wmo-raf/climweb-backup-sync/tree/main?tab=readme-ov-file#climweb-backup-to-google-drive--one-drive)
- [Backup Climweb to another server everyday](https://github.com/wmo-raf/climweb-backup-sync/blob/main/Backup-to-Remote-Server.md)
- [Migrate Climweb from one server to another](https://github.com/wmo-raf/climweb-docker/blob/main/migrate-from-server-to-server.md#migrating-climweb-from-one-remote-server-to-another)
- [Manage Climweb Upgrades](https://github.com/wmo-raf/climweb-docker/blob/main/webhook-setup.md#manage-climweb-upgrades)



# Other useful commands 

| Purpose           | Command |  Instructions        |                                                                                                                                                                                                      
|-------------------|-----------|-----------------------------------------------------------------------------|
| login to shell          | `make shell` | interact with the container's command line and execute commands as if you were directly logged into the container |
| read docker logs            | `make logs` | real-time output of the containers' logs                                   |
| stop/remove docker containers       | `make down` | stop and remove Docker containers                                          |
| check containers status          | `make status` | display container names, their status (running, stopped), the associated services, and their respective health states  |
| generate city forecasts from external source        | `make generate_forecast` | used for fetching 7-day forecast from external source (https://developer.yr.no/)       |
