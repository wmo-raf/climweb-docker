#!/bin/bash
set -eu

NEW_CLIMWEB_VERSION=$1

if [ -z "$NEW_CLIMWEB_VERSION" ]; then
  echo "No Version passed"
  exit 1
fi

env_file=".env"

CURRENT_CLIMWEB_VERSION=$(grep -E "^CLIMWEB_VERSION=" "$env_file" | awk -F'=' '{print $2}' | tr -d '"')

if [ -z "$CURRENT_CLIMWEB_VERSION" ]; then
  echo "No CLIMWEB Version"
  exit 1
else
  if [ "$NEW_CLIMWEB_VERSION" == "$CURRENT_CLIMWEB_VERSION" ]; then
    echo "Current version: '$CURRENT_CLIMWEB_VERSION' and provided version: '$NEW_CLIMWEB_VERSION' are equal"
  else
    echo "********* Building climweb with new version $NEW_CLIMWEB_VERSION.... *************"

    # disable exit on error
    set +e

    # build containers
    docker compose build --build-arg CLIMWEB_VERSION="$NEW_CLIMWEB_VERSION"

    # Check the exit code
    if [ $? -ne 0 ]; then
      # restart climweb to reset upgrade status
      docker compose restart climweb
    else
      echo "********* Updating env file.... *************"

      # replacing CLIMWEB_VERSION
      env_c=$(sed "s/^CLIMWEB_VERSION=.*/CLIMWEB_VERSION=$NEW_CLIMWEB_VERSION/" $env_file)
      # write new env file
      echo "$env_c" >$env_file

      echo "********* Restarting containers.... *************"
      # restart
      docker compose up -d --force-recreate
    fi
  fi
fi
