#! /bin/sh
#
# Explicitly specifying the deploy hook will run it when getting the cert initially AND
# when renewing the cert (and certbot will only run it once even though it is located in
# the renewal-hooks deploy directory. Having it there means it will also run if the certbot renew
# command deploys a new cert.

DEPLOY_HOOK='/etc/letsencrypt/renewal-hooks/deploy/0000-link-nginx-snippet.sh'
WEBROOT_PATH='/usr/share/nginx/html'

domain=$1

if [ -z "$domain" ]
then
        echo "ERROR: $0 requires the fully qualified domain name for the ssl cert as the first argument"
        exit 1
fi

certbot certonly --keep --deploy-hook "$DEPLOY_HOOK" --webroot --webroot-path "$WEBROOT_PATH" --domain $domain
