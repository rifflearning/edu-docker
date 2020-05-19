#!/bin/bash
# Create the RiffEdu user on an Ubuntu base image
# having copied files to /setupfiles
# env variable(s) MM_USER(unused right now) and MM_UID may be set
#   (use dockerfile ARG) to override the defaults

MM_USER="${MM_USER:-mmuser}"
MM_UID=${MM_UID:-1000}

# Create a non-root mattermost user to run the riffedu mattermost app in this container
echo "SETUP: Create non-root user ${MM_USER} ..."
useradd ${MM_USER} --uid ${MM_UID} --user-group --shell /bin/bash --create-home

# Modified bashrc which defines some aliases and an interactive prompt
mv /root/.bashrc /root/bashrc-original
ln -s /setupfiles/bashrc /root/.bashrc

mv /home/${MM_USER}/.bashrc /home/${MM_USER}/bashrc-original
ln -s /setupfiles/bashrc /home/${MM_USER}/.bashrc

ln -s /setupfiles/entrypoint.sh /home/${MM_USER}/entrypoint.sh

# Give ownership of everything in the MM_USER's home to the MM_USER
chown -R ${MM_USER}:${MM_USER} /home/${MM_USER}

# set the root password to password (I don't care that it's simple it's only for development)
# this probably shouldn't exist in a production container
echo "root:password" | chpasswd
