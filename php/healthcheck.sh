#!/bin/bash
set -euo pipefail

PHP_FPM_SOCKET="/var/run/php-fpm/php-fpm.sock"

if ! pgrep "php-fpm" > /dev/null 2>&1; then
    exit 1
fi

if [ ! -S "${PHP_FPM_SOCKET}" ]; then
    exit 1
fi

if [ ! -w "${PHP_FPM_SOCKET}" ]; then
    exit 1
fi

exit 0
