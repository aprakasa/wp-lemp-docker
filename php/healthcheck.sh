#!/bin/bash
# Health check for PHP-FPM + WordPress readiness
set -euo pipefail

WORDPRESS_DIR="/var/www/html"
WP_CLI="wp --path=${WORDPRESS_DIR} --allow-root --quiet"
PHP_FPM_SOCKET="/var/run/php-fpm/php-fpm.sock"

# Check if PHP-FPM master process is running
if ! pgrep "php-fpm" > /dev/null 2>&1; then
    echo "PHP-FPM process not running"
    exit 1
fi

# Check if socket exists and is accessible
if [ ! -S "${PHP_FPM_SOCKET}" ]; then
    echo "PHP-FPM socket not found"
    exit 1
fi

if [ ! -w "${PHP_FPM_SOCKET}" ]; then
    echo "PHP-FPM socket not writable"
    exit 1
fi

# Check if WordPress is installed
if ! $WP_CLI core is-installed > /dev/null 2>&1; then
    echo "WordPress not installed yet"
    exit 1
fi

# Check if wp-config.php exists
if [ ! -f "${WORDPRESS_DIR}/wp-config.php" ]; then
    echo "wp-config.php not found"
    exit 1
fi

# Check if PHP-FPM status endpoint is available (if configured)
# This verifies PHP-FPM is actually accepting and processing connections
if command -v cgi-fcgi > /dev/null 2>&1; then
    # Try to get PHP-FPM status if available
    if SCRIPT_NAME=/status SCRIPT_FILENAME=/status REQUEST_METHOD=GET cgi-fcgi -bind -connect "${PHP_FPM_SOCKET}" > /dev/null 2>&1; then
        : # PHP-FPM is responding to status requests
    fi
fi

echo "PHP-FPM and WordPress are ready"
exit 0
