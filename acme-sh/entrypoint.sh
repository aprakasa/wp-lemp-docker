#!/bin/sh
set -euo pipefail

DOMAIN="${DOMAIN:-localhost}"
SSL_EMAIL="${SSL_EMAIL:-admin@${DOMAIN}}"
SSL_STAGING="${SSL_STAGING:-0}"
CERT_DIR="/etc/letsencrypt"
WEBROOT="/webroot"

if [ -z "${DOMAIN}" ] || [ "${DOMAIN}" = "localhost" ]; then
    echo "ERROR: DOMAIN must be set to a real domain name"
    exit 1
fi

mkdir -p "${CERT_DIR}/${DOMAIN}"

if [ -f "${CERT_DIR}/${DOMAIN}/fullchain.pem" ]; then
    echo "Certificate already exists for ${DOMAIN}"
else
    echo "=== Obtaining SSL certificate for ${DOMAIN} ==="

    ACME_ARGS="--webroot ${WEBROOT} -d ${DOMAIN} -d www.${DOMAIN} --keylength ec-256"

    if [ "${SSL_STAGING}" = "1" ]; then
        ACME_ARGS="${ACME_ARGS} --staging"
    fi

    echo "Waiting for nginx to be ready..."
    max_wait=60
    waited=0
    while [ ! -d "${WEBROOT}/.well-known" ] && [ $waited -lt $max_wait ]; do
        sleep 2
        waited=$((waited + 2))
    done

    acme.sh --issue ${ACME_ARGS}

    acme.sh --install-cert -d "${DOMAIN}" --ecc \
        --fullchain-file "${CERT_DIR}/${DOMAIN}/fullchain.pem" \
        --key-file "${CERT_DIR}/${DOMAIN}/privkey.pem"

    echo "=== Certificate obtained successfully ==="
fi

echo "Starting acme.sh daemon for auto-renewal..."
exec acme.sh --daemon --listen-v4
