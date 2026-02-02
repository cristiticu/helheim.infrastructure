#!/bin/bash

# Valheim Server AMI Build Script for Ubuntu 24.04 LTS (AMD64)
# This script sets up the base system and server files.

# Version: 2 February 2026 Default Public Version

# Configuration Variables
VALHEIM_USER="valheim"
VALHEIM_HOME="/home/${VALHEIM_USER}"
VALHEIM_INSTALL_DIR="${VALHEIM_HOME}/valheim-server"
VALHEIM_DATA_DIR="${VALHEIM_HOME}/.config/unity3d/IronGate/Valheim"


echo "Updating system and installing prerequisites..."
sudo apt update -y
sudo add-apt-repository multiverse -y
sudo dpkg --add-architecture i386
sudo apt update -y
sudo apt install -y \
    libatomic1 \
    libpulse0 \
    libpulse-dev \
    libsdl2-2.0-0:i386 \
    libstdc++6:i386 \
    lib32gcc-s1 \
    curl \
    unzip \
    net-tools \
    steamcmd

echo "Installing AWS CLI v2 manually..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm awscliv2.zip
sudo rm -rf aws

if ! id "${VALHEIM_USER}" &>/dev/null; then
    echo "Creating dedicated user: ${VALHEIM_USER}"
    sudo useradd -m "${VALHEIM_USER}"
    sudo mkdir -p "${VALHEIM_DATA_DIR}"/worlds_local
    sudo chown -R ${VALHEIM_USER}:${VALHEIM_USER} ${VALHEIM_HOME}
fi

sudo -u "${VALHEIM_USER}" bash -c "
    echo 'Starting SteamCMD and downloading Valheim server...'
    mkdir -p ${VALHEIM_INSTALL_DIR}
    # Download the Valheim server files (App ID 896660)
    /usr/games/steamcmd +force_install_dir ${VALHEIM_INSTALL_DIR} +login anonymous +app_update 896660 validate +quit
"
sudo chown -R ${VALHEIM_USER}:${VALHEIM_USER} ${VALHEIM_INSTALL_DIR}

echo "Valheim AMI base setup complete. Stop this instance and create the AMI now."
