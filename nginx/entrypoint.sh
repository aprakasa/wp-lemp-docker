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

if [ "${SSL}" = "1" ]; then
    echo "SSL enabled - HTTPS server will be configured"
else
    echo "SSL disabled - HTTP only mode"
fi

if [ -f "${TEMPLATE_DIR}/wordpress.conf.template" ]; then
    echo "Rendering nginx configuration..."

    TEMP_OUTPUT=$(mktemp)

    {
        # HTTP server block
        echo "# HTTP server - redirects to HTTPS when SSL is enabled"
        echo "server {"
        echo "    listen 80;"
        echo "    listen [::]:80;"
        echo "    server_name ${DOMAIN} www.${DOMAIN};"
        echo ""
        echo "    root /var/www/html;"
        echo "    index index.php index.html;"
        echo ""
        echo "    # Let's Encrypt challenge"
        echo "    include /etc/nginx/snippets/letsencrypt.conf;"
        echo ""

        if [ "${SSL}" = "1" ]; then
            echo "    # SSL redirect"
            echo "    location / {"
            echo "        return 301 https://\$server_name\$request_uri;"
            echo "    }"
        else
            echo "    # Cache-specific location block"
            echo "    include /etc/nginx/snippets/${CACHE_MODE}.conf;"
            echo ""
            echo "    # Security"
            echo "    include /etc/nginx/snippets/security.conf;"
            echo ""
            echo "    # Static assets"
            echo "    include /etc/nginx/snippets/static-assets.conf;"
        fi

        echo "}"
        echo ""

        # HTTPS server block
        if [ "${SSL}" = "1" ]; then
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
            echo "    # SSL certificates"
            echo "    ssl_certificate /etc/letsencrypt/${DOMAIN}/fullchain.pem;"
            echo "    ssl_certificate_key /etc/letsencrypt/${DOMAIN}/privkey.pem;"
            echo ""
            echo "    # SSL configuration"
            echo "    include /etc/nginx/snippets/ssl.conf;"
            echo ""
            echo "    # HTTP/3 headers"
            echo "    add_header Alt-Svc 'h3=\":443\"; ma=86400' always;"
            echo "    add_header x-quic 'h3' always;"
            echo ""
            echo "    # Let's Encrypt challenge (also available on HTTPS)"
            echo "    include /etc/nginx/snippets/letsencrypt.conf;"
            echo ""
            echo "    # Cache-specific location block"
            echo "    include /etc/nginx/snippets/${CACHE_MODE}.conf;"
            echo ""
            echo "    # Security"
            echo "    include /etc/nginx/snippets/security.conf;"
            echo ""
            echo "    # Static assets"
            echo "    include /etc/nginx/snippets/static-assets.conf;"
            echo "}"
            echo ""
        fi

        # Multisite subdomain wildcard - SSL
        if [ "${WP_MULTISITE}" = "subdomain" ] && [ "${SSL}" = "1" ]; then
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
            echo "    ssl_certificate /etc/letsencrypt/${DOMAIN}/fullchain.pem;"
            echo "    ssl_certificate_key /etc/letsencrypt/${DOMAIN}/privkey.pem;"
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

        # Multisite subdomain wildcard - non-SSL
        if [ "${WP_MULTISITE}" = "subdomain" ] && [ "${SSL}" != "1" ]; then
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

    rm -f "${TEMP_OUTPUT}"

    ln -sf "${SITES_AVAILABLE}/wordpress.conf" "${SITES_ENABLED}/wordpress.conf"

    echo "Nginx configuration rendered successfully"
fi

echo "Testing nginx configuration..."
nginx -t

echo "Nginx setup complete."
exec /docker-entrypoint.sh nginx -g "daemon off;"
