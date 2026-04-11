#!/bin/bash
set -euo pipefail

WORDPRESS_DIR="/var/www/html"
WP_CLI="wp --path=${WORDPRESS_DIR} --allow-root"
PHP_FPM_SOCKET="/var/run/php-fpm/php-fpm.sock"

# Setup directories
echo "Setting up PHP-FPM directories..."
mkdir -p /var/run/php-fpm
chown www-data:www-data /var/run/php-fpm
mkdir -p /var/log/php

# Wait for MariaDB before WordPress setup
echo "Waiting for MariaDB..."
max_tries=30
counter=0
until mysqladmin ping -h "${MARIADB_HOST:-mariadb}" -u "${MARIADB_USER}" -p"${MARIADB_PASSWORD}" --silent 2>/dev/null; do
    counter=$((counter + 1))
    if [ $counter -ge $max_tries ]; then
        echo "ERROR: MariaDB not available after ${max_tries} attempts"
        exit 1
    fi
    sleep 2
done
echo "MariaDB is ready."

# Validate passwords
if [ "${MARIADB_PASSWORD:-}" = "changeme" ] || [ "${MARIADB_ROOT_PASSWORD:-}" = "changeme" ] \
   || [ "${WORDPRESS_ADMIN_PASSWORD:-}" = "changeme" ]; then
    echo "ERROR: Default passwords detected. Set secure passwords in .env"
    exit 1
fi

# Download WordPress if not present
if [ ! -f "${WORDPRESS_DIR}/wp-settings.php" ]; then
    echo "Downloading WordPress..."
    mkdir -p "${WORDPRESS_DIR}"
    $WP_CLI core download --version="${WP_VERSION:-latest}" --locale="${WP_LOCALE:-en_US}"
fi

# Create wp-config.php if not present
if [ ! -f "${WORDPRESS_DIR}/wp-config.php" ]; then
    echo "Configuring WordPress..."
    $WP_CLI config create \
        --dbname="${MARIADB_DATABASE}" \
        --dbuser="${MARIADB_USER}" \
        --dbpass="${MARIADB_PASSWORD}" \
        --dbhost="${MARIADB_HOST:-mariadb}" \
        --dbcharset=utf8mb4 \
        --dbcollate=utf8mb4_unicode_ci

    # WordPress settings
    $WP_CLI config set WP_REDIS_SCHEME unix
    $WP_CLI config set WP_REDIS_PATH "${REDIS_HOST:-/var/run/redis/redis.sock}"
    $WP_CLI config set WP_REDIS_DATABASE 1 --raw
    $WP_CLI config set WP_CACHE true --raw
    $WP_CLI config set DISABLE_WP_CRON true --raw
    $WP_CLI config set WP_MEMORY_LIMIT '256M'
    $WP_CLI config set WP_MAX_MEMORY_LIMIT '512M'
    $WP_CLI config set FS_METHOD 'direct'
    $WP_CLI config set DISALLOW_FILE_EDIT true --raw

    $WP_CLI config set RT_WP_NGINX_HELPER_CACHE_PATH '/var/cache/nginx/fastcgi' --type=constant

    $WP_CLI config shuffle-salts

    # Multisite configuration
    if [ "${WP_MULTISITE:-no}" != "no" ]; then
        $WP_CLI config set MULTISITE true --raw
        $WP_CLI config set WP_ALLOW_MULTISITE true --raw
        if [ "${WP_MULTISITE}" = "subdomain" ]; then
            $WP_CLI config set SUBDOMAIN_INSTALL true --raw
        else
            $WP_CLI config set SUBDOMAIN_INSTALL false --raw
        fi
        $WP_CLI config set DOMAIN_CURRENT_SITE "${DOMAIN:-localhost}"
        $WP_CLI config set PATH_CURRENT_SITE '/'
        $WP_CLI config set SITE_ID_CURRENT_SITE 1 --raw
        $WP_CLI config set BLOG_ID_CURRENT_SITE 1 --raw
    fi

    # SSL admin force
    if [ "${SSL:-0}" = "1" ]; then
        $WP_CLI config set FORCE_SSL_ADMIN true --raw
    fi
fi

# Install WordPress if not installed
if ! $WP_CLI core is-installed 2>/dev/null; then
    echo "Installing WordPress..."
    if [ "${WP_MULTISITE:-no}" != "no" ]; then
        $WP_CLI core multisite-install \
            --url="$([ "${SSL:-0}" = "1" ] && echo "https" || echo "http")://${DOMAIN:-localhost}" \
            --title="${WORDPRESS_SITE_TITLE:-WordPress}" \
            --admin_user="${WORDPRESS_ADMIN_USER:-admin}" \
            --admin_password="${WORDPRESS_ADMIN_PASSWORD}" \
            --admin_email="${WORDPRESS_ADMIN_EMAIL}" \
            --subdomains=$([ "${WP_MULTISITE}" = "subdomain" ] && echo "true" || echo "false")
    else
        $WP_CLI core install \
            --url="$([ "${SSL:-0}" = "1" ] && echo "https" || echo "http")://${DOMAIN:-localhost}" \
            --title="${WORDPRESS_SITE_TITLE:-WordPress}" \
            --admin_user="${WORDPRESS_ADMIN_USER:-admin}" \
            --admin_password="${WORDPRESS_ADMIN_PASSWORD}" \
            --admin_email="${WORDPRESS_ADMIN_EMAIL}"
    fi
    echo "WordPress installed successfully."
fi

# Setup cache mode
echo "Setting up cache mode: ${CACHE_MODE:-fastcgi-cache}"

case "${CACHE_MODE:-fastcgi-cache}" in
    fastcgi-cache)
        $WP_CLI plugin install nginx-helper --activate 2>/dev/null || true
        $WP_CLI eval 'get_role("administrator")->add_cap("Nginx Helper | Config"); get_role("administrator")->add_cap("Nginx Helper | Purge cache");' 2>/dev/null || true
        $WP_CLI option update rt_wp_nginx_helper_options 'a:7:{s:12:"enable_purge";s:1:"1";s:12:"purge_method";s:13:"unlink_files";s:16:"purge_homepage";s:1:"1";s:16:"purge_archives";s:1:"1";s:14:"purge_single";s:1:"1";s:10:"log_level";s:4:"INFO";s:15:"cache_directory";s:27:"/var/cache/nginx/fastcgi";}' --format=serialize 2>/dev/null || true
        ;;
    wp-rocket)
        $WP_CLI plugin install wp-rocket --activate 2>/dev/null || true
        ;;
    cache-enabler)
        $WP_CLI plugin install cache-enabler --activate 2>/dev/null || true
        ;;
    wp-super-cache)
        $WP_CLI plugin install wp-super-cache --activate 2>/dev/null || true
        ;;
    redis-cache)
        $WP_CLI plugin install nginx-helper --activate 2>/dev/null || true
        $WP_CLI eval 'get_role("administrator")->add_cap("Nginx Helper | Config"); get_role("administrator")->add_cap("Nginx Helper | Purge cache");' 2>/dev/null || true
        ;;
esac

# Install and enable Redis object cache
$WP_CLI plugin install redis-cache --activate 2>/dev/null || true
if [ -S "/var/run/redis/redis.sock" ] || [ -n "${REDIS_HOST:-}" ]; then
    max_tries=15
    counter=0
    until $WP_CLI redis status 2>/dev/null | grep -q "Connected" || [ $counter -ge $max_tries ]; do
        counter=$((counter + 1))
        $WP_CLI redis enable 2>/dev/null || true
        sleep 2
    done
fi

# Set permalink structure
$WP_CLI rewrite structure '/%postname%/' 2>/dev/null || true

# Set file permissions
echo "Setting file permissions..."
    find "${WORDPRESS_DIR}" -type d -exec chmod 755 {} +
    find "${WORDPRESS_DIR}" -type f -exec chmod 644 {} +
chown -R www-data:www-data "${WORDPRESS_DIR}"

echo "WordPress setup complete."

# Function to cleanup PHP-FPM on exit
cleanup() {
    echo "Shutting down PHP-FPM..."
    pkill -x "php-fpm" 2>/dev/null || true
}
trap cleanup EXIT TERM INT

# Start PHP-FPM only AFTER WordPress is fully configured
echo "Starting PHP-FPM..."
php-fpm &
PHP_FPM_PID=$!

# Wait for socket to be ready with timeout
echo "Waiting for PHP-FPM socket..."
max_socket_wait=30
counter=0
while [ ! -S "${PHP_FPM_SOCKET}" ]; do
    counter=$((counter + 1))
    if [ $counter -ge $max_socket_wait ]; then
        echo "ERROR: PHP-FPM socket not created after ${max_socket_wait} seconds"
        exit 1
    fi
    if ! kill -0 $PHP_FPM_PID 2>/dev/null; then
        echo "ERROR: PHP-FPM process died"
        exit 1
    fi
    sleep 1
done
echo "PHP-FPM socket is ready."

# Wait for socket to be accepting connections by checking if it's writable
echo "Verifying PHP-FPM is accepting connections..."
max_conn_wait=10
counter=0
while true; do
    if [ -w "${PHP_FPM_SOCKET}" ]; then
        break
    fi
    counter=$((counter + 1))
    if [ $counter -ge $max_conn_wait ]; then
        echo "WARNING: PHP-FPM socket may not be ready for connections"
        break
    fi
    sleep 1
done

echo "PHP-FPM is running and ready."

# Keep the container running by waiting on PHP-FPM process
wait $PHP_FPM_PID
