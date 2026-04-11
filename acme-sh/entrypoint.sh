#!/bin/sh
set -eu

DOMAIN="${DOMAIN:-localhost}"
SSL="${SSL:-0}"
SSL_EMAIL="${SSL_EMAIL:-admin@${DOMAIN}}"
SSL_STAGING="${SSL_STAGING:-0}"
CERT_DIR="/etc/letsencrypt"
WEBROOT="/webroot"

if [ "${SSL}" != "1" ]; then
    echo "SSL is disabled, acme-sh is not needed."
    exec sleep infinity
fi

if [ -z "${DOMAIN}" ] || [ "${DOMAIN}" = "localhost" ]; then
    echo "ERROR: DOMAIN must be set to a real domain name"
    exit 1
fi

mkdir -p "${CERT_DIR}/${DOMAIN}"

if [ -f "${CERT_DIR}/${DOMAIN}/fullchain.pem" ]; then
    echo "Certificate already exists for ${DOMAIN}"
    chmod 644 "${CERT_DIR}/${DOMAIN}/privkey.pem" 2>/dev/null || true
else
    echo "=== Obtaining SSL certificate for ${DOMAIN} ==="

    ACME_ARGS="--webroot ${WEBROOT} -d ${DOMAIN} --keylength ec-256"

    if [ "${SSL_STAGING}" = "1" ]; then
        ACME_ARGS="${ACME_ARGS} --staging"
    fi

    acme.sh --register-account -m "${SSL_EMAIL}"
    acme.sh --set-default-ca --server letsencrypt

    if ! acme.sh --issue ${ACME_ARGS}; then
        echo "=== Failed to obtain certificate, will retry ==="
        acme.sh --remove -d "${DOMAIN}" --ecc 2>/dev/null || true
        rm -rf "/acme.sh/${DOMAIN}_ecc" 2>/dev/null || true
        exit 1
    fi

    acme.sh --install-cert -d "${DOMAIN}" --ecc \
        --fullchain-file "${CERT_DIR}/${DOMAIN}/fullchain.pem" \
        --key-file "${CERT_DIR}/${DOMAIN}/privkey.pem" \
        --reloadcmd "docker exec nginx nginx -s reload 2>/dev/null || true"

    chmod 644 "${CERT_DIR}/${DOMAIN}/privkey.pem"
    echo "=== Certificate obtained successfully ==="
fi

echo "Starting acme.sh daemon for auto-renewal..."
exec /entry.sh daemon
