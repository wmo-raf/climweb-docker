#!/bin/bash
set -eu

NEW_CMS_VERSION=$1

if [ -z "$NEW_CMS_VERSION" ]; then
  echo "No Version passed"
  exit 1
fi

env_file=".env"

CURRENT_CMS_VERSION=$(grep -E "^CMS_VERSION=" "$env_file" | awk -F'=' '{print $2}' | tr -d '"')

if [ -z "$CURRENT_CMS_VERSION" ]; then
  echo "No CMS Version"
  exit 1
else
  if [ "$NEW_CMS_VERSION" == "$CURRENT_CMS_VERSION" ]; then
    echo "Current version: '$CURRENT_CMS_VERSION' and provided version: '$NEW_CMS_VERSION' are equal"
  else
    echo "********* Building cms_web with new version $NEW_CMS_VERSION.... *************"

    # build web
    docker compose build cms_web --build-arg CMS_VERSION="$NEW_CMS_VERSION"

    echo "********* Updating env file.... *************"

    # replacing CMS_VERSION
    env_c=$(sed "s/^CMS_VERSION=.*/CMS_VERSION=$NEW_CMS_VERSION/" $env_file)
    # write new env file
    echo "$env_c" >$env_file

    echo "********* Restarting containers.... *************"

    # restart
    docker compose up -d --force-recreate
  fi
fi
