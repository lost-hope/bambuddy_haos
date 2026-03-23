#!/bin/sh

set -eu

ADDON_DIR="/addons/bambuddy"
ADDON_SLUG="local_bambuddy"
ADDON_VERSION="${BAMBUDDY_ADDON_VERSION:-0.2.0}"
DEFAULT_TIMEZONE="Europe/Berlin"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Required command not found: $1" >&2
    exit 1
  fi
}

detect_timezone() {
  if [ -n "${TZ:-}" ]; then
    printf '%s\n' "$TZ"
    return
  fi

  if [ -f /etc/timezone ]; then
    timezone="$(tr -d '\r' </etc/timezone)"
    if [ -n "$timezone" ]; then
      printf '%s\n' "$timezone"
      return
    fi
  fi

  if [ -L /etc/localtime ]; then
    timezone="$(readlink /etc/localtime 2>/dev/null | sed 's#^.*zoneinfo/##')"
    if [ -n "$timezone" ]; then
      printf '%s\n' "$timezone"
      return
    fi
  fi

  printf '%s\n' "$DEFAULT_TIMEZONE"
}

wait_for_addon() {
  attempt=1
  while [ "$attempt" -le 10 ]; do
    if ha apps info "$ADDON_SLUG" >/dev/null 2>&1; then
      return 0
    fi

    sleep 3
    ha store reload >/dev/null 2>&1 || true
    attempt=$((attempt + 1))
  done

  return 1
}

addon_installed() {
  ha apps info "$ADDON_SLUG" --raw-json 2>/dev/null | grep -q '"installed":[[:space:]]*true'
}

require_command ha
require_command sed
require_command grep

TIMEZONE="$(detect_timezone)"

echo "Creating local add-on files in $ADDON_DIR"
mkdir -p "$ADDON_DIR"

cat >"$ADDON_DIR/config.yaml" <<EOF
name: "Bambuddy"
description: "Self-hosted print archive and management for Bambu Lab printers"
version: "$ADDON_VERSION"
slug: "bambuddy"
init: false
arch:
  - amd64
  - aarch64
startup: application
boot: auto
ports:
  8000/tcp: 8000
ports_description:
  8000/tcp: "Bambuddy Web UI"
map:
  - config:rw
options: {}
schema: {}
EOF

cat >"$ADDON_DIR/Dockerfile" <<EOF
ARG BUILD_FROM
FROM ghcr.io/maziggy/bambuddy:latest

ENV TZ=$TIMEZONE

RUN rm -rf /app/data && ln -s /config /app/data

WORKDIR /app

EXPOSE 8000

CMD ["uvicorn", "backend.app.main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF

echo "Reloading Home Assistant Supervisor and app store"
ha supervisor reload
ha store reload

echo "Waiting for local add-on to become visible"
if ! wait_for_addon; then
  echo "The local add-on was not detected after reload. Check Supervisor logs." >&2
  exit 1
fi

if addon_installed; then
  echo "Add-on already installed. Rebuilding to apply the latest local files"
  ha apps rebuild "$ADDON_SLUG" --force
else
  echo "Installing add-on $ADDON_SLUG"
  ha apps install "$ADDON_SLUG"
fi

echo "Starting add-on $ADDON_SLUG"
ha apps start "$ADDON_SLUG" || ha apps restart "$ADDON_SLUG"

echo
echo "Bambuddy installation finished."
echo "Open one of these URLs in your browser:"
echo "  http://homeassistant.local:8000"
echo "  http://<YOUR_HA_IP>:8000"
echo
echo "Remaining manual steps:"
echo "  1. Complete Bambuddy setup in the Web UI"
echo "  2. Add your printer IP, serial number, and LAN access code"
echo "  3. Optional: create a Home Assistant Webpage dashboard pointing to port 8000"
