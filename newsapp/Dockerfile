# MINIMAL DOCKERFILE - SKIP ALL PERMISSION OPERATIONS
FROM php:8.2-apache

WORKDIR /var/www/html

ENV COMPOSER_ALLOW_SUPERUSER=1

# Enable Apache rewrite
RUN a2enmod rewrite

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Copy app and create directories
COPY . .
RUN mkdir -p storage/{app,logs,framework/{cache,sessions,views}} bootstrap/cache public/build

# Install dependencies (no permissions)
RUN composer install --no-dev --ignore-platform-reqs --no-interaction || true

# Laravel setup
RUN cp .env.example .env 2>/dev/null || true
RUN php artisan key:generate --force || true

# Apache config
RUN sed -i 's|/var/www/html|/var/www/html/public|g' /etc/apache2/sites-available/000-default.conf

# Simple entrypoint
RUN echo '#!/bin/bash\ncd /var/www/html\nphp artisan serve --host=0.0.0.0 --port=8000 &\nexec apache2-foreground' > /entrypoint.sh && chmod +x /entrypoint.sh

EXPOSE 80 8000
ENTRYPOINT ["/entrypoint.sh"]
