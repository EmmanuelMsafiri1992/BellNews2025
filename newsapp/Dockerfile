# MINIMAL DOCKERFILE - FIXED COMPOSER INSTALLATION
FROM php:8.2-apache

WORKDIR /var/www/html

ENV COMPOSER_ALLOW_SUPERUSER=1
ENV COMPOSER_MEMORY_LIMIT=-1

# Enable Apache rewrite
RUN a2enmod rewrite

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Copy composer files first for better layer caching
COPY composer.json composer.lock* ./

# Install dependencies before copying full app code
RUN composer install --no-dev --ignore-platform-reqs --no-autoloader --no-scripts --no-interaction

# Copy app and create directories
COPY . .
RUN mkdir -p storage/{app,logs,framework/{cache,sessions,views}} bootstrap/cache public/build

# Complete composer installation with autoloader
RUN composer dump-autoload --optimize --no-dev

# Laravel setup
RUN cp .env.example .env 2>/dev/null || true
RUN php artisan key:generate --force || true

# Apache config
RUN sed -i 's|/var/www/html|/var/www/html/public|g' /etc/apache2/sites-available/000-default.conf

# Create entrypoint script
RUN echo '#!/bin/bash' > /entrypoint.sh && \
    echo 'set -e' >> /entrypoint.sh && \
    echo 'cd /var/www/html' >> /entrypoint.sh && \
    echo 'echo "Starting FBellNews Laravel application..."' >> /entrypoint.sh && \
    echo 'php artisan config:clear 2>/dev/null || true' >> /entrypoint.sh && \
    echo 'php artisan cache:clear 2>/dev/null || true' >> /entrypoint.sh && \
    echo 'if [ ! -f "vendor/autoload.php" ]; then' >> /entrypoint.sh && \
    echo '    echo "ERROR: vendor/autoload.php not found. Running composer install..."' >> /entrypoint.sh && \
    echo '    composer install --no-dev --ignore-platform-reqs --no-interaction' >> /entrypoint.sh && \
    echo '    composer dump-autoload --optimize --no-dev' >> /entrypoint.sh && \
    echo 'fi' >> /entrypoint.sh && \
    echo 'echo "Starting Laravel dev server on port 8000..."' >> /entrypoint.sh && \
    echo 'php artisan serve --host=0.0.0.0 --port=8000 &' >> /entrypoint.sh && \
    echo 'echo "Starting Apache on port 80..."' >> /entrypoint.sh && \
    echo 'exec apache2-foreground' >> /entrypoint.sh && \
    chmod +x /entrypoint.sh

EXPOSE 80 8000
ENTRYPOINT ["/entrypoint.sh"]
