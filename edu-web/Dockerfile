# Args for FROM directives
ARG NGINX_VER=latest

#
# ---- Base web-server image ----
FROM nginx:${NGINX_VER} AS base

# Copy the self-signed ssl files
COPY ssl/ /etc/ssl/

# point the site ssl key and crt to the self-signed ones if the docker secrets aren't loaded.
# Remove any existing sample configurations so they don't get loaded
RUN mkdir -p /run/secrets && \
    ln -s /etc/ssl/private/nginx-selfsigned.key /run/secrets/site.key && \
    ln -s /etc/ssl/certs/nginx-selfsigned.crt /run/secrets/site.crt && \
    rm /etc/nginx/conf.d/*.conf

# Copy the nginx configuration files that set up nginx to reverse proxy the
#  riffedu services (riff-data, riff-mm, signalmaster...)
COPY conf /etc/nginx/

# Expose both the standard http and standard https ports
EXPOSE 80 443

LABEL Description="prod: This image is used to start the riff mattermost reverse proxy server"
