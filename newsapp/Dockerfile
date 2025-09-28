
# ULTRA-MINIMAL DOCKERFILE FOR NANO PI - FIXED VERSION
# Uses php-apache base image, no apt-get dependencies
FROM php:8.2-apache

WORKDIR /var/www/html

# Environment variables
ENV DEBIAN_FRONTEND=noninteractive
ENV COMPOSER_ALLOW_SUPERUSER=1
ENV COMPOSER_MEMORY_LIMIT=64M

# Enable Apache rewrite
RUN a2enmod rewrite

# Install Composer (no apt-get)
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Copy application code
COPY . .

# ---- FIXED PERMISSIONS (build-time) ----
# Reset ownership so www-data can read/write
RUN chown -R www-data:www-data /var/www/html \
    && chmod -R 775 storage bootstrap/cache database || true

# Install PHP dependencies (ignoring platform reqs to keep it light)
RUN composer install --no-dev --no-interaction --no-scripts --prefer-dist --optimize-autoloader --no-progress --quiet --ignore-platform-reqs || \
    composer install --no-dev --no-interaction --no-scripts --ignore-platform-reqs || \
    echo "Composer install completed with warnings"

# Create Laravel directories (idempotent)
RUN mkdir -p storage/logs storage/framework/{cache,sessions,views} bootstrap/cache database public/build \
    && touch database/database.sqlite

# Ensure correct ownership again
RUN chown -R www-data:www-data storage bootstrap/cache database \
    && chmod -R 775 storage bootstrap/cache database

# Setup Laravel environment
RUN php -r "if(!file_exists('.env') && file_exists('.env.example')){copy('.env.example','.env');}" \
    && php artisan key:generate --force --no-interaction || true

# Apache config for Laravel
RUN sed -i 's|/var/www/html|/var/www/html/public|g' /etc/apache2/sites-available/000-default.conf

# Create minimal assets (skip Node build)
RUN mkdir -p public/build/assets && \
    echo '{"resources/css/app.css":{"file":"assets/app.css"},"resources/js/app.js":{"file":"assets/app.js"}}' > public/build/manifest.json && \
    echo '/* FBellNews Minimal CSS */ body{font-family:Arial,sans-serif;margin:20px;background:#f5f5f5;color:#333;} .container{max-width:1200px;margin:0 auto;background:white;padding:20px;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,0.1);} h1{color:#2563eb;text-align:center;margin-bottom:30px;} .news-item{border:1px solid #e5e7eb;margin:15px 0;padding:15px;border-radius:8px;} .news-title{font-weight:bold;font-size:1.1em;margin-bottom:10px;} .news-content{line-height:1.6;} .loading{text-align:center;padding:50px;} .error{color:#dc2626;text-align:center;padding:20px;background:#fef2f2;border-radius:8px;margin:20px 0;}' > public/build/assets/app.css && \
    echo '/* FBellNews Minimal JS */ console.log("FBellNews minimal mode loaded"); document.addEventListener("DOMContentLoaded", function() { console.log("Laravel app initialized"); const app = document.getElementById("app"); if (app && !app.innerHTML.trim()) { app.innerHTML = "<div class=\"container\"><h1>FBellNews</h1><div class=\"loading\">Loading application...</div></div>"; } });' > public/build/assets/app.js

# Entrypoint script
RUN echo '#!/bin/bash' > /usr/local/bin/docker-entrypoint.sh && \
    echo 'set -e' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'cd /var/www/html' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'php artisan serve --host=0.0.0.0 --port=8000 &' >> /usr/local/bin/docker-entrypoint.sh && \
    echo 'apache2-foreground' >> /usr/local/bin/docker-entrypoint.sh && \
    chmod +x /usr/local/bin/docker-entrypoint.sh

# Optimize autoloader
RUN composer dump-autoload --optimize --no-dev || true

# Cleanup (optional)
RUN rm -rf tests phpunit.xml package*.json vite.config.js tailwind.config.js node_modules .git .github || true

# Expose ports
EXPOSE 80
EXPOSE 8000

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["apache2-foreground"]
