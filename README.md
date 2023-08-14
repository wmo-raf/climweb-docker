# nmhs-cms-init

Content Management System for NMHSs in Africa

---

## User Guide

Read more from the user guide - [nmhs-cms.readthedocs.io](https://nmhs-cms.readthedocs.io/)

---

## Prerequisites

Before installing the CMS, there are a few prerequisites to consider installing on your server:

1. **Docker Engine :** Ensure that Docker Engine is installed and running on the machine where you plan to execute the docker-compose command https://docs.docker.com/engine/install/. Docker Engine is the runtime environment for containers.

2. **Docker Compose (step 1-3):** Install Docker Compose https://docs.docker.com/compose/install/linux on the machine where you intend to run the command. Docker Compose is a tool that allows you to define and manage multi-container Docker applications using a YAML configuration file.

3. **Python 3:** Ensure that Python 3 is installed on your machine. Visit (https://realpython.com/installing-python/) and follow the installation instructions for your operating system.

---
## Quickstart Installation with Test Data

The `quickstart` arguement in `nmhs-ctl.py` deploys nmhs-cms with test data with a single command and requires python3 setup. When using nmhs-cms from source, the default port for web components is 3031.

1. Download from source:

    `git clone https://github.com/wmo-raf/nmhs-cms-init.git`

    `cd nmhs-cms-init`

2. Setup environmental variables

    Prepare a '.env' file with necessary variables from '.env.sample'

    `cp .env.sample .env`

   `nano .env`

    Edit and replace variables approriately. See [environmental variables section](#environmental-variables) below

2. Build and launch a running instance of the CMS.

    `docker compose build`
   
    `docker compose up -d`

   or
   
   `python3 nmhs-ctl.py quickstart`

    These commands executes the following steps:

    ```py
    [1/2] BUILDING CONTAINERS
    [2/2] STARTING UP CONTAINERS 
    ```

    The instance can be found at `http://localhost:{CMS_PORT}`

4. Additionally, create superuser to access the CMS Admin interface:

    `python3 nmhs-ctl.py createsuperuser`

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
| CSRF_TRUSTED_ORIGINS     | This variable can be set when CMS_PORT is not 80 e.g if CMS_PORT=8000, *CSRF_TRUSTED_ORIGINS='http://{YOUR_IP_ADDRESS}:8000,http://{YOUR_IP_ADDRESS},http://localhost:8000,http://127.0.0.1:8000'*                                                     | NO       |         |                                                                                                       |
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

## MapViewer Variables

| Variable                     | Description                                                                                                                                                                          |
|------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| MAPVIEWER_CMS_API            | CMS API Endpoint for MapViewer. This should be the public path to your CMS root url , followed by `/api`. For example `https://met.example.com/api`                                  |
| MAPVIEWER_NEXT_STATIC_VOLUME | Mounted docker volume path for MapViewer static files                                                                                                                                |
| BITLY_TOKEN                  | [Bitly](https://bitly.com/) access token. The MapViewer uses Bitly for url shortening. See [here](https://dev.bitly.com/docs/getting-started/authentication/) on how to generate one |
| ANALYTICS_PROPERTY_ID        |                                                                                                                                                                                      |
| GOOGLE_CUSTOM_SEARCH_CX      |                                                                                                                                                                                      |
| GOOGLE_SEARCH_API_KEY        |      |                                                 

## Other useful commands with python3 nmhs-ctl.py {command}

| Command           | Purpose        |                                                                                                                                                                                                      
|-------------------|----------------------------------------------------------------------------------------|
 | `config`          | validate and view the Compose file configuration               |
 | `login`           | interact with the container's command line and execute commands as if you were directly logged into the container |
 | `login-root`      | access a running Docker container and open a Bash shell inside it with the root user                                                                                                                                
 | `logs`            | real-time output of the containers' logs                                   |
 | `stop/down`       | stop and remove Docker containers                                          |
 | `prune`           | clean up unused Docker resources such as containers, images, networks, and volumes. ***Exercise caution when using these commands and ensure that you do not accidentally remove resources that are still needed.*** |
 | `status`          | display container names, their status (running, stopped), the associated services, and their respective health states  |
 | `forecast`        | fetch 7-day forecast from external source (https://developer.yr.no/)       |
 | `setup_mautic`    | setup mautic environmental variables i.e `MAUTIC_DB_USER`,`MAUTIC_DB_PASSWORD` and  `MYSQL_ROOT_PASSWORD`,   |
<!-- | `setup_recaptcha` | setup recaptcha environmental variables i.e `RECAPTCHA_PRIVATE_KEY` and `RECAPTCHA_PUBLIC_KEY`|
 | `setup_cms`       | setting up CMS Configs                                                     |
 | `setup_db`        | Setting up PostgreSQL Configs                                                 | -->

