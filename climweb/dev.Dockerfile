# syntax = docker/dockerfile:1.5

# use osgeo gdal ubuntu small 3.7 image.
# pre-installed with GDAL 3.7.0 and Python 3.10.6
FROM ghcr.io/osgeo/gdal:ubuntu-small-3.7.0

ARG UID
ENV UID=${UID:-9999}
ARG GID
ENV GID=${GID:-9999}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# We might be running as a user which already exists in this image. In that situation
# Everything is OK and we should just continue on.
RUN groupadd -g $GID climweb_docker_group || exit 0
RUN useradd --shell /bin/bash -u $UID -g $GID -o -c "" -m climweb_docker_user -l || exit 0
ENV DOCKER_USER=climweb_docker_user

ENV POSTGRES_VERSION=15

# Install dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    build-essential \
    lsb-release \
    ca-certificates \
    gnupg2 \
    curl \
    cron \
    tini \
    libpq-dev \
    libgeos-dev \
    imagemagick \
    libmagic1 \
    libcairo2-dev \
    libpangocairo-1.0-0 \
    libffi-dev \
    python3-pip \
    python3-dev \
    python3-venv \
    inotify-tools \
    poppler-utils \
    git \
    gosu \
    && echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && curl --silent https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
    && apt-get update \
    && apt-get install --no-install-recommends -y \
    postgresql-client-$POSTGRES_VERSION \
    && apt-get autoclean \
    && apt-get clean \
    && apt-get autoremove \
    && rm -rf /var/lib/apt/lists/*

ENV DOCKER_COMPOSE_WAIT_VERSION=2.12.1

# Install docker-compose wait
ADD https://github.com/ufoscout/docker-compose-wait/releases/download/$DOCKER_COMPOSE_WAIT_VERSION/wait /wait
RUN chmod +x /wait

# Create directories and set correct permissions
RUN mkdir -p /climweb/web /climweb/plugins && chown -R $UID:$GID /climweb

# Set the climweb branch to use
ARG CLIMWEB_BRANCH
ENV CLIMWEB_BRANCH=$CLIMWEB_BRANCH

# Download climweb source code and extract it to /climweb/web.
# Also move the plugins scripts to /climweb/plugins.
RUN curl -L https://github.com/wmo-raf/nmhs-cms/archive/refs/heads/$CLIMWEB_BRANCH.tar.gz \
    | tar -xz -C /tmp && \
    mv /tmp/nmhs-cms-$CLIMWEB_BRANCH/climweb/* /climweb/web/ && \
    mv /tmp/nmhs-cms-$CLIMWEB_BRANCH/deploy/plugins/*.sh /climweb/plugins/ && \
    rm -rf /tmp/nmhs-cms-$CLIMWEB_BRANCH

# Copy cron files, set permissions, and install cron jobs in one step
RUN cp -r /climweb/web/docker/*.cron /etc/cron.d/
RUN chmod 0644 /etc/cron.d/*.cron && \
    cat /etc/cron.d/*.cron | crontab && \
    crontab -u $DOCKER_USER /etc/cron.d/*.cron && \
    chmod u+s /usr/sbin/cron

# set permission for climweb directory
RUN chown -R $UID:$GID /climweb

# Set the user and group
USER $UID:$GID

# Create a virtual environment
RUN python3 -m venv /climweb/venv

# set the pip cache directory
ENV PIP_CACHE_DIR=/tmp/climweb_pip_cache

# Install the requirements
RUN --mount=type=cache,mode=777,target=$PIP_CACHE_DIR,uid=$UID,gid=$GID . /climweb/venv/bin/activate && \
     pip3 install  -r /climweb/web/requirements/base.txt

# Create a tmp directory for the django to use
RUN mkdir -p /climweb/tmp && chown -R $UID:$GID /climweb/tmp

# Set the working directory
WORKDIR /climweb/web

# Ensure that Python outputs everything that's printed inside
# the application rather than buffering it.
ENV PYTHONUNBUFFERED 1

# Create a directory for raster data to be auto-ingested
ENV GEOMANAGER_AUTO_INGEST_RASTER_DATA_DIR=/climweb/geomanager/data
RUN mkdir -p $GEOMANAGER_AUTO_INGEST_RASTER_DATA_DIR && chown -R $UID:$GID $GEOMANAGER_AUTO_INGEST_RASTER_DATA_DIR

# install climweb as a package
RUN chmod a+x /climweb/web/docker/docker-entrypoint.sh && \
    /climweb/venv/bin/pip install --no-cache-dir -e /climweb/web/

ENTRYPOINT ["/usr/bin/tini", "--", "/bin/bash", "/climweb/web/docker/docker-entrypoint.sh"]

ENV DJANGO_SETTINGS_MODULE='climweb.config.settings.production'

CMD ["gunicorn"]
