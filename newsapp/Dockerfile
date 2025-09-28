FROM php:8.2-apache

WORKDIR /var/www/html

# Install system dependencies + PHP extensions first
RUN apt-get update && \
    apt-get install -y \
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
    && rm -rf /var/lib/apt/lists/*

# Install Node.js using NodeSource repository for better ARM compatibility
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/* \
    || echo "Node.js installation failed, will use fallback method"

# Install Composer first
RUN curl -sS https://getcomposer.org/installer \
      | php -- --install-dir=/usr/local/bin --filename=composer

# Copy composer files for dependency installation
COPY composer.json composer.lock* /var/www/html/

# Install PHP dependencies
RUN composer install --no-dev --no-interaction --prefer-dist --optimize-autoloader --no-scripts

# Copy application files
COPY . /var/www/html

# Run post-install scripts
RUN composer dump-autoload --optimize

# Try to install Node.js dependencies and build frontend assets (optional)
RUN if command -v npm >/dev/null 2>&1; then \
        echo "Installing npm dependencies..." && \
        npm install --production=false --no-optional --ignore-scripts 2>/dev/null || echo "npm install failed, will use runtime fallback" && \
        npm run build 2>/dev/null || npm run build:tv 2>/dev/null || echo "Frontend build failed, will use runtime fallback" && \
        npm cache clean --force 2>/dev/null || true; \
    else \
        echo "Node.js not available, will use runtime fallback"; \
    fi

# Laravel setup - create required directories and set permissions
RUN mkdir -p storage/logs storage/framework/{cache,sessions,views} \
    && mkdir -p database \
    && touch database/database.sqlite \
    && php artisan storage:link \
    && chown -R www-data:www-data storage/ bootstrap/cache/ database/ \
    && chmod -R 775 storage/ bootstrap/cache/ database/

# Generate Laravel application key if not set
RUN php artisan key:generate || echo "App key already exists"

# Copy and set up entrypoint script
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

EXPOSE 8000
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
