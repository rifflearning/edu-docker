# Args for FROM directives
ARG UBUNTU_VER=latest

#
# ---- Base Node image ----
FROM ubuntu:${UBUNTU_VER} AS base

# Copy basic setup files to the image
# (not all of them so that the docker cache can skip some lengthy steps)
COPY scripts/bashrc scripts/entrypoint.sh scripts/riffmm-base.sh scripts/riffmm-mkuser.sh /setupfiles/

# run the setup script
ARG MM_USER=mmuser
ARG MM_UID=1000
RUN chmod +x /setupfiles/*.sh \
    && /setupfiles/riffmm-base.sh

# create and set working directory owned by non-root user; set that user
WORKDIR /home/${MM_USER}
USER ${MM_USER}

#
# ---- Build environment (go and node and related pkgs) ----
FROM base as buildenv
ARG NODE_VER=10
ARG GOLANG_VER=1.11.5

# Copy the build environment install script to the image
COPY scripts/riffmm-buildenv.sh /setupfiles/

# run the setup script
USER root
RUN chmod +x /setupfiles/*.sh \
    && /setupfiles/riffmm-buildenv.sh

#
# ---- Build server and webapp ----
FROM buildenv AS build

# set the GOPATH and the PATH to find the go executables
ARG MM_USER=mmuser
ENV GOPATH /home/${MM_USER}/go
ENV PATH $GOPATH/bin:/usr/local/go/bin:$PATH

# see https://github.com/moby/moby/issues/35018 for why --chown=${MM_USER}:${MM_USER} is not
# being used below. -mjl
COPY --chown=mmuser:mmuser scripts/riffmm-build.sh /home/${MM_USER}/
RUN chown -R ${MM_USER}:${MM_USER} .

ARG MM_SERVER_REF=develop
ARG MM_WEBAPP_REF=develop

USER ${MM_USER}
RUN chmod +x ./riffmm-build.sh \
    && ./riffmm-build.sh

#
# ---- Staging ----
FROM base AS staging
LABEL Description="staging: This image runs the RiffEdu mattermost application"

# Copy the built app
ARG MM_USER=mmuser
COPY --from=build --chown=mmuser:mmuser /home/${MM_USER}/riffedu/ riffedu/

# This is the staging image, set NODE_ENV to reflect that
ENV NODE_ENV=staging

# expose port that the mattermost server listens to
EXPOSE 8065

# Healthcheck to make sure container is ready
HEALTHCHECK CMD curl --fail http://localhost:8065 || exit 1

# Declare volumes for mount point directories
VOLUME ["/home/mmuser/riffedu/data",        \
        "/home/mmuser/riffedu/logs",        \
        "/home/mmuser/riffedu/config",      \
        "/home/mmuser/riffedu/plugins",     \
        "/home/mmuser/riffedu/client/plugins"]

# Set the default command to run when the container is started
CMD ["riffedu/bin/mattermost"]
