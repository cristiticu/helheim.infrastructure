#!/bin/bash

# Vintage Story Server User Data Script for Ubuntu 24.04 LTS (AMD64)
# Version: 17 February 2026 1.21.6
# This script runs on instance launch to configure and start the vintage story server.

VINTAGE_USER="vintagestory"
VINTAGE_HOME="/home/${VINTAGE_USER}"
VINTAGE_INSTALL_DIR="${VINTAGE_HOME}/vintagestory-server"
VINTAGE_SERVER_DATA_DIR="${VINTAGE_HOME}/data"

# Placeholder variables to be replaced by startup lambda
USE_MODS="#USE_MODS"
WORLD_S3_BUCKET_PATH="#WORLD_S3"
MODPACK_S3_BUCKET_PATH="#MODPACK_S3"
CONFIG_FILES_S3_BUCKET_PATH="#LISTS_S3"
SERVER_NAME="#SERVER_NAME" 
SERVER_PASSWORD="#PASSWORD"
WORLD_NAME="#WORLD"
INSTANCE_ID="#INSTANCE" 
AWS_REGION="#REGION"

WORLD_LOCAL_PATH="${VINTAGE_SERVER_DATA_DIR}/Saves"

PERIODIC_SYNC_SCRIPT="/usr/local/bin/vintage_periodic_sync.sh"

# This makes them persist so server.sh can see them later
echo "VINTAGE_USER=\"$VINTAGE_USER\"" | sudo tee -a /etc/environment
echo "SERVER_NAME=\"$SERVER_NAME\"" | sudo tee -a /etc/environment
echo "SERVER_PASSWORD=\"$SERVER_PASSWORD\"" | sudo tee -a /etc/environment
echo "WORLD_S3_BUCKET_PATH=\"$WORLD_S3_BUCKET_PATH\"" | sudo tee -a /etc/environment
echo "VINTAGE_SERVER_DATA_DIR=\"$VINTAGE_SERVER_DATA_DIR\"" | sudo tee -a /etc/environment

export $(cat /etc/environment | xargs)

# -------------------------------------------------------------
# 1. Create the Vintage Story Server Startup Script with Placeholders
# -------------------------------------------------------------
echo "Creating Vintage Story server startup script..."

cat <<'EOF' > "${VINTAGE_INSTALL_DIR}/server.sh"
#!/bin/bash
# /etc/init.d/vintagestory.sh
# version 0.4.2 2016-02-09 (YYYY-MM-DD)
#
### BEGIN INIT INFO
# Provides:   vintagestory
# Required-Start: $local_fs $remote_fs screen-cleanup
# Required-Stop:  $local_fs $remote_fs
# Should-Start:   $network
# Should-Stop:    $network
# Default-Start:  2 3 4 5
# Default-Stop:   0 1 6
# Short-Description:    vintagestory server
# Description:    Starts the vintagestory server
### END INIT INFO

. /etc/environment

# Settings - These will be updated by the userdata sed commands
USERNAME='vintagestory'
VSPATH='/home/vintagestory/vintagestory-server'
DATAPATH='/home/vintagestory/data'

HISTORY=1024
SCREENNAME='vintagestory_server'
SERVICE="VintagestoryServer.dll"
OPTIONS="--withconfig='{\"WelcomeMessage\":\"Gym te primeste in bratele lui, {0}. Fie ca prolapsa lui sa iti aduca belsug in aventurile tale.\",\"ServerDescription\":\"Monumentul lui Gym\",\"WhitelistMode\":\"off\",\"ServerName\":\"${SERVER_NAME}\",\"Password\":\"${SERVER_PASSWORD}\"}'"

INVOCATION="dotnet ${SERVICE} --dataPath \"${DATAPATH}\" ${OPTIONS}"
PGREPTEST="dotnet ${SERVICE} --dataPath ${DATAPATH}"

# Commands check
command -v pgrep >/dev/null 2>&1 || { echo "Fatal! I require pgrep but it's not installed." >&2; exit 1; }
command -v screen >/dev/null 2>&1 || { echo "Fatal! I require screen but it's not installed." >&2; exit 1; }

# Determine user context
unset GROUPNAME
ME=$(whoami)
if [ "${ME}" != "${USERNAME}" ] ; then
  groups "${ME}" | grep -q "${USERNAME}" && { GROUPNAME="${USERNAME}"; USERNAME="${ME}"; }
fi

as_user() {
  if [ "${ME}" = "${USERNAME}" ] ; then
    bash -c "${1}"
    return $?
  else
    su "${USERNAME}" -s /bin/bash -c "${1}"
    return $?
  fi
}

vs_version() {
  instdir="${1}"
  if ! [ -f "${instdir}/${SERVICE}" ] ; then
    echo "Fatal! ${instdir}/${SERVICE} not found." >&2
    exit 1
  fi
  if [ ! -d "${DATAPATH}" ] ; then
    mkdir -m 775 -p "${DATAPATH}" >/dev/null 2>&1
  fi
}

vs_start() {
  vs_version "${VSPATH}"
  if pgrep -u "${USERNAME}","${GROUPNAME:-root}" -f "${PGREPTEST}" > /dev/null ; then
    echo "${SERVICE} is already running!"
  else
    cd "${VSPATH}"
    echo "Starting ${SERVICE} ..."
    if as_user "cd \"${VSPATH}\" && screen -h ${HISTORY} -dmS ${SCREENNAME} ${INVOCATION}" ; then
      sleep 7
    else
      echo "Warning! Problems with ${SERVICE}!"
    fi
  fi
}

vs_status() {
  if ! pgrep -u "${USERNAME}","${GROUPNAME:-root}" -f "${PGREPTEST}" > /dev/null ; then
    echo "${SERVICE} is not running."
    return 1
  else
    echo "${SERVICE} is up and running!"
    return 0
  fi
}

vs_stop() {
  if pgrep -u "${USERNAME}","${GROUPNAME:-root}" -f "${PGREPTEST}" > /dev/null ; then
    echo "Stopping ${SERVICE} ..."
    as_user "screen -p 0 -S ${SCREENNAME} -X eval 'stuff \"SERVER SHUTTING DOWN. Saving map...\"\015'"
    sleep 5
    as_user "screen -p 0 -S ${SCREENNAME} -X eval 'stuff \"/stop\"\015'"
    sleep 7

    echo "Waiting for server to finish saving..."
    # Loop while the process still exists
    while pgrep -u "${USERNAME}","${GROUPNAME:-root}" -f "${PGREPTEST}" > /dev/null; do
        sleep 1
    done

    if pgrep -u "${USERNAME}","${GROUPNAME:-root}" -f "${PGREPTEST}" > /dev/null ; then
      as_user "screen -p 0 -S ${SCREENNAME} -X quit"
    fi

    echo "${SERVICE} stopped. Running final S3 sync..."
    /usr/bin/sync_to_s3_wrapper
    echo "Final S3 sync complete."
  else
    echo "${SERVICE} was not running."
  fi
}

case "${1}" in
  start) vs_start ;;
  stop) vs_stop ;;
  restart) vs_stop && vs_start ;;
  status) vs_status ;;
  command)
    shift
    as_user "screen -p 0 -S ${SCREENNAME} -X eval 'stuff \"/$*\"\015'"
    ;;
  *)
    echo "Usage: ${0} {start|stop|status|restart|command \"server command\"}"
    exit 1
    ;;
esac
EOF

# Final Permissions fix
chmod +x "${VINTAGE_INSTALL_DIR}/server.sh"
chown "${VINTAGE_USER}:${VINTAGE_USER}" "${VINTAGE_INSTALL_DIR}/server.sh"

echo "Vintage Story script installed at ${VINTAGE_INSTALL_DIR}/server.sh"



# -------------------------------------------------------------
# 3. Create S3 Sync Wrapper Script with Placeholder
# -------------------------------------------------------------
echo "Creating S3 sync wrapper script with placeholder..."

sudo cat <<EOF > /usr/bin/sync_to_s3_wrapper
#!/bin/bash
echo "Initiating Vintage story world sync to S3..."

aws s3 sync \
    "${WORLD_LOCAL_PATH}" \
    "s3://${WORLD_S3_BUCKET_PATH}" \
    --delete

echo "S3 sync complete."
EOF
sudo chmod +x /usr/bin/sync_to_s3_wrapper



# -------------------------------------------------------------
# 4. Create systemd Service for Vintage story Server
# -------------------------------------------------------------
echo "Creating systemd service for Vintage Story..."

sudo cat <<EOF > /etc/systemd/system/vintagestory.service
[Unit]
Description=Vintage Story Dedicated Server
Wants=network-online.target
After=syslog.target network-online.target
Before=shutdown.target reboot.target halt.target

[Service]
Type=forking
Restart=on-failure
RestartSec=15
TimeoutStopSec=300
TimeoutStartSec=300
User=${VINTAGE_USER}
Group=${VINTAGE_USER}
WorkingDirectory=${VINTAGE_INSTALL_DIR}
ExecStart=${VINTAGE_INSTALL_DIR}/server.sh start
ExecStop=${VINTAGE_INSTALL_DIR}/server.sh stop
KillSignal=SIGINT
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
EOF




# -------------------------------------------------------------
# 5. Initial Sync of World Files and admin lists from S3
# -------------------------------------------------------------
echo "Syncing Vintage story worlds from s3://${WORLD_S3_BUCKET_PATH} to ${WORLD_LOCAL_PATH}"

mkdir -p "${WORLD_LOCAL_PATH}"
chown -R ${VINTAGE_USER}:${VINTAGE_USER} "${VINTAGE_SERVER_DATA_DIR}"
sudo -u ${VINTAGE_USER} aws s3 sync "s3://${WORLD_S3_BUCKET_PATH}" "${WORLD_LOCAL_PATH}"





# -------------------------------------------------------------
# 6. Create 30-Minute Periodic Sync Script
# -------------------------------------------------------------
echo "Creating 30-minute periodic sync script..."

sudo touch /var/log/vintage_periodic_sync.log
sudo chown ${VINTAGE_USER}:${VINTAGE_USER} /var/log/vintage_periodic_sync.log

sudo cat <<EOF > ${PERIODIC_SYNC_SCRIPT}
#!/bin/bash
# Log file for cron output
LOG_FILE="/var/log/vintage_periodic_sync.log"

echo "\$(date '+%Y-%m-%d %H:%M:%S') [INFO] Starting periodic S3 sync..." >> "\$LOG_FILE"

# Execute the existing sync wrapper
/usr/bin/sync_to_s3_wrapper

SYNC_STATUS=\$?
if [ \$SYNC_STATUS -eq 0 ]; then
    echo "\$(date '+%Y-%m-%d %H:%M:%S') [SUCCESS] Periodic S3 sync completed." >> "\$LOG_FILE"
else
    echo "\$(date '+%Y-%m-%d %H:%M:%S') [FAILURE] Periodic S3 sync failed with exit code \$SYNC_STATUS." >> "\$LOG_FILE"
fi

exit 0
EOF
sudo chmod +x ${PERIODIC_SYNC_SCRIPT}

# -------------------------------------------------------------
# 7. Set up Crontab for Periodic Sync
# -------------------------------------------------------------
echo "Setting up crontab for user ${VINTAGE_USER} (sync every 30 minutes)..."

(sudo crontab -u ${VINTAGE_USER} -l 2>/dev/null; echo "*/30 * * * * ${PERIODIC_SYNC_SCRIPT} >/dev/null 2>&1") | sudo crontab -u ${VINTAGE_USER} -




# -------------------------------------------------------------
# 8. Start Vintage Story systemd Service
# -------------------------------------------------------------
echo "Starting Vintage story systemd service..."

sudo systemctl daemon-reload
sudo systemctl enable vintagestory.service
sudo systemctl start vintagestory.service

echo "User data execution complete. Server should be running."
