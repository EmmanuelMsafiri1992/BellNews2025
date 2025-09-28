#!/bin/bash
# Docker entrypoint script for Laravel News App
# Ensures all dependencies and assets are properly set up

set -e

echo "🚀 Starting FBellNews Laravel Application..."

# Ensure we're in the correct directory
cd /var/www/html

# Create required directories if they don't exist
echo "📁 Setting up directory structure..."
mkdir -p storage/logs storage/framework/{cache,sessions,views}
mkdir -p database
mkdir -p public/build

# Set proper permissions
echo "🔐 Setting permissions..."
chown -R www-data:www-data storage/ bootstrap/cache/ database/
chmod -R 775 storage/ bootstrap/cache/ database/

# Create database file if it doesn't exist
if [ ! -f database/database.sqlite ]; then
    echo "🗄️ Creating SQLite database..."
    touch database/database.sqlite
    chown www-data:www-data database/database.sqlite
    chmod 664 database/database.sqlite
fi

# Check if APP_KEY is set, generate if not
echo "🔑 Checking Laravel application key..."
if ! grep -q "^APP_KEY=.*base64:" .env 2>/dev/null; then
    echo "Generating Laravel application key..."
    php artisan key:generate --force
fi

# Run database migrations
echo "🗃️ Running database migrations..."
php artisan migrate --force

# Check if frontend assets exist
if [ ! -f public/build/manifest.json ]; then
    echo "🎨 Frontend assets not found, attempting to build..."
    
    # Check if Node.js is available
    if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
        echo "📦 Node.js available, installing dependencies..."
        
        # Try to install npm dependencies if node_modules doesn't exist
        if [ ! -d node_modules ]; then
            npm install --production=false --no-optional --ignore-scripts 2>/dev/null || {
                echo "⚠️ npm install failed, trying with --legacy-peer-deps"
                npm install --production=false --no-optional --ignore-scripts --legacy-peer-deps 2>/dev/null || {
                    echo "⚠️ npm install still failed, continuing without node_modules"
                }
            }
        fi
        
        # Try to build frontend assets
        echo "🔨 Building frontend assets..."
        if npm run build 2>/dev/null; then
            echo "✅ Frontend build successful"
        elif npm run build:tv 2>/dev/null; then
            echo "✅ TV-specific frontend build successful"
        else
            echo "⚠️ Frontend build failed, using fallback"
            create_fallback_assets
        fi
    else
        echo "⚠️ Node.js not available, using fallback assets"
        create_fallback_assets
    fi
else
    echo "✅ Frontend assets already exist"
fi

# Function to create fallback assets when Node.js build fails
create_fallback_assets() {
    echo "🔧 Creating fallback frontend assets..."
    
    mkdir -p public/build
    
    # Create a basic manifest.json
    cat > public/build/manifest.json << 'EOF'
{
  "resources/css/app.css": {
    "file": "assets/app.css",
    "src": "resources/css/app.css"
  },
  "resources/js/app.js": {
    "file": "assets/app.js",
    "src": "resources/js/app.js"
  }
}
EOF
    
    mkdir -p public/build/assets
    
    # Create basic CSS file
    cat > public/build/assets/app.css << 'EOF'
/* Fallback CSS for FBellNews when Vite build fails */
body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }
.container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; }
h1 { color: #333; text-align: center; }
.loading { text-align: center; padding: 50px; }
.error { color: red; text-align: center; padding: 20px; }
EOF
    
    # Create basic JS file  
    cat > public/build/assets/app.js << 'EOF'
// Fallback JS for FBellNews when Vite build fails
console.log('FBellNews running in fallback mode');

// Basic Vue app fallback
document.addEventListener('DOMContentLoaded', function() {
    const app = document.getElementById('app');
    if (app && !app.innerHTML.trim()) {
        app.innerHTML = '<div class="container"><h1>FBellNews</h1><div class="loading">Loading application...</div></div>';
        
        // Try to load news data via API
        fetch('/api/news')
            .then(response => response.json())
            .then(data => {
                if (data.success && data.data.length > 0) {
                    displayNews(data.data);
                } else {
                    app.innerHTML = '<div class="container"><h1>FBellNews</h1><div class="error">No news data available</div></div>';
                }
            })
            .catch(error => {
                console.error('Error loading news:', error);
                app.innerHTML = '<div class="container"><h1>FBellNews</h1><div class="error">Error loading news data</div></div>';
            });
    }
});

function displayNews(newsData) {
    const app = document.getElementById('app');
    let html = '<div class="container"><h1>FBellNews</h1><div class="news-list">';
    
    newsData.slice(0, 5).forEach(function(item) {
        html += '<div style="border: 1px solid #ddd; margin: 10px 0; padding: 15px; border-radius: 5px;">';
        html += '<h3>' + (item.title || 'No Title') + '</h3>';
        html += '<p>' + (item.description || 'No Description') + '</p>';
        if (item.image_url) {
            html += '<img src="' + item.image_url + '" style="max-width: 100%; height: auto;" onerror="this.style.display=\'none\'">';
        }
        html += '</div>';
    });
    
    html += '</div></div>';
    app.innerHTML = html;
}
EOF
    
    echo "✅ Fallback assets created successfully"
}

# Create storage symlink if it doesn't exist
if [ ! -L public/storage ]; then
    echo "🔗 Creating storage symlink..."
    php artisan storage:link
fi

# Clear caches
echo "🧹 Clearing caches..."
php artisan config:clear
php artisan cache:clear
php artisan route:clear
php artisan view:clear

# Optimize for production
echo "⚡ Optimizing for production..."
php artisan config:cache
php artisan route:cache
php artisan view:cache

echo "✅ Laravel application setup complete!"
echo "🌟 Starting Laravel development server..."

# Start the Laravel server
exec php artisan serve --host=0.0.0.0 --port=8000