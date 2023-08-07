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

exec "$@"