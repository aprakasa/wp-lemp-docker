#!/bin/sh
set -eu

NGINX_CONF_DIR="/etc/nginx"
SNIPPETS="${NGINX_CONF_DIR}/snippets"
CONF_DIR="/tmp/nginx-conf"

mkdir -p /var/cache/nginx/fastcgi
mkdir -p /var/log/nginx
mkdir -p "${CONF_DIR}"

DOMAIN="${DOMAIN:-localhost}"
CACHE_MODE="${CACHE_MODE:-fastcgi-cache}"
WP_MULTISITE="${WP_MULTISITE:-no}"
SSL="${SSL:-0}"

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
        echo "SSL enabled - no certificate found, starting HTTP-only (waiting for acme-sh sidecar)"
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

        if [ "${WP_MULTISITE}" = "subdirectory" ]; then
            echo "# Multisite subdirectory rules"
            echo "set \$multisite_rewrite \"\";"
            echo "if (\$uri ~* \"^/([_0-9a-zA-Z-]+/)(wp-(content|admin|includes).*)\") {"
            echo "    set \$multisite_rewrite \$2;"
            echo "}"
            echo "if (\$uri ~* \"^/([_0-9a-zA-Z-]+/)(.*\\.php)\$\") {"
            echo "    set \$multisite_rewrite \$2;"
            echo "}"
        fi
    } > "${CONF_DIR}/wordpress.conf"
    echo "Nginx configuration rendered successfully"
}

switch_to_https() {
    echo "=== Certificates found, switching to HTTPS ==="
    render_config "1"
    if nginx -t 2>&1; then
        echo "Reloading nginx with HTTPS..."
        nginx -s reload
        echo "=== HTTPS is now active ==="
    else
        echo "=== HTTPS config test failed, staying in HTTP mode ==="
    fi
}

cleanup() {
    echo "Shutting down nginx..."
    kill "${NGINX_PID:-0}" 2>/dev/null || true
    wait "${NGINX_PID:-0}" 2>/dev/null || true
}
trap cleanup EXIT TERM INT

if [ "${SSL}" = "1" ] && [ "${CERT_EXISTS}" = "yes" ]; then
    render_config "1"
    echo "Testing nginx configuration..."
    nginx -t
    echo "Nginx setup complete."
    exec /docker-entrypoint.sh nginx -g "daemon off;"
elif [ "${SSL}" = "1" ] && [ "${CERT_EXISTS}" = "no" ]; then
    render_config "0"
    echo "Testing nginx configuration..."
    nginx -t
    echo "Starting nginx in HTTP-only mode..."
    /docker-entrypoint.sh nginx -g "daemon off;" &
    NGINX_PID=$!

    echo "Waiting for SSL certificate from acme-sh sidecar..."
    max_wait=300
    waited=0
    while [ ! -f "${CERT_DIR}/fullchain.pem" ] || [ ! -f "${CERT_DIR}/privkey.pem" ]; do
        sleep 5
        waited=$((waited + 5))
        if [ $waited -ge $max_wait ]; then
            echo "=== Timeout waiting for certificate (${max_wait}s). Continuing in HTTP-only mode. ==="
            wait $NGINX_PID
            exit 0
        fi
        if ! kill -0 $NGINX_PID 2>/dev/null; then
            echo "=== Nginx process died ==="
            exit 1
        fi
    done

    echo "Certificate detected!"
    sleep 2
    switch_to_https
    wait $NGINX_PID
    exit 0
else
    render_config "0"
    echo "Testing nginx configuration..."
    nginx -t
    echo "Nginx setup complete."
    exec /docker-entrypoint.sh nginx -g "daemon off;"
fi
