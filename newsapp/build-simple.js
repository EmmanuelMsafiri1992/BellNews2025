// Simple build script to create TV-compatible bundle
const fs = require('fs');
const path = require('path');

// Read the Vue components and create a bundled version
function buildApp() {
  const appContent = `
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>WeARE News App</title>
    <script src="https://unpkg.com/vue@3/dist/vue.global.js"></script>
    <script src="https://unpkg.com/vue-i18n@9/dist/vue-i18n.global.js"></script>
    <link href="https://cdn.jsdelivr.net/npm/tailwindcss@2.2.19/dist/tailwind.min.css" rel="stylesheet">
    <style>
        /* TV-compatible styles */
        * {
          margin: 0;
          padding: 0;
          box-sizing: border-box;
        }
        body {
          font-family: 'Inter', 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
          line-height: 1.6;
          background-color: #f9fafb;
        }
        #app {
          width: 100%;
          min-height: 100vh;
        }
        .rtl {
          direction: rtl;
        }
        .animate-spin {
          animation: spin 1s linear infinite;
        }
        @keyframes spin {
          0% { transform: rotate(0deg); }
          100% { transform: rotate(360deg); }
        }
        /* TV-friendly button focus */
        button:focus, .focusable:focus {
          outline: 3px solid #3b82f6;
          outline-offset: 2px;
          box-shadow: 0 0 0 6px rgba(59, 130, 246, 0.3);
        }
        /* Large text for TV screens */
        @media screen and (min-width: 1920px) {
          .container { max-width: 1800px; }
          .text-xl { font-size: 2rem !important; }
          .text-2xl { font-size: 2.5rem !important; }
          .text-3xl { font-size: 3rem !important; }
          .text-base { font-size: 1.25rem !important; }
        }
    </style>
</head>
<body>
    <div id="app">
        <div v-if="loading" class="text-center flex flex-col items-center justify-center h-screen">
            <div class="inline-block animate-spin rounded-full h-32 w-32 border-b-4 border-gray-900"></div>
            <p class="text-gray-500 mt-8 text-xl sm:text-2xl">{{ loading ? 'Loading...' : '' }}</p>
        </div>
        <div v-else class="min-h-screen flex flex-col">
            <!-- Header -->
            <header class="bg-white shadow-sm border-b border-gray-200">
                <div class="container mx-auto px-4 py-6">
                    <h1 class="text-3xl font-bold text-gray-900">WeARE News</h1>
                    <p class="text-gray-600 mt-2">Your TV-compatible news application</p>
                </div>
            </header>

            <!-- Main Content -->
            <main class="flex-1 bg-gray-50 p-4 sm:p-6 lg:p-8 xl:p-12">
                <div class="container mx-auto h-full">
                    <div v-if="newsItems.length > 0" class="grid grid-cols-1 lg:grid-cols-2 gap-8 lg:gap-12 h-full">
                        <!-- Left Column: News Slider -->
                        <div class="bg-white rounded-xl shadow-xl overflow-hidden h-full flex flex-col">
                            <div class="p-6 flex-1">
                                <h2 class="text-2xl font-semibold mb-4">Featured News</h2>
                                <div v-if="currentNews" class="space-y-4">
                                    <div class="aspect-video bg-gray-200 rounded-lg overflow-hidden">
                                        <img v-if="currentNews.image_url && currentNews.image_url !== fallbackImage" 
                                             :src="currentNews.image_url" 
                                             :alt="currentNews.title"
                                             class="w-full h-full object-cover"
                                             @error="handleImageError">
                                        <div v-else class="w-full h-full bg-gray-300 flex items-center justify-center">
                                            <span class="text-gray-500 text-lg">No Image</span>
                                        </div>
                                    </div>
                                    <h3 class="text-xl font-semibold">{{ currentNews.title }}</h3>
                                    <p class="text-gray-600">{{ currentNews.description }}</p>
                                    <div class="flex items-center space-x-4 text-sm text-gray-500">
                                        <span>{{ currentNews.date }}</span>
                                        <span>{{ currentNews.category }}</span>
                                    </div>
                                </div>
                                <div class="flex justify-center space-x-2 mt-6">
                                    <button v-for="(item, index) in newsItems" :key="index"
                                            @click="currentIndex = index"
                                            :class="['w-3 h-3 rounded-full transition-colors', 
                                                    index === currentIndex ? 'bg-blue-500' : 'bg-gray-300']">
                                    </button>
                                </div>
                            </div>
                        </div>

                        <!-- Right Column: News List -->
                        <div class="bg-white rounded-xl shadow-xl overflow-hidden h-full flex flex-col">
                            <div class="p-6">
                                <h2 class="text-2xl font-semibold mb-6">All News</h2>
                                <div class="space-y-4 max-h-96 overflow-y-auto">
                                    <div v-for="(item, index) in newsItems" :key="index"
                                         @click="currentIndex = index"
                                         :class="['p-4 rounded-lg cursor-pointer transition-colors',
                                                 index === currentIndex ? 'bg-blue-50 border-2 border-blue-200' : 'bg-gray-50 hover:bg-gray-100']">
                                        <h4 class="font-semibold text-lg mb-2">{{ item.title }}</h4>
                                        <p class="text-gray-600 text-sm line-clamp-2">{{ item.description }}</p>
                                        <div class="flex items-center space-x-2 mt-2 text-xs text-gray-500">
                                            <span>{{ item.date }}</span>
                                            <span>•</span>
                                            <span>{{ item.category }}</span>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                    <div v-else class="text-center mt-16 flex flex-col items-center justify-center h-full">
                        <div class="text-gray-500 text-2xl sm:text-3xl lg:text-4xl">
                            <svg class="mx-auto h-20 w-20 sm:h-24 sm:w-24 text-gray-400 mb-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 20H5a2 2 0 01-2-2V6a2 2 0 012-2h10a2 2 0 012 2v1m2 13a2 2 0 01-2-2V7m2 13a2 2 0 002-2V9a2 2 0 00-2-2h-2m-4-3H9M7 16h6M7 8h6v4H7V8z" />
                            </svg>
                            <p class="mt-4">{{ error || 'No news available at the moment.' }}</p>
                        </div>
                    </div>
                </div>
            </main>

            <!-- Footer -->
            <footer class="bg-white border-t border-gray-200">
                <div class="container mx-auto px-4 py-6 text-center text-gray-600">
                    <p>&copy; 2024 WeARE News. All rights reserved.</p>
                </div>
            </footer>
        </div>
    </div>

    <script>
        const { createApp } = Vue;
        const { createI18n } = VueI18n;

        // TV-compatible fetch polyfill
        if (!window.fetch) {
            window.fetch = function(url, options) {
                return new Promise(function(resolve, reject) {
                    var xhr = new XMLHttpRequest();
                    xhr.open(options?.method || 'GET', url);
                    xhr.onload = function() {
                        resolve({
                            ok: xhr.status >= 200 && xhr.status < 300,
                            status: xhr.status,
                            json: function() {
                                return Promise.resolve(JSON.parse(xhr.responseText));
                            }
                        });
                    };
                    xhr.onerror = function() {
                        reject(new Error('Network Error'));
                    };
                    if (options?.headers) {
                        Object.keys(options.headers).forEach(function(key) {
                            xhr.setRequestHeader(key, options.headers[key]);
                        });
                    }
                    xhr.send(options?.body);
                });
            };
        }

        const i18n = createI18n({
            locale: 'en',
            fallbackLocale: 'en',
            messages: {
                en: {
                    loading: 'Loading...',
                    noNews: 'No news available',
                    error: 'Error loading news'
                }
            }
        });

        createApp({
            data() {
                return {
                    newsItems: [],
                    currentIndex: 0,
                    loading: true,
                    error: null,
                    fallbackImage: 'https://placehold.co/1280x720/E0E0E0/333333?text=No+Image',
                    autoSlideInterval: null
                };
            },
            computed: {
                currentNews() {
                    return this.newsItems[this.currentIndex] || null;
                }
            },
            methods: {
                async fetchNews() {
                    try {
                        const apiUrl = this.getApiBaseUrl() + '/api/news';
                        console.log('Fetching from:', apiUrl);
                        
                        const response = await fetch(apiUrl, {
                            headers: {
                                'Accept': 'application/json',
                                'Content-Type': 'application/json'
                            }
                        });
                        
                        if (!response.ok) {
                            throw new Error('Failed to fetch news');
                        }
                        
                        const data = await response.json();
                        
                        if (data && data.success && Array.isArray(data.data)) {
                            this.newsItems = data.data;
                        } else if (Array.isArray(data)) {
                            this.newsItems = data;
                        } else {
                            // Create sample news for demonstration
                            this.newsItems = [
                                {
                                    id: 1,
                                    title: 'Welcome to WeARE News',
                                    description: 'Your TV-compatible news application is now running successfully.',
                                    date: new Date().toLocaleDateString(),
                                    category: 'System',
                                    image_url: this.fallbackImage
                                },
                                {
                                    id: 2,
                                    title: 'TV Browser Support',
                                    description: 'This application is optimized for TV browsers and remote control navigation.',
                                    date: new Date().toLocaleDateString(),
                                    category: 'Technology',
                                    image_url: this.fallbackImage
                                },
                                {
                                    id: 3,
                                    title: 'Multi-Language Ready',
                                    description: 'Support for English, Hebrew, and Arabic languages with RTL text direction.',
                                    date: new Date().toLocaleDateString(),
                                    category: 'Features',
                                    image_url: this.fallbackImage
                                }
                            ];
                        }
                        
                        this.error = null;
                    } catch (error) {
                        console.error('Error fetching news:', error);
                        this.error = 'Failed to load news: ' + error.message;
                        this.newsItems = [];
                    } finally {
                        this.loading = false;
                    }
                },
                getApiBaseUrl() {
                    // Dynamic IP detection
                    if (window.IPManager && window.IPManager.getBaseURL) {
                        const dynamicURL = window.IPManager.getBaseURL();
                        if (dynamicURL && dynamicURL !== 'http://localhost:8000') {
                            return dynamicURL;
                        }
                    }
                    
                    // Browser location
                    if (window.location.hostname && window.location.hostname !== 'localhost') {
                        const protocol = window.location.protocol || 'http:';
                        return protocol + '//' + window.location.hostname + ':8000';
                    }
                    
                    return 'http://127.0.0.1:8000';
                },
                handleImageError(event) {
                    event.target.src = this.fallbackImage;
                },
                startAutoSlide() {
                    if (this.newsItems.length > 1) {
                        this.autoSlideInterval = setInterval(() => {
                            this.currentIndex = (this.currentIndex + 1) % this.newsItems.length;
                        }, 5000);
                    }
                },
                stopAutoSlide() {
                    if (this.autoSlideInterval) {
                        clearInterval(this.autoSlideInterval);
                        this.autoSlideInterval = null;
                    }
                }
            },
            watch: {
                currentIndex() {
                    this.stopAutoSlide();
                    setTimeout(() => {
                        this.startAutoSlide();
                    }, 1000);
                }
            },
            async mounted() {
                console.log('WeARE News App starting...');
                await this.fetchNews();
                this.startAutoSlide();
            },
            beforeUnmount() {
                this.stopAutoSlide();
            }
        }).use(i18n).mount('#app');
    </script>
</body>
</html>`;

  // Create public directory if it doesn't exist
  const publicDir = path.join(__dirname, 'public');
  if (!fs.existsSync(publicDir)) {
    fs.mkdirSync(publicDir, { recursive: true });
  }

  // Write the bundled app
  const outputPath = path.join(publicDir, 'index.html');
  fs.writeFileSync(outputPath, appContent);
  
  console.log('✅ Simple build completed!');
  console.log('📁 Output:', outputPath);
}

buildApp();