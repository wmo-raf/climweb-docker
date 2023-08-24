# nmhs-cms-init

Content Management System for NMHSs in Africa

---

## User Guide

Read more from the user guide - [nmhs-cms.readthedocs.io](https://nmhs-cms.readthedocs.io/)

---

## Prerequisites

Before installing the CMS, consider installing on your server:

**Docker Engine & Docker Compose Plugin :** Ensure that Docker Engine is installed and running on the machine where you plan to execute the docker-compose command https://docs.docker.com/engine/install/. Docker Engine is the runtime environment for containers.

---
## CMS Installation Instructions

1. Download from source:

    ```sh
   git clone https://github.com/wmo-raf/nmhs-cms-init.git
    ```

    ```sh
   cd nmhs-cms-init
    ```

3. Setup environmental variables

    Prepare a '.env' file with necessary variables from '.env.sample'

    ```sh
   cp .env.sample .env
    ```

   ```sh
   nano .env
   ```

    Edit and replace variables approriately. See [environmental variables section](#environmental-variables) below

2. Build and launch a running instance of the CMS.

    ```sh
    docker compose build
    ```
   
    ```sh
    docker compose up -d
    ```

    The instance can be found at `http://localhost:{CMS_PORT}`

4. Additionally, create superuser to access the CMS Admin interface:

    Log in to container interactive command line interface
    
    ```sh
   docker exec -it cms_web /bin/bash
    ```

    Create superuser providing username, email and strong password

    ```sh
   python manage.py createsuperuser
    ```
   
    The admin instance can be found at `http://localhost:{CMS_PORT}/{CMS_ADMIN_URL_PATH}`

---

# Environmental Variables
Environmental variables for docker compose. All Should be placed in a single `.env` file, saved in the same folder
as `docker-compose.yml` file


## CMS Web Variables


| Variable    | Description       | Required | Default | More Details |
|:------------|-------------------|:---------|:--------|:-------------|
| CMS_DB_USER | CMS Database user | YES      |         |              |
| CMS_DB_NAME | CMS Database name | YES      |         |              |
| CMS_DB_PASSWORD          | CMS Database password                                                                                                                                                                                                                                | YES      |         |
| CMS_DB_VOLUME            | Mounted docker volume path for persisting database data                                                                                                                                                                                              | YES      |         |                                                                                                       |
| CMS_SITE_NAME            | The human-readable name of your Wagtail installation which welcomes users upon login to the Wagtail admin.                                                                                                                                           | YES      |         |                                                                                                       |
| CMS_ADMIN_URL_PATH       | Base Path to admin pages. Do not use `admin` or an easy to guess path                                                                                                                                                                                | YES      |         |                                                                                                       |
| CMS_DEBUG                | A boolean that turns on/off debug mode. Never deploy a site into production with DEBUG turned on                                                                                                                                                     | NO       | False   |                                                                                                       |
| CMS_PORT                 | Port to run cms                                                                                                                                                                                                                                      | YES      | 80      |                                                                                                       |
| CSRF_TRUSTED_ORIGINS     | This variable can be set when CMS_PORT is not 80 e.g if CMS_PORT=8000, CSRF_TRUSTED_ORIGINS would be the following: http://{YOUR_IP_ADDRESS}:8000, http://{YOUR_IP_ADDRESS}, http://localhost:8000 and http://127.0.0.1:8000                                                   | NO       |         |                                                                                                       |
| TIME_ZONE                | A string representing the time zone for this installation. See the [list of time zones](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones). Set this to your country timezone                                                             | NO       | UTC     | [List of tz database time zones](https://en.wikipedia.org/wiki/List_of_tz_database_time_zones)        |
| SECRET_KEY               | A secret key for a particular Django installation. This is used to provide cryptographic signing, and should be set to a unique, unpredictable value. Django will refuse to start if SECRET_KEY is not set                                           | YES      |         |                                                                                                       |
| ALLOWED_HOSTS            | A list of strings representing the host/domain names that this Django site can serve. This is a security measure to prevent HTTP Host header attacks, which are possible even under many seemingly-safe web server configurations.                   | YES      |         | [Django Allowed Hosts](https://docs.djangoproject.com/en/4.2/ref/settings/#std-setting-ALLOWED_HOSTS) |                                                                                                                                                                                                                          |          |         |                                                                                                       |
| SMTP_EMAIL_HOST          | The host to use for sending email                                                                                                                                                                                                                    | NO       |         |                                                                                                       |
| SMTP_EMAIL_PORT          | Port to use for the SMTP server defined in `SMTP_EMAIL_HOST`                                                                                                                                                                                         | NO       | 25      |                                                                                                       |
| SMTP_EMAIL_USE_TLS       | Whether to use a TLS (secure) connection when talking to the SMTP server. This is used for explicit TLS connections, generally on port 587                                                                                                           | NO       | True    |                                                                                                       |
| SMTP_EMAIL_HOST_USER     | Username to use for the SMTP server defined in `SMTP_EMAIL_HOST`. If empty, Django won’t attempt authentication.                                                                                                                                     | NO       |         |                                                                                                       |
| SMTP_EMAIL_HOST_PASSWORD | Password to use for the SMTP server defined in `SMTP_EMAIL_HOST`. This setting is used in conjunction with `SMTP_EMAIL_HOST_USER` when authenticating to the SMTP server. If either of these settings is empty, Django won’t attempt authentication. | NO       |         |                                                                                                       |
| CMS_ADMINS               | A list of all the people who get code error notifications, in format `"Name <name@example.com>, Another Name <another@example.com>"`                                                                                                                 | NO       |         |                                                                                                       |
| DEFAULT_FROM_EMAIL       | Default email address to use for various automated correspondence from the site manager(s)                                                                                                                                                           | NO       |         |                                                                                                       |
| RECAPTCHA_PUBLIC_KEY     | Google Recaptcha Public Key                                                                                                                                                                                                                          | NO       |         |                                                                                                       |
| RECAPTCHA_PRIVATE_KEY    | Google Recaptcha Private Key                                                                                                                                                                                                                         | NO       |         |                                                                                                       |
| CMS_NUM_OF_WORKERS       | Gunicorn number of workers. Recommended value should be `(2 x $num_cores) + 1 `. For example, if your server has `4 CPU Cores`, this value should be set to `9`, which is the result of `(2 x 4) + 1 = 9`                                            | YES      |         | [Gunicorn Workers details](https://docs.gunicorn.org/en/latest/design.html#how-many-workers)          |
| CMS_STATIC_VOLUME        | Mounted docker volume path for persisting CMS static files                                                                                                                                                                                           | YES      |         |                                                                                                       |
| CMS_MEDIA_VOLUME         | Mounted docker volume path for persisting CMS media files     | YES      |         |                                                                                                       |
| CMS_UPGRADE_HOOK_URL     | [Webhook](https://github.com/adnanh/webhook) url to your server that triggers a cms upgrade script      | NO      |         |                                                                                                       |

## MapViewer Variables

| Variable                     | Description                                                                                                                                                                          |
|------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| MAPVIEWER_CMS_API            | CMS API Endpoint for MapViewer. This should be the public path to your CMS root url , followed by `/api`. For example `https://met.example.com/api`                                  |
| MAPVIEWER_NEXT_STATIC_VOLUME | Mounted docker volume path for MapViewer static files                                                                                                                                |
| BITLY_TOKEN                  | [Bitly](https://bitly.com/) access token. The MapViewer uses Bitly for url shortening. See [here](https://dev.bitly.com/docs/getting-started/authentication/) on how to generate one |
| ANALYTICS_PROPERTY_ID        |                                                                                                                                                                                      |
| GOOGLE_CUSTOM_SEARCH_CX      |                                                                                                                                                                                      |
| GOOGLE_SEARCH_API_KEY        |      |                                                 






## Set up Webhook

[Webhook](https://github.com/adnanh/webhook) helps to automate some tasks that otherwise need to be done manually. For example upgrading the CMS to a newer version.

The [Webhook](https://github.com/adnanh/webhook) package needs to be installed on your server (`NOT` in a docker container)

Install the [Webhook](https://github.com/adnanh/webhook) package for your OS as described [here](https://github.com/adnanh/webhook/tree/master#using-package-manager)

If on Ubuntu or Debian, you can run:

```
sudo apt-get install webhook
```

From the root project directory (where you cloned this project) run:

```
sh webhook-config.sh
```

This will create a new file `webhook/hooks.yaml` with the correct paths in place, using the `webhook/hooks.yaml.sample` file

We will use this file to run [Webhook](https://github.com/adnanh/webhook)


### Running Webhook server with Supervisor

Install supervisor to keep the webhook server running in the background.

```
sudo apt install supervisor
```

Create a `webhook.conf` file in `/etc/supervisor/conf.d/`

```
cd /etc/supervisor/conf.d
sudo nano webhook.conf
```

Add the following inside the `webhook.conf` file

```
[program:webhook]
command=webhook -hooks /path_to_project_dir/webhook/hooks.yaml -verbose
autostart=true
autorestart=true
startretries=3
```

Save the file.

After creating the configuration, tell `supervisord`` to refresh its configuration and start the service:

```
sudo superviserctl reread
sudo superviserctl update
sudo supervisorctl status
```

If everything is ok, `Webhook` is now set and ready to be used.


You can now set the  `CMS_UPGRADE_HOOK_URL` env variable to:

`http://host.docker.internal/9000/cms-upgrade`

Note this a special docker network url accessed only from inside the `cms_web` docker container.


## Other useful commands 

| Purpose           | Command |  Instructions        |                                                                                                                                                                                                      
|-------------------|-----------|-----------------------------------------------------------------------------|
| docker configurations          | `docker compose config` | validate and view the Compose file configuration               |
| login to shell          | `docker exec -it {container} /bin/bash` | interact with the container's command line and execute commands as if you were directly logged into the container |
| login to shell as root user      | `docker exec -u -0 -it {container} /bin/bash` | access a running Docker container and open a Bash shell inside it with the root user                                                                                                                                
| read docker logs            | `docker compose logs --follow {containers}` | real-time output of the containers' logs                                   |
| stop/remove docker containers       | `docker compose down --remove-orphans {containers}` | stop and remove Docker containers                                          |
| check containers status          | `docker compose  ps {containers}` | display container names, their status (running, stopped), the associated services, and their respective health states  |
| generate city forecasts from external source        | use the `login` command above and execute `python manage.py generate_forecast` | used for fetching 7-day forecast from external source (https://developer.yr.no/)       |
| setup mautic instance    | `docker compose --file docker-compose.mautic.yml --file docker-compose.yml build {containers}` followed by `docker compose --file docker-compose.mautic.yml --file docker-compose.yml {DOCKER_COMPOSE_ARGS} up -d` | setup mautic environmental variables i.e `MAUTIC_DB_USER`,`MAUTIC_DB_PASSWORD` and  `MYSQL_ROOT_PASSWORD`  then execute command |

