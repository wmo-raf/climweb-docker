#!/bin/bash
set -e

# get current working directory
WORKING_DIR=$(pwd)

# hooks sample file
hooks_sample_file="$WORKING_DIR/webhook/hooks.yaml.sample"

# .env file
env_file="$WORKING_DIR/.env"

# Check if hooks sample file exists
if [ ! -e "$hooks_sample_file" ]; then
    echo "Sample hooks file does not exist: $hooks_sample_file"
    exit 1
fi

# Check if .env file exists
if [ ! -e "$env_file" ]; then
    echo ".env file not found at $env_file. Please set up your .env file first."
    exit 1
fi

# Use Django's SECRET_KEY as the webhook secret — already set in every installation.
UPGRADE_WEBHOOK_SECRET=$(grep -E "^SECRET_KEY=" "$env_file" | cut -d'=' -f2- | tr -d '"')

if [ -z "$UPGRADE_WEBHOOK_SECRET" ]; then
    echo "SECRET_KEY is not set in $env_file. Please set it up before running this script."
    exit 1
fi

# new hooks file
hooks_file="$WORKING_DIR/webhook/hooks.yaml"

# substitute WORKING_DIR and webhook secret placeholders
hooks_yaml_c=$(sed "s?WORKING_DIR?$WORKING_DIR?g" "$hooks_sample_file")
hooks_yaml_c=$(echo "$hooks_yaml_c" | sed "s?UPGRADE_WEBHOOK_SECRET_PLACEHOLDER?$UPGRADE_WEBHOOK_SECRET?g")

# write out hooks_file
echo "$hooks_yaml_c" > "$hooks_file"

echo "Webhook config written to $hooks_file"
