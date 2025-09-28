# Ultra-minimal Laravel Dockerfile for ARM NanoPi
FROM php:8.2-apache

WORKDIR /var/www/html

ENV DEBIAN_FRONTEND=noninteractive
ENV COMPOSER_ALLOW_SUPERUSER=1
ENV COMPOSER_MEMORY_LIMIT=64M

# Enable Apache rewrite
RUN a2enmod rewrite

# Install Composer (no apt-get)
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Copy app files
COPY . .

# Install dependencies (skip dev + platform checks)
RUN composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader --ignore-platform-reqs || true

# Laravel dirs
RUN mkdir -p storage/logs storage/framework/{cache,sessions,views} bootstrap/cache database public/build \
 && touch database/database.sqlite \
 && chown -R www-data:www-data storage bootstrap/cache database \
 && chmod -R 775 storage bootstrap/cache database

# Ensure .env exists + app key
RUN php -r "if(!file_exists('.env') && file_exists('.env.example')) copy('.env.example','.env');" \
 && php artisan key:generate --force --no-interaction || true

# Point Apache to /public
RUN sed -i 's|/var/www/html|/var/www/html/public|g' /etc/apache2/sites-available/000-default.conf

# Minimal assets
RUN mkdir -p public/build/assets \
 && echo '{"resources/css/app.css":{"file":"assets/app.css"},"resources/js/app.js":{"file":"assets/app.js"}}' > public/build/manifest.json \
 && echo 'body{font-family:Arial;}' > public/build/assets/app.css \
 && echo 'console.log("FBellNews minimal mode loaded");' > public/build/assets/app.js

# Optimize autoload
RUN composer dump-autoload --optimize --no-dev || true

EXPOSE 80
CMD ["apache2-foreground"]
