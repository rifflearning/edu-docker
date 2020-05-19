#!/bin/bash
# Setup of riff mattermost on an Ubuntu base image
# having copied files to /setupfiles
# env variable(s) NODE_VER(unused right now) and GOLANG_VER must be set (use dockerfile ARG)

# packages needed to install
INSTALL_PKGS=( curl apt-utils gcc g++ make jq wget gnupg2 ca-certificates )
MM_PKGS=( build-essential libjpeg-dev libpng-dev libtiff-dev libgif-dev git )
DEV_PKGS=( vim-tiny )

# Setting found in Stack Overflow answer to:
# https://stackoverflow.com/questions/22466255/is-it-possible-to-answer-dialog-questions-when-installing-under-docker
# could be an ARG in dockerfile, or we just export it here. It won't persist in the docker image.
export DEBIAN_FRONTEND=noninteractive

# Update package db and install needed packages
echo "SETUP: Update apt and install packages ..."
apt-get update
apt-get install -y --no-install-recommends "${INSTALL_PKGS[@]}" "${MM_PKGS[@]}" "${DEV_PKGS[@]}"

# Install node --set up the apt repository to get the latest node ver 12
# (for production we may want to "lock it down" and use a different way of installing node.
#  such as: https://nodejs.org/dist/v10.13.0/node-v10.13.0-linux-x64.tar.xz)
echo "SETUP: Installing node 12.x ..."
curl -sL https://deb.nodesource.com/setup_12.x | bash -
apt-get install -y --no-install-recommends nodejs
npm install -g npm

# This has problems getting installed, so I'm going to try to install it globally
npm install -g mozjpeg --unsafe-perm=true

# Install golang
echo "SETUP: Installing golang ${GOLANG_VER} ..."
GOLANG_ARC="go${GOLANG_VER}.linux-amd64.tar.gz"
wget --progress=dot:mega "https://dl.google.com/go/${GOLANG_ARC}"
tar -C /usr/local -xzf "${GOLANG_ARC}"
rm "${GOLANG_ARC}"

# In order to have /usr/local/go/bin on the path when running the entrypoint cmd
# we need to use the ENV command in the dockerfile, adding it in /etc/profile won't
# work because that isn't an interactive shell.
# echo 'export PATH=$PATH:/usr/local/go/bin' >> /etc/profile

# Clean up apt package cache
echo "SETUP: Clean up the apt package cache ..."
rm -rf /var/lib/apt/lists/*
