FROM php:8.2-apache

WORKDIR /var/www/html

# Enable Apache rewrite (required for Laravel pretty URLs)
RUN a2enmod rewrite

# Install system dependencies + PHP extensions
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
       libzip-dev \
       unzip \
       git \
       libpng-dev \
       libjpeg-dev \
       libfreetype6-dev \
       libsqlite3-dev \
       sqlite3 \
       pkg-config \
       curl \
       ca-certificates \
       wget \
    && docker-php-ext-configure gd \
         --with-freetype=/usr/include/ \
         --with-jpeg=/usr/include/ \
    && docker-php-ext-install \
         zip \
         pdo \
         pdo_mysql \
         pdo_sqlite \
         gd \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/cache/apt/archives/*.deb /var/cache/apt/archives/partial/*.deb /var/cache/apt/*.bin

# Install Node.js (for Vite build) - ARM64 compatible
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/cache/apt/archives/*.deb

# Install Composer
RUN curl -sS https://getcomposer.org/installer \
      | php -- --install-dir=/usr/local/bin --filename=composer

# Copy composer files & install PHP dependencies (production only)
COPY composer.json composer.lock* /var/www/html/
RUN composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader --no-scripts

# Copy application files (excluding vendor to avoid dev dependencies)
COPY . /var/www/html
RUN rm -rf vendor

# Reinstall production dependencies and optimize Laravel
RUN composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader --no-scripts \
 && composer dump-autoload --optimize \
 && php artisan config:clear \
 && php artisan route:clear \
 && php artisan view:clear

# Build frontend assets
RUN if command -v npm >/dev/null 2>&1; then \
        npm install --production=false --no-optional --ignore-scripts && \
        npm run build || echo "Vite build failed, skipping..."; \
    fi

# Laravel setup - create required directories and set permissions
RUN mkdir -p storage/logs storage/framework/{cache,sessions,views} \
    && mkdir -p database \
    && touch database/database.sqlite \
    && php artisan storage:link || true \
    && chown -R www-data:www-data storage bootstrap/cache database \
    && chmod -R 775 storage bootstrap/cache database

# Generate Laravel app key if not already set
RUN php artisan key:generate || echo "App key already exists"

# Apache config for Laravel (public folder as DocumentRoot)
RUN sed -i 's|/var/www/html|/var/www/html/public|g' /etc/apache2/sites-available/000-default.conf \
 && sed -i 's|/var/www/|/var/www/html/public|g' /etc/apache2/apache2.conf

# Copy entrypoint script and fix line endings
COPY docker-entrypoint.sh /usr/local/bin/
RUN sed -i 's/\r$//' /usr/local/bin/docker-entrypoint.sh && chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 80
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["apache2-foreground"]
