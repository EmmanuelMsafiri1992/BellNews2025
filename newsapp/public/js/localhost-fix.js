// Aggressive localhost override to stop network scanning
(function() {
    'use strict';
    
    // console.log('Setting up localhost override...');
    
    // Block all network requests except localhost
    const isNetworkIP = (url) => {
        if (typeof url !== 'string') return false;
        return url.match(/^https?:\/\/(?:192\.168\.|10\.|172\.(?:1[6-9]|2[0-9]|3[01])\.|169\.254\.)/);
    };
    
    // Override fetch globally to redirect network IPs to localhost
    const originalFetch = window.fetch;
    window.fetch = function(url, options) {
        if (isNetworkIP(url)) {
            // console.log('Fetch request intercepted:', url, '-> redirecting to localhost:8000');
            url = url.replace(/^https?:\/\/[^\/]+/, 'http://localhost:8000');
        }
        return originalFetch.call(this, url, options);
    };

    // Override XMLHttpRequest for Axios
    const originalXHROpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url, async, user, password) {
        if (isNetworkIP(url)) {
            // console.log('XHR request intercepted:', url, '-> redirecting to localhost:8000');
            url = url.replace(/^https?:\/\/[^\/]+/, 'http://localhost:8000');
        }
        return originalXHROpen.call(this, method, url, async, user, password);
    };

    // IPManager override - completely replace the functionality
    window.IPManager = {
        currentIP: "localhost",
        currentPort: 8000,
        baseURL: "http://localhost:8000",
        isDetecting: false,
        listeners: [],
        retryCount: 0,
        
        init: function() {
            // console.log('IPManager.init() - Using localhost override');
            this.setCurrentIP("localhost", 8000);
            return this;
        },
        
        setCurrentIP: function(host, port) {
            // console.log('IPManager.setCurrentIP() - Forced to localhost:8000');
            this.currentIP = "localhost";
            this.currentPort = 8000;
            this.baseURL = "http://localhost:8000";
            this.notifyListeners("localhost", 8000, "http://localhost:8000");
        },
        
        getBaseURL: function() {
            // console.log('IPManager.getBaseURL() - Returning http://localhost:8000');
            return "http://localhost:8000";
        },
        
        getCurrentHost: function() {
            return "localhost";
        },
        
        buildURL: function(host, port) {
            return "http://localhost:8000";
        },
        
        detectCurrentIP: function() {
            // Do nothing - always use localhost
        },
        
        onIPChange: function(callback) {
            if (typeof callback === 'function') {
                this.listeners.push(callback);
            }
        },
        
        notifyListeners: function(host, port, baseURL) {
            // console.log('IPManager.notifyListeners() - Notifying with localhost');
            this.listeners.forEach(function(callback) {
                try {
                    callback("localhost", 8000, "http://localhost:8000");
                } catch (e) {
                    // console.log('Error in IP change listener:', e.message);
                }
            });
        },
        
        log: function(message) {
            // Silent
        }
    };
    
    // console.log('IPManager override installed - all APIs will use http://localhost:8000');
    
    // Override axios when it becomes available
    let axiosCheckInterval = setInterval(function() {
        if (window.axios) {
            // console.log('Axios detected - overriding baseURL and interceptors');
            
            // Set default baseURL
            window.axios.defaults.baseURL = 'http://localhost:8000';
            
            // Add request interceptor to force localhost
            window.axios.interceptors.request.use(function(config) {
                if (config.url && isNetworkIP(config.url)) {
                    // console.log('Axios request intercepted:', config.url, '-> localhost:8000');
                    config.url = config.url.replace(/^https?:\/\/[^\/]+/, 'http://localhost:8000');
                }
                if (config.baseURL && isNetworkIP(config.baseURL)) {
                    // console.log('Axios baseURL intercepted:', config.baseURL, '-> localhost:8000');
                    config.baseURL = 'http://localhost:8000';
                }
                return config;
            });
            
            clearInterval(axiosCheckInterval);
        }
    }, 100);
    
    // Clear interval after 10 seconds to prevent infinite checking
    setTimeout(function() {
        clearInterval(axiosCheckInterval);
    }, 10000);
    
})();