#!/bin/bash

# Vintage Story Server AMI Build Script for Ubuntu 24.04 LTS (AMD64)
# This script sets up the base system and server files.

# Version: 17 February 2026 1.21.6

# Configuration Variables
VINTAGE_USER="vintagestory"
VINTAGE_HOME="/home/${VINTAGE_USER}"
VINTAGE_INSTALL_DIR="${VINTAGE_HOME}/vintagestory-server"
VINTAGE_SERVER_DATA_DIR="${VINTAGE_HOME}/data"


echo "Updating system and installing prerequisites..."
sudo apt update -y
sudo apt install -y \
    dotnet-runtime-8.0 \
    procps \
    screen \
    curl \
    unzip \
    net-tools \

echo "Installing AWS CLI v2 manually..."
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
rm awscliv2.zip
sudo rm -rf aws

if ! id "${VINTAGE_USER}" &>/dev/null; then
    echo "Creating dedicated user: ${VINTAGE_USER}"
    sudo useradd -m "${VINTAGE_USER}"
    sudo chown -R ${VINTAGE_USER}:${VINTAGE_USER} ${VINTAGE_HOME}
fi

sudo -u "${VINTAGE_USER}" bash -c "
    echo 'Downloading Vintage Story server files...'
    cd ${VINTAGE_HOME}
    mkdir -p ${VINTAGE_INSTALL_DIR}
    curl -O https://cdn.vintagestory.at/gamefiles/stable/vs_server_linux-x64_1.21.6.tar.gz
    tar -C ${VINTAGE_INSTALL_DIR} -xzf vs_server_linux-x64_1.21.6.tar.gz
    rm vs_server_linux-x64_1.21.6.tar.gz
    chmod +x ${VINTAGE_INSTALL_DIR}/server.sh
"

sudo chown -R ${VINTAGE_USER}:${VINTAGE_USER} ${VINTAGE_INSTALL_DIR}
echo "Vintage Story AMI base setup complete. Stop this instance and create the AMI now."

