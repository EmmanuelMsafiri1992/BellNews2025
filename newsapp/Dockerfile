# ULTRA-LIGHTWEIGHT DOCKERFILE FOR NANO PI - MEMORY OPTIMIZED
FROM php:8.2-apache

WORKDIR /var/www/html

# Critical: Set memory-friendly environment
ENV DEBIAN_FRONTEND=noninteractive
ENV APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1
ENV COMPOSER_ALLOW_SUPERUSER=1
ENV COMPOSER_MEMORY_LIMIT=-1

# Enable Apache rewrite
RUN a2enmod rewrite

# CRITICAL: Configure APT for low-memory systems
RUN echo 'APT::Cache-Start 4194304;' > /etc/apt/apt.conf.d/01memory && \
    echo 'APT::Cache-Grow 1048576;' >> /etc/apt/apt.conf.d/01memory && \
    echo 'APT::Cache-Limit 8388608;' >> /etc/apt/apt.conf.d/01memory && \
    echo 'APT::Keep-Downloaded-Packages "false";' > /etc/apt/apt.conf.d/99-no-cache && \
    echo 'Dir::Cache::pkgcache "";' > /etc/apt/apt.conf.d/99-no-pkgcache && \
    echo 'Dir::Cache::srcpkgcache "";' > /etc/apt/apt.conf.d/99-no-srcpkgcache && \
    echo 'APT::Install-Recommends "false";' > /etc/apt/apt.conf.d/99-no-recommends && \
    echo 'APT::Install-Suggests "false";' >> /etc/apt/apt.conf.d/99-no-recommends

# Update with minimal memory usage
RUN apt-get update

# Install ONLY essential packages one by one to avoid memory issues
RUN apt-get install -y --no-install-recommends ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
    apt-get install -y --no-install-recommends curl && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
    apt-get install -y --no-install-recommends wget && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
    apt-get install -y --no-install-recommends libzip-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
    apt-get install -y --no-install-recommends unzip && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
    apt-get install -y --no-install-recommends git && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
    apt-get install -y --no-install-recommends libpng-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
    apt-get install -y --no-install-recommends libjpeg-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
    apt-get install -y --no-install-recommends libfreetype6-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
    apt-get install -y --no-install-recommends libsqlite3-dev && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
    apt-get install -y --no-install-recommends sqlite3 && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Install PHP extensions one by one with memory cleanup
RUN docker-php-ext-configure gd --with-freetype --with-jpeg && \
    rm -rf /tmp/*

RUN docker-php-ext-install zip && \
    rm -rf /tmp/*

RUN docker-php-ext-install pdo && \
    rm -rf /tmp/*

RUN docker-php-ext-install pdo_mysql && \
    rm -rf /tmp/*

RUN docker-php-ext-install pdo_sqlite && \
    rm -rf /tmp/*

RUN docker-php-ext-install gd && \
    rm -rf /tmp/*

# Install Composer with memory limit
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Copy composer files ONLY
COPY composer.json composer.lock* ./

# Install PHP dependencies with memory optimization
RUN composer install --no-dev --no-interaction --no-scripts --prefer-dist --optimize-autoloader || \
    composer install --no-dev --no-interaction --no-scripts

# Copy application files
COPY . .

# Remove unnecessary files to free memory
RUN rm -rf vendor node_modules .git .github tests phpunit.xml

# Final composer install
RUN composer install --no-dev --no-interaction --no-scripts --prefer-dist --optimize-autoloader && \
    composer dump-autoload --optimize

# Laravel optimizations without building frontend (saves memory)
RUN php artisan config:clear || true && \
    php artisan route:clear || true && \
    php artisan view:clear || true

# Create Laravel directories
RUN mkdir -p storage/logs storage/framework/{cache,sessions,views} bootstrap/cache database public/build && \
    touch database/database.sqlite && \
    chown -R www-data:www-data storage bootstrap/cache database public && \
    chmod -R 775 storage bootstrap/cache database && \
    chmod 664 database/database.sqlite

# Generate app key
RUN php artisan key:generate --force || true

# Storage link
RUN php artisan storage:link || true

# Apache config for Laravel
RUN sed -i 's|/var/www/html|/var/www/html/public|g' /etc/apache2/sites-available/000-default.conf && \
    sed -i 's|/var/www/|/var/www/html/public|g' /etc/apache2/apache2.conf

# Create simple fallback assets (no Node.js to save memory)
RUN mkdir -p public/build/assets && \
    echo '{}' > public/build/manifest.json && \
    echo 'body{font-family:Arial,sans-serif;margin:0;padding:20px;background:#f5f5f5;}' > public/build/assets/app.css && \
    echo 'console.log("FBellNews loaded");' > public/build/assets/app.js

# Copy entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
RUN sed -i 's/\r$//' /usr/local/bin/docker-entrypoint.sh && \
    chmod +x /usr/local/bin/docker-entrypoint.sh

# Final cleanup
RUN apt-get autoremove -y && \
    apt-get autoclean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
    find /var/cache -type f -delete 2>/dev/null || true

EXPOSE 80
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["apache2-foreground"]