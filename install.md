# Bambuddy on Home Assistant OS

A step-by-step guide to self-hosting Bambuddy as a local add-on.

Works on Home Assistant OS (HAOS), `amd64`, and `arm64`.

## Overview

[Bambuddy](https://github.com/maziggy/bambuddy) is a self-hosted print archive and management system for Bambu Lab 3D printers. It connects to your printer using LAN Mode, so no Bambu Cloud dependency is required.

This guide walks you through installing Bambuddy as a local add-on directly on Home Assistant OS, so it runs 24/7 on your always-on HA machine alongside your other automations.

## What You Will Accomplish

- Create a local HA add-on that wraps the Bambuddy Docker image.
- Install and start Bambuddy through the HA Supervisor.
- Fix persistent storage so your printer config and print history survive add-on rebuilds.
- Add Bambuddy to the HA sidebar as an embedded webpage panel that works on desktop and mobile.

## Prerequisites

- Home Assistant OS running on a machine on your local network.
- SSH & Web Terminal add-on installed in HA.
	- Path: `Settings -> Add-ons -> Add-on Store -> search for Terminal & SSH`
- Advanced mode enabled in your HA user profile.
	- Path: click your name at the bottom left -> enable `Advanced mode`
- A Bambu Lab printer with LAN Mode enabled.
- Your printer's IP address, Serial Number, and LAN Access Code.
	- Found under printer `Settings -> Network` and `Settings -> Device Information`

## Why a Local Add-on Instead of Docker?

Bambuddy is distributed as a Docker image. On a standard Linux machine, you would use `docker-compose` to run it. However, Home Assistant OS locks down direct Docker access from the SSH terminal, so running Docker commands directly returns `command not found`.

The supported way to run extra containers alongside HA OS is through the Supervisor's local add-on system. By creating a simple `Dockerfile` and `config.yaml`, the Supervisor treats Bambuddy like any other add-on: it appears in your add-on list, starts on boot, and can be managed from the HA UI.

## Step 1: Open the SSH Terminal

In your HA sidebar, click `Terminal`, or go to:

`Settings -> Add-ons -> Terminal & SSH -> Open Web UI`

All commands in the following steps are run in this terminal.

## Step 2: Create the Local Add-on Folder

HA Supervisor scans the `/addons` directory for local add-ons. Create a folder for Bambuddy:

```bash
mkdir -p /addons/bambuddy
```

## Step 3: Create the config.yaml

This file tells the Supervisor what the add-on is, what port it uses, and to mount the `/config` directory for persistent storage.

Run the following command to create it:

```bash
cat > /addons/bambuddy/config.yaml << 'EOF'
name: "Bambuddy"
description: "Self-hosted print archive and management for Bambu Lab printers"
version: "0.1.6"
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
```

## Step 4: Create the Dockerfile

This pulls the latest Bambuddy image and sets up persistent storage by symlinking `/app/data` (where Bambuddy stores its database) to `/config` (which HA mounts persistently).

Without the symlink, every time you rebuild the add-on the database is wiped and you lose your printer configuration and print history. The symlink fixes that permanently.

Run the following command to create it:

```bash
cat >/addons/bambuddy/Dockerfile << EOF
ARG BUILD_FROM
FROM ghcr.io/maziggy/bambuddy:latest

# Nutzt die System-Zeitzone deines Hosts
ENV TZ=${TZ:-Europe/Berlin}

# Erstellt den Symlink für persistenten Speicher
RUN rm -rf /app/data && ln -s /config/app/data /app/data

WORKDIR /app
EXPOSE 8000
CMD ["uvicorn", "backend.app.main:app", "--host", "0.0.0.0", "--port", "8000"]
EOF
EOF
```

Note: Replace `America/Los_Angeles` with your own timezone, for example `America/New_York` or `Europe/London`.

## Step 5: Install Bambuddy from the Add-on Store

1. Go to `Settings -> Add-ons -> Add-on Store`.
2. Click the three-dot menu in the top right.
3. Click `Check for updates` or `Reload`.
4. Bambuddy should now appear under local apps. Open it.
5. Click `Install` and wait for the build to complete.
6. Once installed, click `Start`.
7. Open the `Log` tab and confirm it started cleanly.

You should see messages similar to:

- `Application startup complete`
- `Uvicorn running on http://0.0.0.0:8000`

## Step 6: Add Your Printer

Open your browser and navigate to:

```text
http://<YOUR_HA_IP>:8000
```

Replace `<YOUR_HA_IP>` with the IP address of your Home Assistant machine.

1. On the setup screen, leave `Enable Authentication` unchecked because this is a local-only service.
2. Click `Complete Setup`.
3. Click `+ Add Printer`.
4. Enter your printer's IP address, Serial Number, and LAN Access Code.
5. Select your printer model from the dropdown.
6. Click `Add Printer`.

Your printer should appear as connected with real-time status, AMS slot info, temperatures, and camera access.

## Step 7: Add Bambuddy to the HA Sidebar

To access Bambuddy directly from the HA sidebar on both desktop and the mobile app:

1. Go to `Settings -> Dashboards`.
2. Click `+ Add Dashboard`.
3. Select `Webpage`.
4. Set the title to `Bambuddy`.
5. Set the URL to `http://<YOUR_HA_IP>:8000`.
6. Click `Create`.

Bambuddy will now appear in your sidebar. In the HA mobile app, it opens as a full embedded panel inside the app.

## About Persistent Storage

The symlink created in Step 4 is the key to data persistence:

```dockerfile
RUN rm -rf /app/data && ln -s /config /app/data
```

Bambuddy stores its SQLite database and archived print files in `/app/data`. By symlinking that path to `/config`, the HA Supervisor persistent config volume is used instead of the container's internal storage.

This means:

- Rebuilding the add-on does not wipe your printer config or print history.
- Restarting HA does not wipe your data.
- Your data lives at `/config` on the HA host and is included in HA backups.

## Updating Bambuddy

When a new version of Bambuddy is released:

1. Go to `Settings -> Add-ons -> Bambuddy`.
2. Click `Rebuild`.
3. The Supervisor will pull the latest `ghcr.io/maziggy/bambuddy:latest` image and rebuild the add-on.
4. Your printer config and print history will be preserved thanks to the persistent storage symlink.

Note: You may want to update the version number in `config.yaml` to match the new release, though this is cosmetic only.

## Troubleshooting

### Add-on not appearing in the store after creating files

Go to the Add-on Store, open the three-dot menu, and select `Check for updates` or `Reload`. The Supervisor will rescan the `/addons` directory.

### Bambuddy starts but printer shows as offline

- Confirm your printer has LAN Mode enabled.
	- Path: printer `Settings -> Network -> LAN Mode`
- Confirm the IP address you entered is correct and the printer is on the same subnet as your HA machine.
- Double-check the Serial Number and Access Code. These are case sensitive.

### Camera feed not showing

The P1S camera stream is only active during a print. Start a print and then click the camera icon on the printer card to open the live feed.

### Data is still being wiped on rebuild

Confirm the `Dockerfile` contains this line:

```dockerfile
RUN rm -rf /app/data && ln -s /config /app/data
```

Also confirm `config.yaml` contains:

```yaml
map:
	- config:rw
```

Both are required. After correcting either file, hit `Rebuild` on the add-on page.

## References

- Bambuddy: <https://github.com/maziggy/bambuddy>
- Guide covers Bambuddy `v0.2.x` on Home Assistant OS `17.x`
