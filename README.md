# wp-lemp-docker

High-performance WordPress Docker stack using nginx, PHP-FPM, MariaDB, and Redis. All images are pre-built — zero server-side builds required.

## Quick Start

1. Copy environment template:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` and set your domain and secure passwords

3. Start the stack:
   ```bash
   docker compose up -d
   ```

4. Access WordPress at `http://your-domain.com`

## SSL Setup

1. Run initial setup without SSL to verify everything works

2. Obtain SSL certificate:
   ```bash
   docker exec nginx /etc/nginx/scripts/obtain-ssl.sh
   ```

3. Enable SSL in `.env`:
   ```
   SSL=1
   ```

4. Restart:
   ```bash
   docker compose restart
   ```

## Cache Modes

Set `CACHE_MODE` in `.env`:
- `fastcgi-cache` (default) — Nginx FastCGI page caching with nginx-helper
- `wp-rocket` — WP-Rocket plugin
- `cache-enabler` — Cache Enabler plugin
- `wp-super-cache` — WP Super Cache plugin
- `redis-cache` — FastCGI page cache + Redis object cache

Redis object cache is always active (via redis-cache plugin) regardless of cache mode.

## Multisite

Set `WP_MULTISITE` in `.env`:
- `no` (default) — Single site
- `subdirectory` — Multisite with subdirectories
- `subdomain` — Multisite with subdomains

## PHP Versions

Set `PHP_VERSION` in `.env`:
- `8.3`
- `8.4`
- `8.5` (default)

## Architecture

```
Client → nginx (:80/:443)
              ↓ (Unix socket)
         php-fpm (:9000)
              ↓ (Docker network)
         mariadb (:3306)
              ↓ (Unix socket)
         redis (object cache)
```

- **nginx** — `ghcr.io/aprakasa/nginx:latest` — Web server, SSL termination, FastCGI page cache
- **php-fpm** — `ghcr.io/aprakasa/php-fpm:${PHP_VERSION}` — WordPress processing with OPcache, Redis, Imagick, GD
- **mariadb** — MariaDB 12 — Database
- **redis** — Redis 8 — Object cache via Unix socket

All inter-service communication uses Unix sockets through shared Docker volumes for maximum performance. No server-side builds — all images are pulled pre-built from GHCR.

## Requirements

- Docker Engine 20.10+
- Docker Compose V2
- 1GB RAM minimum (2GB recommended)
