#!/bin/bash

python manage.py migrate --noinput

python manage.py collectstatic --clear --no-input
# &

# # Execute Django management command as a cron job
# while true; do
#   python manage.py generate_forecast
#   sleep 10800  # Delay between cron job executions (e.g., 3 hours)
# done


#ensure environment-variables are available for cronjob
printenv | grep -v "no_proxy" >>/etc/environment

# ensure cron is running
service cron start
service cron status

# submit satellite imagery download task
python manage.py submit_sat_imagery_download

export GEOMANAGER_AUTO_INGEST_RASTER_DATA_DIR=${GEOMANAGER_AUTO_INGEST_RASTER_DATA_DIR:-/geomanager/data}
mkdir -p $GEOMANAGER_AUTO_INGEST_RASTER_DATA_DIR

watchmedo shell-command --patterns="*.tif" --ignore-directories --recursive \
  --command='python manage.py ingest_geomanager_raster "${watch_event_type}" "${watch_src_path}" --dst "${watch_dest_path}" --overwrite' \
    $GEOMANAGER_AUTO_INGEST_RASTER_DATA_DIR &
    
# reset cms upgrade status
python manage.py reset_cms_upgrade_status

exec "$@"