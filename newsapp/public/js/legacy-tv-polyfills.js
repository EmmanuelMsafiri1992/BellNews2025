// Comprehensive Legacy TV Browser Polyfills for 2015-2017 TVs
(function() {
    'use strict';
    
    // Feature detection flags
    var hasNativeSupport = {
        fetch: typeof window.fetch === 'function',
        promise: typeof Promise === 'function',
        es6: (function() { try { eval('const x = 1'); return true; } catch(e) { return false; }})(),
        flexbox: (function() {
            var div = document.createElement('div');
            div.style.display = 'flex';
            return div.style.display === 'flex';
        })()
    };
    
    // console.log('Legacy TV Polyfills - Feature detection:', hasNativeSupport);

    // 1. EXTREMELY BASIC PROMISE IMPLEMENTATION for oldest TVs
    if (!window.Promise || typeof Promise !== 'function') {
        // console.log('Installing basic Promise polyfill for very old TV browsers');
        window.Promise = function(executor) {
            var self = this;
            self.state = 'pending';
            self.value = undefined;
            self.handlers = [];
            
            function resolve(result) {
                if (self.state === 'pending') {
                    self.state = 'fulfilled';
                    self.value = result;
                    self.handlers.forEach(handle);
                    self.handlers = null;
                }
            }
            
            function reject(error) {
                if (self.state === 'pending') {
                    self.state = 'rejected';
                    self.value = error;
                    self.handlers.forEach(handle);
                    self.handlers = null;
                }
            }
            
            function handle(handler) {
                if (self.state === 'pending') {
                    self.handlers.push(handler);
                } else {
                    if (self.state === 'fulfilled' && typeof handler.onFulfilled === 'function') {
                        handler.onFulfilled(self.value);
                    }
                    if (self.state === 'rejected' && typeof handler.onRejected === 'function') {
                        handler.onRejected(self.value);
                    }
                }
            }
            
            this.then = function(onFulfilled, onRejected) {
                return new Promise(function(resolve, reject) {
                    handle({
                        onFulfilled: function(result) {
                            try {
                                resolve(onFulfilled ? onFulfilled(result) : result);
                            } catch (ex) {
                                reject(ex);
                            }
                        },
                        onRejected: function(error) {
                            try {
                                resolve(onRejected ? onRejected(error) : error);
                            } catch (ex) {
                                reject(ex);
                            }
                        }
                    });
                });
            };
            
            this.catch = function(onRejected) {
                return this.then(null, onRejected);
            };
            
            try {
                executor(resolve, reject);
            } catch (ex) {
                reject(ex);
            }
        };
        
        // Promise.all for very basic implementation
        Promise.all = function(promises) {
            return new Promise(function(resolve, reject) {
                if (!promises.length) {
                    resolve([]);
                    return;
                }
                var results = [];
                var remaining = promises.length;
                
                promises.forEach(function(promise, index) {
                    Promise.resolve(promise).then(function(result) {
                        results[index] = result;
                        remaining--;
                        if (remaining === 0) {
                            resolve(results);
                        }
                    }).catch(reject);
                });
            });
        };
        
        Promise.resolve = function(value) {
            return new Promise(function(resolve) { resolve(value); });
        };
        
        Promise.reject = function(reason) {
            return new Promise(function(resolve, reject) { reject(reason); });
        };
    }

    // 2. ENHANCED FETCH POLYFILL with better error handling
    if (!window.fetch) {
        // console.log('Installing enhanced fetch polyfill for old TV browsers');
        window.fetch = function(url, options) {
            return new Promise(function(resolve, reject) {
                var xhr = new XMLHttpRequest();
                options = options || {};
                
                // Handle different input types
                if (typeof url !== 'string') {
                    if (url && url.url) {
                        url = url.url;
                    } else {
                        reject(new TypeError('Invalid URL'));
                        return;
                    }
                }
                
                xhr.open(options.method || 'GET', url, true);
                
                // Set headers with validation
                if (options.headers) {
                    for (var key in options.headers) {
                        if (options.headers.hasOwnProperty(key)) {
                            try {
                                xhr.setRequestHeader(key, options.headers[key]);
                            } catch(e) {
                                console.warn('Failed to set header:', key, e);
                            }
                        }
                    }
                }
                
                // Timeout handling
                if (options.timeout) {
                    xhr.timeout = options.timeout;
                }
                
                // Enhanced response object
                xhr.onload = function() {
                    var response = {
                        ok: xhr.status >= 200 && xhr.status < 300,
                        status: xhr.status,
                        statusText: xhr.statusText || '',
                        url: url,
                        headers: {
                            get: function(name) {
                                return xhr.getResponseHeader(name);
                            }
                        },
                        text: function() {
                            return Promise.resolve(xhr.responseText || '');
                        },
                        json: function() {
                            return Promise.resolve().then(function() {
                                try {
                                    return JSON.parse(xhr.responseText || '{}');
                                } catch(e) {
                                    throw new Error('Invalid JSON response');
                                }
                            });
                        },
                        blob: function() {
                            return Promise.resolve(new Blob([xhr.response]));
                        }
                    };
                    resolve(response);
                };
                
                xhr.onerror = function() {
                    reject(new TypeError('Network request failed'));
                };
                
                xhr.ontimeout = function() {
                    reject(new TypeError('Network request timed out'));
                };
                
                xhr.onabort = function() {
                    reject(new TypeError('Network request aborted'));
                };
                
                // Send with error handling
                try {
                    xhr.send(options.body || null);
                } catch(e) {
                    reject(new TypeError('Failed to send request: ' + e.message));
                }
            });
        };
    }

    // 3. ARRAY METHODS for oldest TV browsers
    if (!Array.prototype.forEach) {
        Array.prototype.forEach = function(callback, thisArg) {
            for (var i = 0; i < this.length; i++) {
                if (i in this) {
                    callback.call(thisArg, this[i], i, this);
                }
            }
        };
    }
    
    if (!Array.prototype.map) {
        Array.prototype.map = function(callback, thisArg) {
            var result = [];
            for (var i = 0; i < this.length; i++) {
                if (i in this) {
                    result[i] = callback.call(thisArg, this[i], i, this);
                }
            }
            return result;
        };
    }
    
    if (!Array.prototype.filter) {
        Array.prototype.filter = function(callback, thisArg) {
            var result = [];
            for (var i = 0; i < this.length; i++) {
                if (i in this && callback.call(thisArg, this[i], i, this)) {
                    result.push(this[i]);
                }
            }
            return result;
        };
    }
    
    if (!Array.prototype.reduce) {
        Array.prototype.reduce = function(callback, initialValue) {
            var i = 0, value;
            
            if (arguments.length >= 2) {
                value = initialValue;
            } else {
                if (this.length === 0) {
                    throw new TypeError('Reduce of empty array with no initial value');
                }
                value = this[i++];
            }
            
            for (; i < this.length; i++) {
                if (i in this) {
                    value = callback(value, this[i], i, this);
                }
            }
            return value;
        };
    }
    
    // 4. OBJECT METHODS for oldest browsers
    if (!Object.keys) {
        Object.keys = function(obj) {
            var keys = [];
            for (var key in obj) {
                if (obj.hasOwnProperty(key)) {
                    keys.push(key);
                }
            }
            return keys;
        };
    }
    
    if (!Object.create) {
        Object.create = function(proto) {
            function F() {}
            F.prototype = proto;
            return new F();
        };
    }

    // 5. JSON SAFETY for very old browsers
    if (!window.JSON) {
        window.JSON = {
            parse: function(text) {
                try {
                    return eval('(' + text + ')');
                } catch(e) {
                    throw new SyntaxError('Invalid JSON');
                }
            },
            stringify: function(obj) {
                if (obj === null) return 'null';
                if (typeof obj === 'undefined') return undefined;
                if (typeof obj === 'string') return '"' + obj.replace(/"/g, '\\"') + '"';
                if (typeof obj === 'number' || typeof obj === 'boolean') return String(obj);
                if (obj instanceof Array) {
                    var arr = [];
                    for (var i = 0; i < obj.length; i++) {
                        arr.push(JSON.stringify(obj[i]) || 'null');
                    }
                    return '[' + arr.join(',') + ']';
                }
                if (typeof obj === 'object') {
                    var pairs = [];
                    for (var key in obj) {
                        if (obj.hasOwnProperty(key) && typeof obj[key] !== 'undefined') {
                            pairs.push(JSON.stringify(key) + ':' + JSON.stringify(obj[key]));
                        }
                    }
                    return '{' + pairs.join(',') + '}';
                }
                return undefined;
            }
        };
    }

    // 6. CONSOLE SAFETY for very old TV browsers
    if (!window.console) {
        window.console = {};
    }
    var consoleMethods = ['log', 'warn', 'error', 'info', 'debug', 'trace', 'time', 'timeEnd'];
    for (var i = 0; i < consoleMethods.length; i++) {
        if (!console[consoleMethods[i]]) {
            console[consoleMethods[i]] = function() {};
        }
    }

    // 7. BASIC CSS FLEXBOX FALLBACK
    if (!hasNativeSupport.flexbox) {
        // console.log('Adding CSS Flexbox fallbacks for old TV browsers');
        
        // Add basic flexbox CSS fallbacks
        var style = document.createElement('style');
        style.textContent = [
            '.flex { display: block !important; }',
            '.flex-1 { width: 100% !important; }',
            '.flex-col { display: block !important; }',
            '.flex-row { display: block !important; }',
            '.items-center { text-align: center !important; }',
            '.justify-center { text-align: center !important; }',
            '.justify-between { }',
            '.space-x-4 > * { margin-right: 16px !important; }',
            '.space-y-4 > * { margin-bottom: 16px !important; }',
            '.grid { display: block !important; }',
            '.grid-cols-1 > *, .grid-cols-2 > * { width: 100% !important; display: block !important; }',
            '@media (min-width: 1024px) { .lg\\:grid-cols-2 > * { width: 48% !important; float: left !important; margin-right: 4% !important; } }'
        ].join('\n');
        
        if (document.head) {
            document.head.appendChild(style);
        } else {
            // For very old browsers that might not have document.head
            setTimeout(function() {
                (document.head || document.getElementsByTagName('head')[0]).appendChild(style);
            }, 100);
        }
    }

    // 8. ENHANCED TV REMOTE CONTROL for older TVs
    window.LegacyTVRemote = {
        init: function() {
            // console.log('Initializing Legacy TV Remote Control');
            this.bindEvents();
            this.enhanceFocus();
        },
        
        bindEvents: function() {
            var self = this;
            
            // More comprehensive key handling for different TV brands
            document.addEventListener('keydown', function(e) {
                var keyCode = e.keyCode || e.which;
                
                // Samsung, LG, and generic TV remote codes
                switch(keyCode) {
                    case 37: case 4: // Left arrow / Samsung left
                        e.preventDefault();
                        self.navigate('left');
                        break;
                    case 38: case 1: // Up arrow / Samsung up  
                        e.preventDefault();
                        self.navigate('up');
                        break;
                    case 39: case 5: // Right arrow / Samsung right
                        e.preventDefault();
                        self.navigate('right');
                        break;
                    case 40: case 2: // Down arrow / Samsung down
                        e.preventDefault();
                        self.navigate('down');
                        break;
                    case 13: case 29443: // Enter / Samsung enter
                        e.preventDefault();
                        self.activate();
                        break;
                    case 8: case 27: case 461: // Back / ESC / Samsung back
                        e.preventDefault();
                        self.goBack();
                        break;
                }
            });
        },
        
        navigate: function(direction) {
            var focusable = this.getFocusableElements();
            var current = document.activeElement;
            var currentIndex = focusable.indexOf(current);
            
            if (currentIndex === -1 && focusable.length > 0) {
                focusable[0].focus();
                return;
            }
            
            var newIndex;
            switch(direction) {
                case 'up':
                case 'left':
                    newIndex = currentIndex > 0 ? currentIndex - 1 : focusable.length - 1;
                    break;
                case 'down':
                case 'right':
                    newIndex = currentIndex < focusable.length - 1 ? currentIndex + 1 : 0;
                    break;
            }
            
            if (focusable[newIndex]) {
                focusable[newIndex].focus();
                this.highlightFocused(focusable[newIndex]);
            }
        },
        
        getFocusableElements: function() {
            var selectors = [
                'button:not([disabled])',
                'a[href]',
                'input:not([disabled])',
                'select:not([disabled])',
                'textarea:not([disabled])',
                '[tabindex]:not([tabindex="-1"])',
                '.focusable'
            ].join(', ');
            
            return Array.prototype.slice.call(document.querySelectorAll(selectors))
                .filter(function(el) {
                    return el.offsetWidth > 0 && el.offsetHeight > 0;
                });
        },
        
        activate: function() {
            var focused = document.activeElement;
            if (focused) {
                if (focused.click) {
                    focused.click();
                } else if (focused.onActivate) {
                    focused.onActivate();
                }
            }
        },
        
        goBack: function() {
            // Try to find and click back button or trigger custom back event
            var backButton = document.querySelector('[data-back], .back-button, .btn-back');
            if (backButton && backButton.click) {
                backButton.click();
            } else {
                window.history.back();
            }
        },
        
        highlightFocused: function(element) {
            // Remove previous highlights
            var highlighted = document.querySelectorAll('.tv-focused');
            for (var i = 0; i < highlighted.length; i++) {
                highlighted[i].classList.remove('tv-focused');
            }
            
            // Add highlight to current element
            if (element) {
                element.classList.add('tv-focused');
            }
        },
        
        enhanceFocus: function() {
            // Add CSS for better focus visibility on old TVs
            var style = document.createElement('style');
            style.textContent = [
                '.tv-focused { outline: 3px solid #FFD700 !important; outline-offset: 2px !important; background-color: rgba(255, 215, 0, 0.1) !important; }',
                'button:focus, a:focus, input:focus, select:focus, textarea:focus, .focusable:focus {',
                '  outline: 2px solid #FFD700 !important;',
                '  outline-offset: 2px !important;',
                '  background-color: rgba(255, 215, 0, 0.1) !important;',
                '}',
                'button, a, input, select, textarea, .focusable { transition: none !important; }' // Disable transitions for better TV performance
            ].join('\n');
            
            (document.head || document.getElementsByTagName('head')[0]).appendChild(style);
        }
    };

    // 9. MEMORY AND PERFORMANCE OPTIMIZATIONS
    window.TVOptimizer = {
        init: function() {
            // console.log('Initializing TV Performance Optimizer');
            this.optimizeImages();
            this.optimizeAnimations();
            this.setupMemoryCleanup();
        },
        
        optimizeImages: function() {
            // Lazy load images more aggressively
            var images = document.getElementsByTagName('img');
            for (var i = 0; i < images.length; i++) {
                var img = images[i];
                if (img.src && !img.complete) {
                    img.onerror = function() {
                        this.src = 'data:image/svg+xml,%3Csvg xmlns="http://www.w3.org/2000/svg" width="300" height="200"%3E%3Crect width="100%25" height="100%25" fill="%23ddd"/%3E%3Ctext x="50%25" y="50%25" text-anchor="middle" fill="%23999"%3EImage%3C/text%3E%3C/svg%3E';
                    };
                }
            }
        },
        
        optimizeAnimations: function() {
            // Disable CSS animations for better performance on old TVs
            var style = document.createElement('style');
            style.textContent = [
                '*, *:before, *:after {',
                '  animation-duration: 0s !important;',
                '  animation-delay: 0s !important;',
                '  transition-duration: 0s !important;',
                '  transition-delay: 0s !important;',
                '}'
            ].join('\n');
            (document.head || document.getElementsByTagName('head')[0]).appendChild(style);
        },
        
        setupMemoryCleanup: function() {
            // Periodic cleanup for memory-constrained TV browsers
            setInterval(function() {
                if (window.gc) {
                    window.gc();
                }
                
                // Remove unused event listeners
                var elements = document.querySelectorAll('*');
                for (var i = 0; i < elements.length; i++) {
                    if (elements[i]._listeners) {
                        delete elements[i]._listeners;
                    }
                }
            }, 300000); // Every 5 minutes
        }
    };

    // INITIALIZE ALL POLYFILLS AND OPTIMIZATIONS
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function() {
            setTimeout(function() {
                window.LegacyTVRemote.init();
                window.TVOptimizer.init();
            }, 500);
        });
    } else {
        setTimeout(function() {
            window.LegacyTVRemote.init();
            window.TVOptimizer.init();
        }, 500);
    }

    // console.log('Legacy TV Polyfills loaded successfully for 2015-2017 Smart TVs');
})();