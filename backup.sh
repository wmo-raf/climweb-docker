#!/bin/bash

# Set up environment variables
DUMP_DIRECTORY="/path/to/dump/directory"
MEDIA_DIRECTORY="/path/to/media" # Path to your media folder
BACKUP_DIRECTORY="/path/to/backup/directory"

MANAGEMENT_COMMAND="dumpdata"

# Run Django management command with timestamp
TIMESTAMP=$(date +"%Y%m%d%H%M%S")
DUMP_FILENAME="dump_${TIMESTAMP}.json"
python manage.py "$MANAGEMENT_COMMAND" --output="$DUMP_DIRECTORY/$DUMP_FILENAME"

# Clean up old dumps (keep only last 7 days)
find "$DUMP_DIRECTORY" -name "dump_*" -mtime +7 -exec rm {} \;

# Compress media folder with timestamp
MEDIA_BACKUP_FILENAME="media_backup_${TIMESTAMP}.tar.gz"
tar -czf "$BACKUP_DIRECTORY/$MEDIA_BACKUP_FILENAME" "$MEDIA_DIRECTORY"

# Clean up old media backups (keep only last 7 days)
find "$BACKUP_DIRECTORY" -name "media_backup_*" -mtime +7 -exec rm {} \