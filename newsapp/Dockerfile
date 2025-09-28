# ARM64-optimized Dockerfile for Laravel News App - NANO PI VERSION
FROM --platform=linux/arm64 php:8.2-apache

WORKDIR /var/www/html

# Set ARM64-specific environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1
ENV COMPOSER_ALLOW_SUPERUSER=1

# Enable Apache rewrite (required for Laravel pretty URLs)
RUN a2enmod rewrite

# CRITICAL: Configure APT to prevent cache issues on ARM64
RUN echo 'APT::Update::Post-Invoke-Success {"rm -f /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin || true";};' > /etc/apt/apt.conf.d/99-clear-cache && \
    echo 'APT::Keep-Downloaded-Packages "false";' > /etc/apt/apt.conf.d/99-no-cache && \
    echo 'Dir::Cache::pkgcache "";' > /etc/apt/apt.conf.d/99-no-pkgcache && \
    echo 'Dir::Cache::srcpkgcache "";' > /etc/apt/apt.conf.d/99-no-srcpkgcache

# Update package lists with retries for ARM64
RUN for i in 1 2 3; do \
        apt-get update && break || sleep 5; \
    done

# Install essential packages first (minimal set to avoid memory issues)
RUN apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        wget \
        gnupg \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install development packages in stages to avoid ARM64 memory issues
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libzip-dev \
        unzip \
        git \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libpng-dev \
        libjpeg-dev \
        libfreetype6-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        libsqlite3-dev \
        sqlite3 \
        pkg-config \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Configure and install PHP extensions one by one
RUN docker-php-ext-configure gd --with-freetype --with-jpeg
RUN docker-php-ext-install zip
RUN docker-php-ext-install pdo
RUN docker-php-ext-install pdo_mysql
RUN docker-php-ext-install pdo_sqlite
RUN docker-php-ext-install gd

# Install Node.js for ARM64 with fallback
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - || \
    curl -fsSL https://deb.nodesource.com/setup_16.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Copy composer files & install PHP dependencies (production only)
COPY composer.json composer.lock* /var/www/html/
RUN composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader --no-scripts || \
    composer install --no-dev --no-interaction --no-scripts

# Copy application files (excluding vendor to avoid dev dependencies)
COPY . /var/www/html
RUN rm -rf vendor node_modules

# Reinstall production dependencies and optimize Laravel
RUN composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader --no-scripts && \
    composer dump-autoload --optimize

# Clear Laravel caches
RUN php artisan config:clear || true
RUN php artisan route:clear || true
RUN php artisan view:clear || true

# Build frontend assets with multiple fallbacks for ARM64
RUN if command -v npm >/dev/null 2>&1; then \
        npm install --production=false --no-optional --ignore-scripts --no-audit --no-fund 2>/dev/null || \
        npm install --production=false --ignore-scripts 2>/dev/null || \
        echo "npm install failed"; \
        npm run build 2>/dev/null || \
        npm run production 2>/dev/null || \
        npm run build:tv 2>/dev/null || \
        echo "Frontend build failed, using fallback"; \
    fi

# Laravel setup - create required directories and set permissions
RUN mkdir -p storage/logs storage/framework/{cache,sessions,views} bootstrap/cache database public/build && \
    touch database/database.sqlite && \
    php artisan storage:link || true && \
    chown -R www-data:www-data storage bootstrap/cache database public && \
    chmod -R 775 storage bootstrap/cache database && \
    chmod 664 database/database.sqlite

# Generate Laravel app key if not already set
RUN php artisan key:generate --force || true

# Apache config for Laravel (public folder as DocumentRoot)
RUN sed -i 's|/var/www/html|/var/www/html/public|g' /etc/apache2/sites-available/000-default.conf && \
    sed -i 's|/var/www/|/var/www/html/public|g' /etc/apache2/apache2.conf

# Copy entrypoint script and fix line endings
COPY docker-entrypoint.sh /usr/local/bin/
RUN sed -i 's/\r$//' /usr/local/bin/docker-entrypoint.sh && \
    chmod +x /usr/local/bin/docker-entrypoint.sh

# Final cleanup for ARM64
RUN apt-get autoremove -y && \
    apt-get autoclean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    find /var/cache -type f -delete 2>/dev/null || true

EXPOSE 80
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["apache2-foreground"]