# Args for FROM directives
ARG NODE_VER=10

#
# ---- Node app initialization image ----
FROM node:${NODE_VER}
# The node:8 npm (v 5.6) has some issues, update it to latest
RUN npm install -g npm
# Modified bashrc which defines some aliases and an interactive prompt
COPY bashrc /root/.bashrc
COPY --chown=node:node bashrc /home/node/.bashrc
# set the root password to password (I don't care that it's simple it's only for development)
# this shouldn't exist in a production container
RUN echo "root:password" | chpasswd
# create and set working directory owned by non-root user; set that user
WORKDIR /app
RUN chown node:node /app
USER node
# describe this image
LABEL Description="this image initializes whatever is bound at /app and exits"
# define command to initialize the /app directory (npm install and build)
# A volume must be bound at /app w/ a Makefile (expected to be the local
# repository working directory for the riff-server project)
CMD ["make", "init"]
