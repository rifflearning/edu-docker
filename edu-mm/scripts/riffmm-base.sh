#!/bin/bash
# Configuration/setup of the base RiffEdu image
# having copied files to /setupfiles
# env variable(s) MM_USER and MM_UID may be set
#   (use dockerfile ARG) to override the defaults

# Update the apt repositories
apt-get update

# Install curl (needed for the docker container healthcheck)
apt-get install -y --no-install-recommends curl

# Clean up apt package cache
rm -rf /var/lib/apt/lists/*

# Create the local user that will be used to run the RiffEdu mattermost app
# and set a root password
/setupfiles/riffmm-mkuser.sh
