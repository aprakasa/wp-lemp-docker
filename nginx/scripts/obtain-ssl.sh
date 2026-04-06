#!/bin/bash
set -euo pipefail

DOMAIN="${DOMAIN}"
EMAIL="${SSL_EMAIL:-admin@${DOMAIN}}"
STAGING="${SSL_STAGING:-0}"
WEBROOT="/var/www/certbot"
CERT_DIR="/etc/letsencrypt"

mkdir -p "${WEBROOT}" "${CERT_DIR}"

if [ -f "${CERT_DIR}/${DOMAIN}/fullchain.pem" ]; then
    echo "Certificate already exists for ${DOMAIN}. Skipping issuance."
    exit 0
fi

echo "Obtaining SSL certificate for ${DOMAIN}..."

ACME_ARGS="--webroot ${WEBROOT} -d ${DOMAIN} -d www.${DOMAIN} --keylength ec-256"

if [ "${STAGING}" = "1" ]; then
    ACME_ARGS="${ACME_ARGS} --staging"
fi

if [ ! -f ~/.acme.sh/acme.sh ]; then
    curl -sL https://get.acme.sh | sh -s email="${EMAIL}"
fi

~/.acme.sh/acme.sh --issue ${ACME_ARGS}
~/.acme.sh/acme.sh --install-cert -d "${DOMAIN}" --ecc \
    --fullchain-file "${CERT_DIR}/${DOMAIN}/fullchain.pem" \
    --key-file "${CERT_DIR}/${DOMAIN}/privkey.pem" \
    --reloadcmd "nginx -s reload"

echo "SSL certificate obtained for ${DOMAIN}."
