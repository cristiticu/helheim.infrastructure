#!/bin/bash

# Valheim Server User Data Script for Ubuntu 24.04 LTS (AMD64)
# This script runs on instance launch to configure and start the Valheim server.
VALHEIM_USER="valheim"
VALHEIM_DATA_DIR="/home/${VALHEIM_USER}/.config/unity3d/IronGate/Valheim"
VALHEIM_INSTALL_DIR="/home/${VALHEIM_USER}/valheim-server"

# Placeholder variables to be replaced by User Data script
S3_BUCKET_PATH="#S3"
SERVER_NAME="#SERVER_NAME" 
SERVER_PASSWORD="#PASSWORD"
WORLD_NAME="#WORLD" 
INSTANCE_ID="#INSTANCE" 
AWS_REGION="#REGION"

VALHEIM_PRESET_FLAG="#PRESET_FLAG"
VALHEIM_MODIFIER_FLAGS="#MODIFIER_FLAGS"
VALHEIM_KEY_FLAGS="#KEY_FLAGS"

WORLD_LOCAL_PATH="${VALHEIM_DATA_DIR}/worlds_local"
PERIODIC_SYNC_SCRIPT="/usr/local/bin/valheim_periodic_sync.sh"

# -------------------------------------------------------------
# 1. Create the Valheim Server Startup Script with Placeholders
# -------------------------------------------------------------
echo "Creating Valheim server startup script with placeholders..."

sudo -u "${VALHEIM_USER}" bash -c "
    cat <<EOF > ${VALHEIM_INSTALL_DIR}/start_valheim.sh
#!/bin/bash

# Required for Valheim server to find its libraries
export LD_LIBRARY_PATH=./linux64:\$LD_LIBRARY_PATH
export SteamAppId=892970

echo 'Starting Valheim server...'

cleanup_on_exit() {
    # ESCAPED QUOTES to prevent truncation!
    echo \"Received SIGINT. Initiating graceful server shutdown.\"
    echo \"Waiting for Valheim server to exit after save...\"

    # Valheim server (child process) should receive SIGINT via shell/systemd propagation.
    # We wait for it to finish its save and exit.
    wait \$VALHEIM_PID

    echo \"Server process exited. Running final S3 sync.\"
    /usr/bin/sync_to_s3_wrapper
    
    exit 0
}

trap cleanup_on_exit SIGINT

./valheim_server.x86_64 \
    -name \"${SERVER_NAME}\" \
    -port 2456 \
    -nographics \
    -world \"${WORLD_NAME}\" \
    -password \"${SERVER_PASSWORD}\" \
    -public 1 ${VALHEIM_PRESET_FLAG} ${VALHEIM_MODIFIER_FLAGS} ${VALHEIM_KEY_FLAGS} &

VALHEIM_PID=\$!

echo \"Valheim server PID: \$VALHEIM_PID\"
wait \$VALHEIM_PID
echo \"Valheim server process exited unexpectedly. Running final S3 sync.\"
/usr/bin/sync_to_s3_wrapper


EOF

    chmod +x ${VALHEIM_INSTALL_DIR}/start_valheim.sh
"



# -------------------------------------------------------------
# 2. Create S3 Sync Wrapper Script with Placeholder
# -------------------------------------------------------------
echo "Creating S3 sync wrapper script with placeholder..."

sudo cat <<EOF > /usr/bin/sync_to_s3_wrapper
#!/bin/bash
echo "Initiating Valheim world sync to S3..."

# The User Data script will use 'sed' to replace THIS_BUCKET_PLACEHOLDER with the real S3 bucket name.
aws s3 sync \
    "${WORLD_LOCAL_PATH}" \
    "s3://${S3_BUCKET_PATH}"

echo "S3 sync complete."
EOF
sudo chmod +x /usr/bin/sync_to_s3_wrapper



# -------------------------------------------------------------
# 3. Create systemd Service for Valheim Server
# -------------------------------------------------------------
echo "Creating systemd service for Valheim..."

sudo cat <<EOF > /etc/systemd/system/valheim.service
[Unit]
Description=Valheim Dedicated Server
Wants=network-online.target
After=syslog.target network-online.target
Before=shutdown.target reboot.target halt.target

[Service]
Type=simple
Restart=on-failure
RestartSec=15
TimeoutStopSec=300
TimeoutStartSec=300
User=${VALHEIM_USER}
WorkingDirectory=${VALHEIM_INSTALL_DIR}
ExecStart=${VALHEIM_INSTALL_DIR}/start_valheim.sh
KillSignal=SIGINT
RemainAfterExit=no

[Install]
WantedBy=multi-user.target
EOF



# -------------------------------------------------------------
# 4. Initial Sync of World Files from S3
# -------------------------------------------------------------
echo "Syncing Valheim worlds from s3://${S3_BUCKET_PATH} to ${WORLD_LOCAL_PATH}"

mkdir -p "${WORLD_LOCAL_PATH}"
chown -R ${VALHEIM_USER}:${VALHEIM_USER} "${VALHEIM_DATA_DIR}"
sudo -u ${VALHEIM_USER} aws s3 sync "s3://${S3_BUCKET_PATH}" "${WORLD_LOCAL_PATH}"




# -------------------------------------------------------------
# 5. Create 30-Minute Periodic Sync Script
# -------------------------------------------------------------
echo "Creating 30-minute periodic sync script..."

sudo cat <<EOF > ${PERIODIC_SYNC_SCRIPT}
#!/bin/bash
# Log file for cron output
LOG_FILE="/var/log/valheim_periodic_sync.log"

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
# 6. Set up Crontab for Periodic Sync
# -------------------------------------------------------------
echo "Setting up crontab for user ${VALHEIM_USER} (sync every 30 minutes)..."

(sudo crontab -u ${VALHEIM_USER} -l 2>/dev/null; echo "*/30 * * * * ${PERIODIC_SYNC_SCRIPT} >/dev/null 2>&1") | sudo crontab -u ${VALHEIM_USER} -


# -------------------------------------------------------------
# 7. Start Valheim systemd Service
# -------------------------------------------------------------
echo "Starting Valheim systemd service..."

sudo systemctl daemon-reload
sudo systemctl enable valheim.service
sudo systemctl start valheim.service

echo "User data execution complete. Server should be running."