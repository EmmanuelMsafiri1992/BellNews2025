# EXTREME MEMORY-OPTIMIZED DOCKERFILE FOR NANO PI
# Designed for devices with <512MB RAM
FROM php:8.2-apache

WORKDIR /var/www/html

# Critical: Set extreme memory-friendly environment
ENV DEBIAN_FRONTEND=noninteractive
ENV APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1
ENV COMPOSER_ALLOW_SUPERUSER=1
ENV COMPOSER_MEMORY_LIMIT=128M

# Enable Apache rewrite
RUN a2enmod rewrite

# CRITICAL: Configure APT for EXTREME low-memory (increase cache significantly)
RUN echo 'APT::Cache-Start 25165824;' > /etc/apt/apt.conf.d/01memory && \
    echo 'APT::Cache-Grow 2097152;' >> /etc/apt/apt.conf.d/01memory && \
    echo 'APT::Cache-Limit 50331648;' >> /etc/apt/apt.conf.d/01memory && \
    echo 'APT::Keep-Downloaded-Packages "false";' > /etc/apt/apt.conf.d/99-no-cache && \
    echo 'Dir::Cache::pkgcache "";' > /etc/apt/apt.conf.d/99-no-pkgcache && \
    echo 'Dir::Cache::srcpkgcache "";' > /etc/apt/apt.conf.d/99-no-srcpkgcache && \
    echo 'APT::Install-Recommends "false";' > /etc/apt/apt.conf.d/99-no-recommends && \
    echo 'APT::Install-Suggests "false";' >> /etc/apt/apt.conf.d/99-no-recommends && \
    echo 'APT::Get::List-Cleanup "false";' > /etc/apt/apt.conf.d/99-no-list-cleanup

# Clear existing package lists and update with new settings
RUN rm -rf /var/lib/apt/lists/* && \
    apt-get update

# Install MINIMAL essential packages only
RUN apt-get install -y --no-install-recommends curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN apt-get update && \
    apt-get install -y --no-install-recommends libzip-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN apt-get update && \
    apt-get install -y --no-install-recommends unzip && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN apt-get update && \
    apt-get install -y --no-install-recommends libsqlite3-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN apt-get update && \
    apt-get install -y --no-install-recommends sqlite3 && \
    apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Install ONLY essential PHP extensions (skip graphics to save memory)
RUN docker-php-ext-install zip && rm -rf /tmp/*
RUN docker-php-ext-install pdo && rm -rf /tmp/*
RUN docker-php-ext-install pdo_sqlite && rm -rf /tmp/*

# Install Composer (lightweight version)
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Copy and optimize composer files
COPY composer.json composer.lock* ./

# Install minimal PHP dependencies
RUN composer install --no-dev --no-interaction --no-scripts --prefer-dist --optimize-autoloader --no-progress --quiet || \
    composer install --no-dev --no-interaction --no-scripts --no-progress --quiet

# Copy application files and clean up
COPY . .
RUN rm -rf vendor node_modules .git .github tests phpunit.xml package*.json vite.config.js tailwind.config.js

# Final composer optimization
RUN composer install --no-dev --no-interaction --no-scripts --prefer-dist --optimize-autoloader --no-progress --quiet && \
    composer dump-autoload --optimize --no-dev

# Laravel setup (minimal)
RUN mkdir -p storage/logs storage/framework/{cache,sessions,views} bootstrap/cache database public/build && \
    touch database/database.sqlite && \
    chown -R www-data:www-data storage bootstrap/cache database && \
    chmod -R 775 storage bootstrap/cache database

# Laravel optimizations (skip heavy operations)
RUN php artisan config:clear || true
RUN php artisan key:generate --force || true
RUN php artisan storage:link || true

# Apache config for Laravel
RUN sed -i 's|/var/www/html|/var/www/html/public|g' /etc/apache2/sites-available/000-default.conf

# Create MINIMAL fallback assets (no Node.js at all)
RUN mkdir -p public/build/assets && \
    echo '{"resources/css/app.css":{"file":"assets/app.css"},"resources/js/app.js":{"file":"assets/app.js"}}' > public/build/manifest.json && \
    echo 'body{font-family:Arial,sans-serif;margin:20px;background:#f5f5f5;}.container{max-width:1200px;margin:0 auto;background:white;padding:20px;border-radius:8px;}h1{color:#333;text-align:center;}' > public/build/assets/app.css && \
    echo 'console.log("FBellNews minimal mode");document.addEventListener("DOMContentLoaded",function(){console.log("Laravel app loaded");});' > public/build/assets/app.js

# Copy and fix entrypoint
COPY docker-entrypoint.sh /usr/local/bin/
RUN sed -i 's/\r$//' /usr/local/bin/docker-entrypoint.sh && \
    chmod +x /usr/local/bin/docker-entrypoint.sh

# Extreme cleanup
RUN apt-get autoremove -y && \
    apt-get autoclean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/cache/apt/* && \
    find /var/log -type f -delete 2>/dev/null || true && \
    find /usr/share/doc -type f -delete 2>/dev/null || true && \
    find /usr/share/man -type f -delete 2>/dev/null || true

EXPOSE 80
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["apache2-foreground"]