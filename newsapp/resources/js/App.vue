<template>
  <div id="app" class="min-h-screen flex flex-col" :class="{ 'rtl': $i18n.locale === 'he' || $i18n.locale === 'ar' }">
    <!-- Header Component -->
    <header-component />

    <!-- Main Content Area -->
    <main class="flex-1 bg-gray-50 p-4 sm:p-6 lg:p-8 xl:p-12">
      <div class="container mx-auto h-full">
        <div v-if="loading" class="text-center flex flex-col items-center justify-center h-full min-h-[50vh]">
          <div class="inline-block animate-spin rounded-full h-32 w-32 border-b-4 border-gray-900"></div>
          <p class="text-gray-500 mt-8 text-xl sm:text-2xl">{{ $t('loading') }}</p>
        </div>
        <div v-else-if="processedNewsItems.length > 0" class="grid grid-cols-1 lg:grid-cols-2 gap-8 lg:gap-12 h-full">
          <!-- Left Column: Enhanced News Slider -->
          <div class="bg-white rounded-xl shadow-xl overflow-hidden h-full flex flex-col hover:shadow-2xl transition-all duration-300 ease-in-out transform hover:-translate-y-1">
            <slider-component
              :news-items="processedNewsItems"
              :current-index="currentIndex"
              @slide-change="handleSlideChange"
              :auto-slide="true"
              @pause="pauseSlider"
              @resume="resumeSlider"
            />
          </div>
          <!-- Right Column: News List -->
          <div class="bg-white rounded-xl shadow-xl overflow-hidden h-full flex flex-col hover:shadow-2xl transition-all duration-300 ease-in-out transform hover:-translate-y-1">
            <news-component
              :news-items="processedNewsItems"
              :current-index="currentIndex"
              @news-select="handleNewsSelect"
            />
          </div>
        </div>
        <div v-else class="text-center mt-16 flex flex-col items-center justify-center h-full min-h-[50vh]">
          <div class="text-gray-500 text-2xl sm:text-3xl lg:text-4xl">
            <svg class="mx-auto h-20 w-20 sm:h-24 sm:w-24 text-gray-400 mb-4" fill="none" viewBox="0 0 24 24" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 20H5a2 2 0 01-2-2V6a2 2 0 012-2h10a2 2 0 012 2v1m2 13a2 2 0 01-2-2V7m2 13a2 2 0 002-2V9a2 2 0 00-2-2h-2m-4-3H9M7 16h6M7 8h6v4H7V8z" />
            </svg>
            <p class="mt-4">{{ noNewsMessage }}</p>
          </div>
        </div>
      </div>
    </main>

    <!-- Footer Component -->
    <footer-component />
  </div>
</template>

<script>
import SliderComponent from './components/SliderComponent.vue';
import NewsComponent from './components/NewsComponent.vue';
import HeaderComponent from './components/HeaderComponent.vue';
import FooterComponent from './components/FooterComponent.vue';

export default {
  name: 'App',
  components: {
    SliderComponent,
    NewsComponent,
    HeaderComponent,
    FooterComponent,
  },
  data() {
    return {
      currentIndex: 0,
      newsItems: [],
      loading: true,
      autoSlideTimeout: null,
      refreshInterval: null,
      fallbackImage: 'https://placehold.co/1280x720/E0E0E0/333333?text=No+Image', // Enhanced placeholder
      error: null,
      retryCount: 0,
      maxRetries: 3,
      debouncedSlideChange: null,
      slideInterval: 5000, // Default global value in milliseconds
    };
  },
  computed: {
    processedNewsItems() {
      if (!Array.isArray(this.newsItems)) {
        return [];
      }

      return this.newsItems.map((item, index) => {
        if (!item || typeof item !== 'object') {
          console.warn(`Invalid news item at index ${index}:`, item);
          return this.createFallbackNewsItem(index);
        }

        const processedImages = this.processImageArray(item.images, item);
        const primaryImage = processedImages.length > 0 ? processedImages[0] : null;

        return {
          id: item.id || `news-${index}`,
          title: item.title || item.headline || this.$t('No Title'),
          description: item.description || item.summary || item.content || this.$t('No description available'),
          full_description: item.full_description || item.description || item.summary || item.content || this.$t('No description available'),
          date: item.date || item.published_at || item.created_at || new Date().toLocaleDateString(),
          category: item.category || item.type || this.$t('News'),
          location: item.location || '',
          time: item.time || item.event_time || '',
          organizer: item.organizer || item.author || '',

          images: processedImages,
          image_url: primaryImage ? primaryImage.url : this.fallbackImage,
          slide_duration: primaryImage ? primaryImage.duration : this.slideInterval,

          hasValidImage: !!primaryImage
        };
      });
    },
    noNewsMessage() {
      if (this.error) {
        return this.$t('errorLoadingNews') || 'Error loading news. Please try again later.';
      }
      return this.$t('noNews') || 'No news available at the moment.';
    }
  },
  methods: {
    processImageArray(images, item) {
        if (!Array.isArray(images) || images.length === 0) {
            const primaryImageUrl = this.processImageUrl(item.image_url || item.image);
            if (primaryImageUrl !== this.fallbackImage) {
                return [{ url: primaryImageUrl, duration: this.slideInterval }];
            }
            return [];
        }

        return images.map(imgObj => {
            if (typeof imgObj === 'object' && imgObj !== null && imgObj.url) {
                return {
                    url: this.processImageUrl(imgObj.url),
                    duration: parseInt(imgObj.slide_duration, 10) || this.slideInterval
                };
            }
            return null;
        }).filter(Boolean);
    },
    fetchSettings: function() {
        var self = this;
        return new Promise(function(resolve, reject) {
            try {
                var apiBaseUrl = self.getApiBaseUrl();
                
                // Use TV-compatible fetch
                window.fetch(apiBaseUrl + '/api/settings', {
                    method: 'GET',
                    headers: {
                        'Accept': 'application/json',
                        'Content-Type': 'application/json'
                    },
                    timeout: 8000
                }).then(function(response) {
                    if (!response.ok) {
                        throw new Error('Failed to fetch settings');
                    }
                    return response.json();
                }).then(function(settings) {
                    if (settings && settings.slider_display_time) {
                        self.slideInterval = parseInt(settings.slider_display_time, 10) * 1000;
                    }
                    resolve(settings);
                }).catch(function(error) {
                    console.error('Could not fetch settings:', error);
                    resolve({}); // Don't fail completely, just use defaults
                });
            } catch (error) {
                console.error('Settings fetch error:', error);
                resolve({}); // Don't fail completely
            }
        });
    },
    createFallbackNewsItem(index) {
      return {
        id: `fallback-${index}`,
        title: this.$t('News Item'),
        description: this.$t('Loading...'),
        full_description: this.$t('Loading...'),
        date: new Date().toLocaleDateString(),
        category: this.$t('News'),
        location: '',
        time: '',
        organizer: '',
        image_url: this.fallbackImage,
        images: [{ url: this.fallbackImage, duration: this.slideInterval }],
        slide_duration: this.slideInterval,
        hasValidImage: false
      };
    },
    handleSlideChange(newIndex) {
      if (this.debouncedSlideChange) {
        clearTimeout(this.debouncedSlideChange);
      }
      this.debouncedSlideChange = setTimeout(() => {
        if (newIndex >= 0 && newIndex < this.processedNewsItems.length) {
          this.currentIndex = newIndex;
        }
      }, 50);
    },
    handleNewsSelect(newsIndex) {
      if (newsIndex >= 0 && newsIndex < this.processedNewsItems.length) {
        this.currentIndex = newsIndex;
      }
    },
    pauseSlider() {
      if (this.autoSlideTimeout) {
        clearTimeout(this.autoSlideTimeout);
        this.autoSlideTimeout = null;
      }
    },
    resumeSlider() {
      if (!this.autoSlideTimeout && this.processedNewsItems.length > 1) {
        this.startAutoSlide();
      }
    },
    startAutoSlide() {
      this.pauseSlider();
      if (this.processedNewsItems.length > 1) {
        const currentItem = this.processedNewsItems[this.currentIndex];
        const duration = currentItem ? currentItem.slide_duration : this.slideInterval;

        this.autoSlideTimeout = setTimeout(() => {
          this.currentIndex = (this.currentIndex + 1) % this.processedNewsItems.length;
          this.startAutoSlide();
        }, duration);
      }
    },
    processImageUrl(imageUrl) {
      if (!imageUrl || typeof imageUrl !== 'string') return this.fallbackImage;
      imageUrl = imageUrl.trim();
      if (imageUrl.startsWith('/')) return imageUrl;
      if (imageUrl.startsWith('//')) return `https:${imageUrl}`;
      if (imageUrl.startsWith('http')) return imageUrl;
      // Assume local assets are in /assets/images/ or similar.
      // Adjust this path based on your Laravel public asset structure if different.
      return `/assets/images/${imageUrl}`;
    },
    isValidImageUrl(imageUrl) {
      if (!imageUrl || typeof imageUrl !== 'string') return false;
      const imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.svg'];
      const lowercaseUrl = imageUrl.toLowerCase();
      return imageExtensions.some(ext => lowercaseUrl.includes(ext)) || imageUrl.startsWith('http') || imageUrl.startsWith('/');
    },
    preloadImages() {
      if (!this.processedNewsItems.length) return;
      this.processedNewsItems.forEach((item) => {
        if (item.image_url && item.image_url !== this.fallbackImage) {
          const img = new Image();
          img.src = item.image_url;
        }
      });
    },
    fetchNews: function() {
      var self = this;
      var maxRetries = 3;
      var baseDelay = 1000;
      var apiBaseUrl = this.getApiBaseUrl();
                      
      return new Promise(function(resolve, reject) {
        function attemptFetch(attempt) {
          try {
            // TV-compatible fetch with simplified controller
            var timeoutId = setTimeout(function() {
              console.warn('Request timeout after 10 seconds');
            }, 10000);
            
            window.fetch(apiBaseUrl + '/api/news', {
              method: 'GET',
              headers: { 
                'Accept': 'application/json', 
                'Content-Type': 'application/json', 
                'Cache-Control': 'no-cache', 
                'Pragma': 'no-cache' 
              },
              timeout: 10000
            }).then(function(response) {
              clearTimeout(timeoutId);
              if (!response.ok) {
                throw new Error('HTTP ' + response.status + ': ' + response.statusText);
              }
              return response.json();
            }).then(function(data) {
              // Handle different response formats
              if (data && data.success && Array.isArray(data.data)) {
                self.newsItems = data.data;
              } else if (Array.isArray(data)) {
                self.newsItems = data;
              } else {
                throw new Error('Invalid data format');
              }
              
              self.error = null;
              self.retryCount = 0;
              
              // TV-safe nextTick replacement
              setTimeout(function() {
                self.preloadImages();
              }, 10);
              
              resolve(data);
            }).catch(function(error) {
              console.error('Fetch attempt ' + (attempt + 1) + ' failed:', error.message);
              
              if (attempt >= maxRetries - 1) {
                self.error = 'Failed to load news after ' + maxRetries + ' attempts';
                self.newsItems = [];
                resolve([]); // Don't reject, just resolve with empty data
                return;
              }
              
              // Exponential backoff with TV-safe setTimeout
              var delay = baseDelay * Math.pow(2, attempt);
              setTimeout(function() {
                attemptFetch(attempt + 1);
              }, delay);
            });
          } catch (error) {
            console.error('Fetch setup error:', error);
            if (attempt >= maxRetries - 1) {
              self.error = 'Failed to setup request';
              self.newsItems = [];
              resolve([]);
            } else {
              setTimeout(function() {
                attemptFetch(attempt + 1);
              }, baseDelay);
            }
          }
        }
        
        attemptFetch(0);
      });
    },
    getApiBaseUrl: function() {
      // Priority order for getting API base URL:
      // 1. Dynamic IP Manager (if available)
      // 2. Environment variables
      // 3. Current browser location
      // 4. Fallback to localhost
      
      if (window.IPManager && window.IPManager.getBaseURL) {
        var dynamicURL = window.IPManager.getBaseURL();
        if (dynamicURL && dynamicURL !== 'http://localhost:8000') {
          return dynamicURL;
        }
      }
      
      // Try environment variables
      var envURL = window.ENV_API_BASE_URL;
      if (envURL) {
        return envURL;
      }
      
      // Try current browser location
      if (window.location.hostname && window.location.hostname !== 'localhost') {
        var protocol = window.location.protocol || 'http:';
        return protocol + '//' + window.location.hostname + ':8000';
      }
      
      // Final fallback
      return 'http://127.0.0.1:8000';
    },
    handleIPChange: function(newHost, newPort, newBaseURL) {
      console.log('IP changed to:', newBaseURL);
      
      // Update any cached URLs or configurations
      this.error = null;
      
      // Refresh data with new IP
      this.fetchNews();
      this.fetchSettings();
      
      // Show user notification if needed
      this.$nextTick(function() {
        console.log('Reconnected to server at:', newBaseURL);
      });
    },
    handleNetworkRecovery: function(event, reason) {
      var self = this;
      
      switch(event) {
        case 'start':
          console.log('Network recovery started:', reason);
          this.error = 'Connection lost, attempting to reconnect...';
          break;
          
        case 'success':
          console.log('Network recovery successful');
          this.error = null;
          // Refresh data after successful recovery
          setTimeout(function() {
            self.fetchNews();
            self.fetchSettings();
          }, 1000);
          break;
          
        case 'failed':
          console.log('Network recovery failed');
          this.error = 'Unable to connect to server. Please check your network connection.';
          break;
      }
    },
  },
  mounted: function() {
    var self = this;
    console.log('App mounted, starting data fetch...');
    this.loading = true;
    
    // Set up IP change listener
    if (window.IPManager) {
      window.IPManager.onIPChange(function(host, port, baseURL) {
        self.handleIPChange(host, port, baseURL);
      });
    }
    
    // Set up network recovery listener
    if (window.NetworkRecovery) {
      window.NetworkRecovery.onRecovery(function(event, reason) {
        self.handleNetworkRecovery(event, reason);
      });
    }
    
    // Wait for IP detection to complete before fetching data
    var initializeApp = function() {
      Promise.all([self.fetchSettings(), self.fetchNews()]).then(function() {
        if (self.processedNewsItems.length > 1) {
          self.startAutoSlide();
        }
      }).catch(function(error) {
        console.error('Error during app initialization:', error);
      }).finally(function() {
        self.loading = false;
      });
    };
    
    // Wait for IP Manager or start immediately
    if (window.IPManager && !window.IPManager.currentIP) {
      setTimeout(function() {
        initializeApp();
      }, 2000); // Wait 2 seconds for IP detection
    } else {
      initializeApp();
    }
    
    // Set up refresh interval for news and settings with TV-safe interval
    this.refreshInterval = setInterval(function() {
      self.fetchNews();
      self.fetchSettings();
    }, 5 * 60 * 1000); // Refresh every 5 minutes
  },
  beforeUnmount() {
    this.pauseSlider(); // Clear auto-slide timeout
    if (this.refreshInterval) clearInterval(this.refreshInterval); // Clear refresh interval
    if (this.debouncedSlideChange) clearTimeout(this.debouncedSlideChange); // Clear debounce timeout
  },
  watch: {
    // Restart auto-slide whenever currentIndex changes (e.g., manual navigation)
    currentIndex() {
        this.startAutoSlide();
    }
  },
  errorCaptured(err, instance, info) {
    console.error('Vue error captured:', err, instance, info);
    // Return false to prevent the error from propagating further up the component tree
    return false;
  }
};
</script>

<style>
/* Base styles for the entire application */
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
/* RTL support */
.rtl {
  direction: rtl;
}
/* Enhanced shadow for hover effect */
.hover\:shadow-xl:hover {
  box-shadow: 0 20px 25px -5px rgba(0, 0, 0, 0.1), 0 10px 10px -5px rgba(0, 0, 0, 0.04);
  transition: box-shadow 0.3s ease;
}
/* Spin animation for loading indicators */
@keyframes spin {
  0% { transform: rotate(0deg); }
  100% { transform: rotate(360deg); }
}
.animate-spin {
  animation: spin 1s linear infinite;
}
/* Image loading placeholder animation */
.news-image {
  transition: opacity 0.3s ease;
}
.news-image.loading {
  opacity: 0.7;
  background: linear-gradient(90deg, #f0f0f0 25%, #e0e0e0 50%, #f0f0f0 75%);
  background-size: 200% 100%;
  animation: loading 1.5s infinite;
}
@keyframes loading {
  0% { background-position: 200% 0; }
  100% { background-position: -200% 0; }
}

/* Responsive adjustments for various screen sizes */

/* Small screens (mobile) */
@media screen and (max-width: 640px) {
  .p-4 { padding: 1rem; }
  .text-xl { font-size: 1.25rem !important; }
  .text-2xl { font-size: 1.5rem !important; }
  .text-3xl { font-size: 1.875rem !important; }
}

/* Medium screens (tablet) */
@media screen and (min-width: 641px) and (max-width: 1024px) {
  .p-6 { padding: 1.5rem; }
  .text-xl { font-size: 1.5rem !important; }
  .text-2xl { font-size: 1.875rem !important; }
  .text-3xl { font-size: 2.25rem !important; }
}

/* Large screens (desktop/HD TV) */
@media screen and (min-width: 1025px) and (max-width: 1919px) {
  .container { max-width: 1280px; } /* Standard desktop container */
  .p-8 { padding: 2rem; }
  .text-xl { font-size: 1.75rem !important; }
  .text-2xl { font-size: 2rem !important; }
  .text-3xl { font-size: 2.5rem !important; }
  .text-base { font-size: 1.125rem !important; }
  .text-lg { font-size: 1.25rem !important; }
  .text-sm { font-size: 0.9rem !important; }
}

/* Extra Large screens (4K TV optimizations) */
@media screen and (min-width: 1920px) {
  .container { max-width: 1800px; } /* Wider container for 4K */
  .p-4 { padding: 2rem; }
  .p-6 { padding: 3rem; }
  .p-8 { padding: 4rem; }
  .p-12 { padding: 6rem; }

  .text-xl { font-size: 2rem !important; }
  .text-2xl { font-size: 2.5rem !important; }
  .text-3xl { font-size: 3rem !important; }
  .text-4xl { font-size: 3.5rem !important; } /* Added for larger headings */
  .text-sm { font-size: 1.125rem !important; }
  .text-base { font-size: 1.25rem !important; }
  .text-lg { font-size: 1.5rem !important; }

  /* Enhanced button sizes for TV remotes */
  button { min-width: 48px; min-height: 48px; }
  /* Focus states for better navigation with TV remotes */
  button:focus, .focusable:focus {
    outline: 3px solid #3b82f6; /* Blue outline */
    outline-offset: 2px;
    box-shadow: 0 0 0 6px rgba(59, 130, 246, 0.3); /* Soft blue glow */
  }

  /* Improved contrast and readability for TV screens */
  .text-gray-500 { color: #374151; }
  .bg-gray-50 { background-color: #f9fafb; }
  .text-white { text-shadow: 2px 2px 4px rgba(0, 0, 0, 0.9); font-weight: 500; }
  .bg-black { background-color: rgba(0, 0, 0, 0.85); }
  .bg-white { background-color: rgba(255, 255, 255, 0.95); }
}

/* High Contrast mode adjustments (for accessibility) */
@media (prefers-contrast: high) {
  .text-white { color: #ffffff; text-shadow: 2px 2px 0px #000000; }
  .bg-black { background-color: #000000; }
  .bg-white { background-color: #ffffff; }
  /* Add more specific high-contrast adjustments as needed */
}
</style>
