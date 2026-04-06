FROM php:8.3-fpm-alpine

RUN apk add --no-cache \
    bash \
    curl \
    git \
    mysql-client \
    imagemagick \
    imagemagick-dev \
    libzip-dev \
    icu-dev \
    libpng-dev \
    libjpeg-turbo-dev \
    freetype-dev \
    libwebp-dev \
    oniguruma-dev \
    linux-headers \
    $PHPIZE_DEPS \
    && docker-php-ext-configure gd \
        --with-freetype \
        --with-jpeg \
        --with-webp \
    && docker-php-ext-install -j$(nproc) \
        bcmath \
        exif \
        gd \
        intl \
        mysqli \
        opcache \
        pcntl \
        pdo_mysql \
        zip \
    && pecl install redis-6.1.0 \
    && docker-php-ext-enable redis \
    && apk del $PHPIZE_DEPS linux-headers

RUN curl -sL https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    -o /usr/local/bin/wp \
    && chmod +x /usr/local/bin/wp

COPY php/opcache.ini /usr/local/etc/php/conf.d/opcache.ini
COPY php/custom.ini /usr/local/etc/php/conf.d/custom.ini
COPY php/zz-docker.conf /usr/local/etc/php-fpm.d/zz-docker.conf
COPY php/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
