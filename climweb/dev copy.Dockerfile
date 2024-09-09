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

# Copy cron files, set permissions, and install cron jobs in one step
COPY *.cron /etc/cron.d/
RUN chmod 0644 /etc/cron.d/*.cron && \
    cat /etc/cron.d/*.cron | crontab && \
    crontab -u $DOCKER_USER /etc/cron.d/*.cron && \
    chmod u+s /usr/sbin/cron

USER $UID:$GID

ENV CLIMWEB_DOWNLOAD_DIR=/tmp/climweb_src
ARG CLIMWEB_BRANCH
ENV CLIMWEB_BRANCH=$CLIMWEB_BRANCH

# Download climweb source code and extract it to /climweb/web.
# Also move the plugins scripts to /climweb/plugins.
RUN curl -L https://github.com/wmo-raf/nmhs-cms/archive/refs/heads/$CLIMWEB_BRANCH.tar.gz \
    | tar -xz -C /tmp && \
    mv /tmp/nmhs-cms-$CLIMWEB_BRANCH/climweb/* /climweb/web/ && \
    mv /tmp/nmhs-cms-$CLIMWEB_BRANCH/deploy/plugins/*.sh /climweb/plugins/ && \
    rm -rf /tmp/nmhs-cms-$CLIMWEB_BRANCH

RUN python3 -m venv /climweb/venv

ENV PIP_CACHE_DIR=/tmp/climweb_pip_cache
# hadolint ignore=SC1091,DL3042
RUN --mount=type=cache,mode=777,target=$PIP_CACHE_DIR,uid=$UID,gid=$GID . /climweb/venv/bin/activate && pip3 install  -r /climweb/web/requirements.txt


WORKDIR /climweb/web

# Ensure that Python outputs everything that's printed inside
# the application rather than buffering it.
ENV PYTHONUNBUFFERED 1

# ENV GEOMANAGER_AUTO_INGEST_RASTER_DATA_DIR=/geomanager/data
# RUN mkdir -p $GEOMANAGER_AUTO_INGEST_RASTER_DATA_DIR

COPY --chown=$UID:$GID docker-entrypoint.sh /climweb/web/docker-entrypoint.sh

# install climweb as a package
RUN chmod a+x /climweb/web/docker-entrypoint.sh && \
    /climweb/venv/bin/pip install --no-cache-dir -e /climweb/web/

ENV DJANGO_SETTINGS_MODULE='climweb.config.settings.dev'

# create tmp dir for handling large django uploads
RUN mkdir -p tmp

ENTRYPOINT ["/climweb/web/docker-entrypoint.sh"]

CMD ["gunicorn"]
