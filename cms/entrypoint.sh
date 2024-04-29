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

# initialize geomanager
python manage.py initialize_geomanager

# Run Django Background Tasks. A similar CRON job will be initiated in the background after 15 minutes
# Read more at https://django-background-tasks.readthedocs.io/en/latest/#running-tasks
python manage.py process_tasks --duration 15

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

exec "$@"