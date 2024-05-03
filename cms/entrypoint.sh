#!/bin/bash

python manage.py migrate --noinput

python manage.py collectstatic --clear --no-input

# ensure environment-variables are available for cronjob
printenv | grep -v "no_proxy" >>/etc/environment

# ensure cron is running
service cron start
service cron status

# submit satellite imagery download task
python manage.py submit_sat_imagery_download

# initialize geomanager
python manage.py initialize_geomanager

export GEOMANAGER_AUTO_INGEST_RASTER_DATA_DIR=${GEOMANAGER_AUTO_INGEST_RASTER_DATA_DIR:-/geomanager/data}
mkdir -p $GEOMANAGER_AUTO_INGEST_RASTER_DATA_DIR

# start command to watch for new files in the geomanager auto-ingest data dir
while file=$(inotifywait -e create --format "%w%f" -r "$GEOMANAGER_AUTO_INGEST_RASTER_DATA_DIR"); do
  EXT=${file##*.}
  if [ "$EXT" = "tif" ] || [ "$EXT" = "nc" ]; then
    echo "New Geomanager ingestion file detected: $file"
    python manage.py ingest_geomanager_raster created "$file" --overwrite --clip
  fi
done &

# reset cms upgrade status
python manage.py reset_cms_upgrade_status

# start background tasks, with 15 minutes duration.
# Cron Job will triggered after 15 minutes
# https://django-background-tasks.readthedocs.io/en/latest/#running-tasks
python manage.py process_tasks --duration 900 &

# run gunicorn
gunicorn nmhs_cms.wsgi:application --bind 0.0.0.0:8000 --workers=${GUNICORN_NUM_OF_WORKERS:-2} --timeout=${GUNICORN_TIMEOUT:-300}