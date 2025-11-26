#!/bin/bash

# Valheim Server User Data Script for Ubuntu 24.04 LTS (AMD64)
# This script runs on instance launch to configure and start the Valheim server.
VALHEIM_USER="valheim"
VALHEIM_DATA_DIR="/home/${VALHEIM_USER}/.config/unity3d/IronGate/Valheim"
VALHEIM_INSTALL_DIR="/home/${VALHEIM_USER}/valheim-server"

# Placeholder variables to be replaced by startup lambda
WORLD_S3_BUCKET_PATH="#WORLD_S3"
MODPACK_S3_BUCKET_PATH="#MODPACK_S3"
CONFIG_FILES_S3_BUCKET_PATH="#LISTS_S3"
SERVER_NAME="#SERVER_NAME" 
SERVER_PASSWORD="#PASSWORD"
WORLD_NAME="#WORLD" 
INSTANCE_ID="#INSTANCE" 
AWS_REGION="#REGION"

VALHEIM_PRESET_FLAG="#PRESET_FLAG"
VALHEIM_MODIFIER_FLAGS="#MODIFIER_FLAGS"
VALHEIM_KEY_FLAGS="#KEY_FLAGS"

CONFIG_FILES_LOCAL_PATH="${VALHEIM_DATA_DIR}"

WORLD_LOCAL_PATH="${VALHEIM_DATA_DIR}/worlds_local"

MOD_FILES_LOCAL_PATH="${VALHEIM_INSTALL_DIR}/BepInEx"
MOD_PLUGINS_LOCAL_PATH="${MOD_FILES_LOCAL_PATH}/plugins"
MOD_CONFIG_LOCAL_PATH="${MOD_FILES_LOCAL_PATH}/config"
MOD_PATCHERS_LOCAL_PATH="${MOD_FILES_LOCAL_PATH}/patchers"

PERIODIC_SYNC_SCRIPT="/usr/local/bin/valheim_periodic_sync.sh"

# -------------------------------------------------------------
# 1. Create the Valheim Server Startup Script with Placeholders
# -------------------------------------------------------------
echo "Creating Valheim server startup script with placeholders..."

sudo -u "${VALHEIM_USER}" bash -c "
    cat <<EOF > ${VALHEIM_INSTALL_DIR}/start_valheim.sh
#!/bin/bash

# BepInEx-specific settings
# NOTE: Do not edit unless you know what you are doing!
####
export DOORSTOP_ENABLED=1
export DOORSTOP_TARGET_ASSEMBLY=./BepInEx/core/BepInEx.Preloader.dll

export LD_LIBRARY_PATH="./doorstop_libs:\$LD_LIBRARY_PATH"
export LD_PRELOAD="libdoorstop_x64.so:\$LD_PRELOAD"
####

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
# 2. Sync modpack files from S3 (Safely merging changes)
# -------------------------------------------------------------
echo "Syncing modpack files from S3 (safely merging)..."

if [[ -n "${MODPACK_S3_BUCKET_PATH}" ]]; then
    
    echo "--- S3 Modpack Sync Initiated (Using s3 sync) ---"
    

    
    sudo -u "${VALHEIM_USER}" /usr/bin/aws s3 sync "${MODPACK_S3_BUCKET_PATH}" "${MOD_FILES_LOCAL_PATH}" --recursive

    if [ $? -eq 0 ]; then
        echo "S3 Modpack Sync completed successfully. Existing local files preserved."
    else
        echo "WARNING: S3 Modpack Sync failed."
    fi

    # Ensure final ownership is correct
    chown -R ${VALHEIM_USER}:${VALHEIM_USER} "${VALHEIM_INSTALL_DIR}"

else
    echo "MODPACK_S3_BUCKET_PATH is empty. No modpack sync required."
fi


# -------------------------------------------------------------
# 3. Create S3 Sync Wrapper Script with Placeholder
# -------------------------------------------------------------
echo "Creating S3 sync wrapper script with placeholder..."

sudo cat <<EOF > /usr/bin/sync_to_s3_wrapper
#!/bin/bash
echo "Initiating Valheim world sync to S3..."

# The User Data script will use 'sed' to replace THIS_BUCKET_PLACEHOLDER with the real S3 bucket name.
aws s3 sync \
    "${WORLD_LOCAL_PATH}" \
    "s3://${WORLD_S3_BUCKET_PATH}"

echo "S3 sync complete."
EOF
sudo chmod +x /usr/bin/sync_to_s3_wrapper



# -------------------------------------------------------------
# 4. Create systemd Service for Valheim Server
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
# 5. Initial Sync of World Files and admin lists from S3
# -------------------------------------------------------------
echo "Syncing Valheim worlds from s3://${WORLD_S3_BUCKET_PATH} to ${WORLD_LOCAL_PATH}"

mkdir -p "${WORLD_LOCAL_PATH}"
chown -R ${VALHEIM_USER}:${VALHEIM_USER} "${VALHEIM_DATA_DIR}"
sudo -u ${VALHEIM_USER} aws s3 sync "s3://${WORLD_S3_BUCKET_PATH}" "${WORLD_LOCAL_PATH}"
sudo -u ${VALHEIM_USER} aws s3 sync "s3://${CONFIG_FILES_S3_BUCKET_PATH}" "${CONFIG_FILES_LOCAL_PATH}"




# -------------------------------------------------------------
# 6. Create 30-Minute Periodic Sync Script
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
# 7. Set up Crontab for Periodic Sync
# -------------------------------------------------------------
echo "Setting up crontab for user ${VALHEIM_USER} (sync every 30 minutes)..."

(sudo crontab -u ${VALHEIM_USER} -l 2>/dev/null; echo "*/30 * * * * ${PERIODIC_SYNC_SCRIPT} >/dev/null 2>&1") | sudo crontab -u ${VALHEIM_USER} -


# -------------------------------------------------------------
# 8. Start Valheim systemd Service
# -------------------------------------------------------------
echo "Starting Valheim systemd service..."

sudo systemctl daemon-reload
sudo systemctl enable valheim.service
sudo systemctl start valheim.service

echo "User data execution complete. Server should be running."