#!/bin/bash
# Health check for PHP-FPM + WordPress readiness
set -euo pipefail

WORDPRESS_DIR="/var/www/html"
WP_CLI="wp --path=${WORDPRESS_DIR} --allow-root --quiet"

# Check if PHP-FPM is responding
if ! php-fpm -t > /dev/null 2>&1; then
    echo "PHP-FPM config test failed"
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

echo "PHP-FPM and WordPress are ready"
exit 0
