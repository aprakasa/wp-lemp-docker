#!/bin/sh
set -euo pipefail

NGINX_CONF_DIR="/etc/nginx"
TEMPLATE_DIR="${NGINX_CONF_DIR}/templates"
SITES_AVAILABLE="${NGINX_CONF_DIR}/sites-available"
SITES_ENABLED="${NGINX_CONF_DIR}/sites-enabled"
SNIPPETS="${NGINX_CONF_DIR}/snippets"

mkdir -p /var/cache/nginx/fastcgi
mkdir -p /var/log/nginx
mkdir -p "${SITES_AVAILABLE}" "${SITES_ENABLED}" "${SNIPPETS}"
mkdir -p /var/www/certbot
mkdir -p /etc/letsencrypt

DOMAIN="${DOMAIN:-localhost}"
CACHE_MODE="${CACHE_MODE:-fastcgi-cache}"
WP_MULTISITE="${WP_MULTISITE:-no}"
SSL="${SSL:-0}"
SSL_EMAIL="${SSL_EMAIL:-admin@${DOMAIN}}"
SSL_STAGING="${SSL_STAGING:-0}"

CACHE_SNIPPET="${SNIPPETS}/${CACHE_MODE}.conf"
if [ ! -f "${CACHE_SNIPPET}" ]; then
    echo "WARNING: Cache mode '${CACHE_MODE}' snippet not found, falling back to fastcgi-cache"
    CACHE_MODE="fastcgi-cache"
fi

echo "Active cache mode: ${CACHE_MODE}"

if [ "${WP_MULTISITE}" = "subdomain" ]; then
    echo "Configured for multisite subdomain mode"
elif [ "${WP_MULTISITE}" = "subdirectory" ]; then
    echo "Configured for multisite subdirectory mode"
else
    echo "Configured for single site mode"
fi

CERT_DIR="/etc/letsencrypt/${DOMAIN}"
CERT_EXISTS="no"
if [ "${SSL}" = "1" ] && [ -f "${CERT_DIR}/fullchain.pem" ] && [ -f "${CERT_DIR}/privkey.pem" ]; then
    CERT_EXISTS="yes"
fi

if [ "${SSL}" = "1" ]; then
    if [ "${CERT_EXISTS}" = "yes" ]; then
        echo "SSL enabled - certificate found"
    else
        echo "SSL enabled - no certificate found, starting HTTP-only to obtain certificate"
    fi
else
    echo "SSL disabled - HTTP only mode"
fi

render_config() {
    _ssl_enabled="${1:-0}"

    echo "Rendering nginx configuration (SSL=${_ssl_enabled})..."

    {
        echo "# HTTP server"
        echo "server {"
        echo "    listen 80;"
        echo "    listen [::]:80;"
        echo "    server_name ${DOMAIN} www.${DOMAIN};"
        echo ""
        echo "    root /var/www/html;"
        echo "    index index.php index.html;"
        echo ""
        echo "    include /etc/nginx/snippets/letsencrypt.conf;"
        echo ""

        if [ "${_ssl_enabled}" = "1" ]; then
            echo "    location / {"
            echo "        return 301 https://\$server_name\$request_uri;"
            echo "    }"
        else
            echo "    include /etc/nginx/snippets/${CACHE_MODE}.conf;"
            echo ""
            echo "    include /etc/nginx/snippets/security.conf;"
            echo ""
            echo "    include /etc/nginx/snippets/static-assets.conf;"
        fi

        echo "}"
        echo ""

        if [ "${_ssl_enabled}" = "1" ]; then
            echo "# HTTPS server"
            echo "server {"
            echo "    listen 443 ssl;"
            echo "    listen [::]:443 ssl;"
            echo "    http2 on;"
            echo "    listen 443 quic;"
            echo "    listen [::]:443 quic;"
            echo ""
            echo "    server_name ${DOMAIN} www.${DOMAIN};"
            echo ""
            echo "    root /var/www/html;"
            echo "    index index.php index.html;"
            echo ""
            echo "    ssl_certificate ${CERT_DIR}/fullchain.pem;"
            echo "    ssl_certificate_key ${CERT_DIR}/privkey.pem;"
            echo ""
            echo "    include /etc/nginx/snippets/ssl.conf;"
            echo ""
            echo "    add_header Alt-Svc 'h3=\":443\"; ma=86400' always;"
            echo "    add_header x-quic 'h3' always;"
            echo ""
            echo "    include /etc/nginx/snippets/letsencrypt.conf;"
            echo ""
            echo "    include /etc/nginx/snippets/${CACHE_MODE}.conf;"
            echo ""
            echo "    include /etc/nginx/snippets/security.conf;"
            echo ""
            echo "    include /etc/nginx/snippets/static-assets.conf;"
            echo "}"
            echo ""
        fi

        if [ "${WP_MULTISITE}" = "subdomain" ] && [ "${_ssl_enabled}" = "1" ]; then
            echo "# Multisite subdomain wildcard (SSL)"
            echo "server {"
            echo "    listen 443 ssl;"
            echo "    listen [::]:443 ssl;"
            echo "    http2 on;"
            echo "    listen 443 quic;"
            echo "    listen [::]:443 quic;"
            echo ""
            echo "    server_name *.${DOMAIN};"
            echo ""
            echo "    root /var/www/html;"
            echo "    index index.php index.html;"
            echo ""
            echo "    ssl_certificate ${CERT_DIR}/fullchain.pem;"
            echo "    ssl_certificate_key ${CERT_DIR}/privkey.pem;"
            echo "    include /etc/nginx/snippets/ssl.conf;"
            echo ""
            echo "    add_header Alt-Svc 'h3=\":443\"; ma=86400' always;"
            echo "    add_header x-quic 'h3' always;"
            echo ""
            echo "    include /etc/nginx/snippets/${CACHE_MODE}.conf;"
            echo "    include /etc/nginx/snippets/security.conf;"
            echo "    include /etc/nginx/snippets/static-assets.conf;"
            echo "}"
            echo ""
        fi

        if [ "${WP_MULTISITE}" = "subdomain" ] && [ "${_ssl_enabled}" != "1" ]; then
            echo "# Multisite subdomain wildcard (HTTP)"
            echo "server {"
            echo "    listen 80;"
            echo "    listen [::]:80;"
            echo "    server_name *.${DOMAIN};"
            echo ""
            echo "    root /var/www/html;"
            echo "    index index.php index.html;"
            echo ""
            echo "    include /etc/nginx/snippets/${CACHE_MODE}.conf;"
            echo "    include /etc/nginx/snippets/security.conf;"
            echo "    include /etc/nginx/snippets/static-assets.conf;"
            echo "}"
            echo ""
        fi
    } > "${SITES_AVAILABLE}/wordpress.conf"

    ln -sf "${SITES_AVAILABLE}/wordpress.conf" "${SITES_ENABLED}/wordpress.conf"
    echo "Nginx configuration rendered successfully"
}

ensure_curl() {
    if command -v curl > /dev/null 2>&1; then
        return 0
    fi
    echo "Installing curl..."
    if command -v apk > /dev/null 2>&1; then
        apk add --no-cache curl
    elif command -v apt-get > /dev/null 2>&1; then
        apt-get update -qq && apt-get install -y -qq curl
    else
        echo "ERROR: Cannot install curl (no apk or apt-get)"
        return 1
    fi
}

obtain_certificate() {
    echo "=== Auto-SSL: Obtaining certificate for ${DOMAIN} ==="

    if ! ensure_curl; then
        echo "=== FAILED: curl is required but not available ==="
        return 1
    fi

    if [ ! -f ~/.acme.sh/acme.sh ]; then
        echo "Installing acme.sh..."
        curl -sL https://get.acme.sh | sh -s email="${SSL_EMAIL}"
    fi

    ACME_ARGS="--webroot /var/www/certbot -d ${DOMAIN} -d www.${DOMAIN} --keylength ec-256"

    if [ "${SSL_STAGING}" = "1" ]; then
        ACME_ARGS="${ACME_ARGS} --staging"
    fi

    echo "Issuing certificate..."
    if ~/.acme.sh/acme.sh --issue ${ACME_ARGS}; then
        mkdir -p "${CERT_DIR}"
        ~/.acme.sh/acme.sh --install-cert -d "${DOMAIN}" --ecc \
            --fullchain-file "${CERT_DIR}/fullchain.pem" \
            --key-file "${CERT_DIR}/privkey.pem" \
            --reloadcmd "nginx -s reload"
        echo "=== Certificate obtained successfully ==="
        return 0
    else
        echo "=== FAILED to obtain certificate. Continuing in HTTP-only mode. ==="
        return 1
    fi
}

switch_to_https() {
    echo "=== Switching to HTTPS mode ==="
    render_config "1"
    echo "Testing HTTPS configuration..."
    if nginx -t 2>&1; then
        echo "Reloading nginx with HTTPS..."
        nginx -s reload
        echo "=== HTTPS is now active ==="
    else
        echo "=== HTTPS config test failed, staying in HTTP mode ==="
    fi
}

setup_renewal_cron() {
    echo "Setting up automatic certificate renewal (daily check)..."
    CRON_LINE="0 3 * * * ~/.acme.sh/acme.sh --cron --home ~/.acme.sh > /dev/null 2>&1"
    if ! crontab -l 2>/dev/null | grep -q "acme.sh --cron"; then
        (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
        echo "Renewal cron job installed"
    fi
}

if [ "${SSL}" = "1" ] && [ "${CERT_EXISTS}" = "yes" ]; then
    render_config "1"
elif [ "${SSL}" = "1" ] && [ "${CERT_EXISTS}" = "no" ]; then
    render_config "0"
    echo "Testing nginx configuration..."
    nginx -t
    echo "Starting nginx in HTTP-only mode to obtain certificate..."
    /docker-entrypoint.sh nginx -g "daemon off;" &
    NGINX_PID=$!

    sleep 3

    if obtain_certificate; then
        setup_renewal_cron
        switch_to_https
        wait $NGINX_PID
    else
        echo "=== Running in HTTP-only mode ==="
        setup_renewal_cron
        wait $NGINX_PID
    fi
    exit 0
else
    render_config "0"
fi

echo "Testing nginx configuration..."
nginx -t

echo "Nginx setup complete."
exec /docker-entrypoint.sh nginx -g "daemon off;"
