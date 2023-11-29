# syntax = docker/dockerfile:1.5

# use osgeo gdal ubuntu small 3.7 image.
# pre-installed with GDAL 3.7.0 and Python 3.10.6
FROM ghcr.io/osgeo/gdal:ubuntu-small-3.7.0

# install dependencies
RUN apt-get update && apt-get install -y \
    cron \
    libgeos-dev \
    imagemagick \
    libmagic1 \
    libcairo2-dev \
    libffi-dev \
    python3-pip --fix-missing \
    lsb-release

# for pg_dump 
RUN echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && cat /etc/apt/sources.list.d/pgdg.list \
    && curl --silent https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
    && apt-get update \
    && apt-get install -y postgresql-client-15

# set python env
ENV PYTHONDONTWRITEBYTECODE 1
ENV PYTHONUNBUFFERED 1

# install docker-compose wait
ADD https://github.com/ufoscout/docker-compose-wait/releases/download/2.12.0/wait /wait
RUN chmod +x /wait

# Download cms
ENV APP_HOME=/home/app
RUN mkdir -p $APP_HOME
ARG CMS_VERSION
ENV CMS_VERSION=$CMS_VERSION

ADD https://github.com/wmo-raf/nmhs-cms/archive/refs/tags/v$CMS_VERSION.tar.gz ./
RUN tar -xzf v$CMS_VERSION.tar.gz -C ./ && mv nmhs-cms-$CMS_VERSION/ $APP_HOME/web/ && rm v$CMS_VERSION.tar.gz

# setup working dir
WORKDIR $APP_HOME/web

# install requirements
RUN --mount=type=cache,target=/root/.cache pip install --upgrade pip && pip install -r requirements.txt

ENV GEOMANAGER_AUTO_INGEST_RASTER_DATA_DIR=/geomanager/data
RUN mkdir -p $GEOMANAGER_AUTO_INGEST_RASTER_DATA_DIR

COPY entrypoint.sh ./
RUN chmod +x entrypoint.sh

# add satellite.cron to crontab
COPY satellite.cron /etc/cron.d/satellite.cron

RUN chmod 0644 /etc/cron.d/satellite.cron && crontab /etc/cron.d/satellite.cron

# add backup.cron to crontab
COPY backup.cron /etc/cron.d/backup.cron

RUN chmod 0644 /etc/cron.d/backup.cron && crontab /etc/cron.d/backup.cron

# add city_forecast.cron to crontab
COPY city_forecast.cron /etc/cron.d/city_forecast.cron

RUN chmod 0644 /etc/cron.d/city_forecast.cron && crontab /etc/cron.d/city_forecast.cron

# create tmp dir for handling large django uploads
RUN mkdir -p tmp

# Port used by this container to serve HTTP.
EXPOSE 8000