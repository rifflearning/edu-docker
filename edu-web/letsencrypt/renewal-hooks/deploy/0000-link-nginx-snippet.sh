#! /bin/sh
#
# Handle updating nginx config (via snippets) for initial cert retrieval
# and reloading nginx after cert renewals.

NGINX_SNIPPET_DIR=/etc/nginx/snippets/
NGINX_CERT_SNIPPET_NAME=site_ssl_cert.conf

certificate_name=$(basename $RENEWED_LINEAGE)
cert_snippet_name=${certificate_name}_ssl_cert.conf
cert_snippet_path="${NGINX_SNIPPET_DIR}${cert_snippet_name}"


# The 1st time certbot gets a certificate we need to update nginx config to point to the
# letsencrypt "live" certificate which is a link that certbot will update when certs are renewed.
# nginx is initially configured to point to a self-signed cert for localhost so that nginx can load,
# but that cert needs to be replaced for access from the internet via a valid domain.
if [ -f "$cert_snippet_path" ]; then
    echo "nginx already configured to use letsencrypt certificate $certificate_name"
else
    # create the cert snippet file pointing to the live certs
    # (heredoc indentation MUST be tabs not spaces!)
    cat > $cert_snippet_path <<- EOF
		ssl_certificate $RENEWED_LINEAGE/fullchain.pem;
		ssl_certificate_key $RENEWED_LINEAGE/privkey.pem;
		EOF

    ln -f -s $cert_snippet_path ${NGINX_SNIPPET_DIR}${NGINX_CERT_SNIPPET_NAME}
    echo "nginx configured to use letsencrypt certificate $certificate_name"
fi

# Send signal to nginx to reload config which will load the updated certs
nginx -s reload
echo "nginx reload requested"
