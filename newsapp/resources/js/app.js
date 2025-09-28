// Import polyfills first for TV browser compatibility
import './tv-polyfills.js';
// Import dynamic IP detection system
import './ip-detection.js';
// Import network recovery system
import './network-recovery.js';

import { createApp } from 'vue';
import { createI18n } from 'vue-i18n';
import App from './App.vue';
import SliderComponent from './components/SliderComponent.vue';
import NewsComponent from './components/NewsComponent.vue';
import HeaderComponent from './components/HeaderComponent.vue';
import FooterComponent from './components/FooterComponent.vue';

// Dynamically import translation files
import en from '../lang/en.json';
import he from '../lang/he.json';
import ar from '../lang/ar.json';

// TV-safe locale detection
function getSafeLocale() {
  var defaultLocale = 'en';
  try {
    var stored = window.safeLocalStorage ? window.safeLocalStorage.getItem('locale') : null;
    return stored || defaultLocale;
  } catch (e) {
    console.warn('Could not access localStorage for locale:', e);
    return defaultLocale;
  }
}

const i18n = createI18n({
  locale: getSafeLocale(),
  fallbackLocale: 'en',
  messages: {
    en: en,
    he: he,
    ar: ar
  }
});

// TV browser error handling
window.addEventListener('error', function(e) {
  console.error('Global error caught:', e.error);
  // Don't let errors crash the app on TV browsers
  return true;
});

window.addEventListener('unhandledrejection', function(e) {
  console.error('Unhandled promise rejection:', e.reason);
  // Prevent unhandled promise rejections from crashing TV browsers
  e.preventDefault();
});

const app = createApp(App);

// TV-safe component registration
try {
  app.component('slider-component', SliderComponent);
  app.component('news-component', NewsComponent);
  app.component('header-component', HeaderComponent);
  app.component('footer-component', FooterComponent);
  app.use(i18n);
  
  // Initialize TV remote helper after app is mounted
  app.mount('#app');
  
  // Initialize TV remote navigation after DOM is ready
  if (window.TVRemoteHelper) {
    setTimeout(function() {
      window.TVRemoteHelper.init();
    }, 1000);
  }
  
  console.log('NewsApp initialized successfully for TV browsers');
} catch (error) {
  console.error('Failed to initialize app:', error);
  // Show fallback message for TV users
  document.getElementById('app').innerHTML = '<div style="text-align:center;padding:50px;font-size:24px;">Loading News App...</div>';
}
