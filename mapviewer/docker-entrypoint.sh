#!/bin/bash

# copy .next files to enable connecting mounted volumes to static
mkdir -p /app/nginx/.next
cp -r /app/.next/. /app/nginx/.next/

yarn start

exec "$@"