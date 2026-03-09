#!/usr/bin/env bash

set -e

# -------- colors --------

GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # no color

section() {
  echo ""
  echo -e "${BLUE}=====================================${NC}"
  echo -e "${BLUE}$1${NC}"
  echo -e "${BLUE}=====================================${NC}"
}

info() {
  echo -e "${YELLOW}$1${NC}" >&2
}

success() {
  echo -e "${GREEN}$1${NC}" >&2
}

error() {
  echo -e "${RED}$1${NC}" >&2
}

CMS_PORT=80

# -------- helper functions --------

prompt_required() {
  local value
  while true; do
    echo ""
    info "$2"
    read -p "$(echo -e ${BLUE}$1:${NC} )" value

    if [[ -n "$value" ]]; then
      echo "$value"
      return
    else
      error "Value required. Please try again."
    fi
  done
}

prompt_default() {
  local value
  echo ""
  info "$3"
  read -p "$(echo -e ${BLUE}$1 [$2]:${NC} )" value
  echo "${value:-$2}"
}

prompt_password() {

  while true; do
    echo ""
    info "Enter database password (input hidden)"

    read -s -p "$(echo -e ${BLUE}CMS_DB_PASSWORD:${NC} )" pass1
    echo
    read -s -p "$(echo -e ${BLUE}Confirm CMS_DB_PASSWORD:${NC} )" pass2
    echo ""

    if [[ "$pass1" == "$pass2" && -n "$pass1" ]]; then
      success "Password created successfully."
      echo "$pass1"
      return
    else
      error "Passwords do not match. Please try again."
    fi
  done
}

# -------- database section --------

section "Database Configuration"

CMS_DB_NAME=$(prompt_required \
"CMS_DB_NAME" \
"Name of the PostgreSQL database used by the CMS.")

CMS_DB_USER=$(prompt_required \
"CMS_DB_USER" \
"Database username used by the CMS to connect to PostgreSQL.")

CMS_DB_PASSWORD=$(prompt_password)

# -------- system section --------

section "System Configuration"

SECRET_KEY=$(openssl rand -base64 50 | tr -d '\n$')

CLIMWEB_VERSION=$(prompt_required \
"CLIMWEB_VERSION" \
"Version of ClimWeb docker images to install .")

IP_ADDRESS=$(prompt_required \
"Server IP or Domain" \
"Public IP address or domain where ClimWeb will be accessible.")

# -------- optional settings --------

section "Optional Configuration"

TIME_ZONE=$(prompt_default \
"TIME_ZONE" \
"UTC" \
"Server timezone. Example: Africa/Nairobi.")

CMS_DEFAULT_LANGUAGE_CODE=$(prompt_default \
"CMS_DEFAULT_LANGUAGE_CODE" \
"en" \
"Default CMS language (en, fr, ar, am, es, sw).")


# -------- derived variables --------

CMS_BASE_URL="http://$IP_ADDRESS"
CSRF_TRUSTED_ORIGINS="http://$IP_ADDRESS,http://$IP_ADDRESS:$CMS_PORT"
MAPVIEWER_CMS_API="http://$IP_ADDRESS/api"
ALLOWED_HOSTS="$IP_ADDRESS"

# -------- prepare config --------

section "Preparing Configuration"

cp docker-compose.yml.sample docker-compose.yml
cp nginx/nginx.conf.sample nginx/nginx.conf
cp .env.sample .env

set_env() {
  key="$1"
  value="$2"

  # sanitize value
  value=$(printf "%s" "$value" | tr -d '\n')

  if grep -q "^${key}=" .env; then
    sed -i.bak "s|^${key}=.*|${key}=${value}|" .env
  else
    printf "%s=%s\n" "$key" "$value" >> .env
  fi
}

set_env CMS_PORT "$CMS_PORT"
set_env CMS_DB_NAME "$CMS_DB_NAME"
set_env CMS_DB_USER "$CMS_DB_USER"
set_env CMS_DB_PASSWORD "$CMS_DB_PASSWORD"
set_env SECRET_KEY "$SECRET_KEY"
set_env CLIMWEB_VERSION "$CLIMWEB_VERSION"
set_env CMS_BASE_URL "$CMS_BASE_URL"
set_env CSRF_TRUSTED_ORIGINS "$CSRF_TRUSTED_ORIGINS"
set_env MAPVIEWER_CMS_API "$MAPVIEWER_CMS_API"
set_env TIME_ZONE "$TIME_ZONE"
set_env CMS_DEFAULT_LANGUAGE_CODE "$CMS_DEFAULT_LANGUAGE_CODE"
set_env ALLOWED_HOSTS "$ALLOWED_HOSTS"

rm -f .env.bak

success "Environment configuration created."

# -------- start containers --------

section "Starting ClimWeb"

docker compose pull

docker compose up -d

success "ClimWeb installation complete."

echo ""
echo -e "${GREEN}Access the CMS at:${NC}"
echo -e "${BLUE}http://$IP_ADDRESS${NC}" | tr -d '\n$'
echo ""