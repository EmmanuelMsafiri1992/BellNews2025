// TV Browser Compatibility Polyfills
// This file provides polyfills for Samsung and LG TV browsers

(function() {
    'use strict';

    // 1. Fetch API Polyfill for older TV browsers
    if (!window.fetch) {
        window.fetch = function(url, options) {
            return new Promise(function(resolve, reject) {
                var xhr = new XMLHttpRequest();
                options = options || {};
                
                xhr.open(options.method || 'GET', url, true);
                
                // Set headers
                if (options.headers) {
                    for (var key in options.headers) {
                        if (options.headers.hasOwnProperty(key)) {
                            xhr.setRequestHeader(key, options.headers[key]);
                        }
                    }
                }
                
                // Handle timeout
                if (options.timeout) {
                    xhr.timeout = options.timeout;
                }
                
                xhr.onload = function() {
                    var response = {
                        ok: xhr.status >= 200 && xhr.status < 300,
                        status: xhr.status,
                        statusText: xhr.statusText,
                        json: function() {
                            return Promise.resolve(JSON.parse(xhr.responseText));
                        },
                        text: function() {
                            return Promise.resolve(xhr.responseText);
                        }
                    };
                    resolve(response);
                };
                
                xhr.onerror = function() {
                    reject(new Error('Network error'));
                };
                
                xhr.ontimeout = function() {
                    reject(new Error('Request timeout'));
                };
                
                xhr.send(options.body || null);
            });
        };
    }

    // 2. AbortController Polyfill
    if (!window.AbortController) {
        window.AbortController = function() {
            this.signal = {
                aborted: false,
                addEventListener: function() {},
                removeEventListener: function() {}
            };
            this.abort = function() {
                this.signal.aborted = true;
            };
        };
    }

    // 3. Promise.all polyfill (in case it's missing)
    if (!Promise.all) {
        Promise.all = function(promises) {
            return new Promise(function(resolve, reject) {
                if (!Array.isArray(promises)) {
                    reject(new TypeError('Promise.all requires an array'));
                    return;
                }
                
                var results = [];
                var pending = promises.length;
                
                if (pending === 0) {
                    resolve(results);
                    return;
                }
                
                promises.forEach(function(promise, index) {
                    Promise.resolve(promise).then(function(value) {
                        results[index] = value;
                        pending--;
                        if (pending === 0) {
                            resolve(results);
                        }
                    }).catch(reject);
                });
            });
        };
    }

    // 4. Array.prototype.find polyfill
    if (!Array.prototype.find) {
        Array.prototype.find = function(callback, thisArg) {
            if (this == null) {
                throw new TypeError('Array.prototype.find called on null or undefined');
            }
            
            var O = Object(this);
            var len = parseInt(O.length) || 0;
            
            if (typeof callback !== 'function') {
                throw new TypeError('callback must be a function');
            }
            
            var k = 0;
            while (k < len) {
                var kValue = O[k];
                if (callback.call(thisArg, kValue, k, O)) {
                    return kValue;
                }
                k++;
            }
            return undefined;
        };
    }

    // 5. Array.prototype.includes polyfill
    if (!Array.prototype.includes) {
        Array.prototype.includes = function(searchElement, fromIndex) {
            if (this == null) {
                throw new TypeError('Array.prototype.includes called on null or undefined');
            }
            
            var O = Object(this);
            var len = parseInt(O.length) || 0;
            
            if (len === 0) {
                return false;
            }
            
            var n = fromIndex | 0;
            var k = Math.max(n >= 0 ? n : len - Math.abs(n), 0);
            
            while (k < len) {
                if (O[k] === searchElement) {
                    return true;
                }
                k++;
            }
            
            return false;
        };
    }

    // 6. Object.assign polyfill
    if (!Object.assign) {
        Object.assign = function(target) {
            if (target == null) {
                throw new TypeError('Cannot convert undefined or null to object');
            }
            
            var to = Object(target);
            
            for (var index = 1; index < arguments.length; index++) {
                var nextSource = arguments[index];
                
                if (nextSource != null) {
                    for (var nextKey in nextSource) {
                        if (Object.prototype.hasOwnProperty.call(nextSource, nextKey)) {
                            to[nextKey] = nextSource[nextKey];
                        }
                    }
                }
            }
            
            return to;
        };
    }

    // 7. String.prototype.includes polyfill
    if (!String.prototype.includes) {
        String.prototype.includes = function(search, start) {
            if (typeof start !== 'number') {
                start = 0;
            }
            
            if (start + search.length > this.length) {
                return false;
            } else {
                return this.indexOf(search, start) !== -1;
            }
        };
    }

    // 8. Safe localStorage wrapper for TV browsers
    window.safeLocalStorage = (function() {
        var storage = {};
        var hasLocalStorage = false;
        
        try {
            hasLocalStorage = 'localStorage' in window && window.localStorage !== null;
            if (hasLocalStorage) {
                // Test if we can actually use localStorage
                localStorage.setItem('__test__', 'test');
                localStorage.removeItem('__test__');
            }
        } catch (e) {
            hasLocalStorage = false;
        }
        
        return {
            getItem: function(key) {
                if (hasLocalStorage) {
                    try {
                        return localStorage.getItem(key);
                    } catch (e) {
                        console.warn('localStorage.getItem failed:', e);
                    }
                }
                return storage[key] || null;
            },
            setItem: function(key, value) {
                if (hasLocalStorage) {
                    try {
                        localStorage.setItem(key, value);
                        return;
                    } catch (e) {
                        console.warn('localStorage.setItem failed:', e);
                    }
                }
                storage[key] = String(value);
            },
            removeItem: function(key) {
                if (hasLocalStorage) {
                    try {
                        localStorage.removeItem(key);
                        return;
                    } catch (e) {
                        console.warn('localStorage.removeItem failed:', e);
                    }
                }
                delete storage[key];
            }
        };
    })();

    // 9. Console polyfill for TV browsers that might not have full console
    if (!window.console) {
        window.console = {};
    }
    
    ['log', 'warn', 'error', 'info', 'debug'].forEach(function(method) {
        if (!console[method]) {
            console[method] = function() {
                // Silent fallback for TV browsers without console
            };
        }
    });

    // 10. setTimeout/setInterval safety wrapper
    var originalSetTimeout = window.setTimeout;
    var originalSetInterval = window.setInterval;
    
    window.setTimeout = function(callback, delay) {
        if (typeof callback !== 'function') {
            throw new TypeError('Callback must be a function');
        }
        return originalSetTimeout(callback, Math.max(delay || 0, 4));
    };
    
    window.setInterval = function(callback, delay) {
        if (typeof callback !== 'function') {
            throw new TypeError('Callback must be a function');
        }
        return originalSetInterval(callback, Math.max(delay || 0, 4));
    };

    // 11. TV Remote Navigation Helper
    window.TVRemoteHelper = {
        // Track focusable elements for TV remote navigation
        focusableElements: [],
        currentFocusIndex: 0,
        
        init: function() {
            this.updateFocusableElements();
            this.bindKeyEvents();
        },
        
        updateFocusableElements: function() {
            // Find all focusable elements
            this.focusableElements = Array.prototype.slice.call(
                document.querySelectorAll('button, [tabindex], .focusable, a, input, select, textarea')
            ).filter(function(el) {
                return el.offsetWidth > 0 && el.offsetHeight > 0 && !el.disabled;
            });
        },
        
        bindKeyEvents: function() {
            var self = this;
            document.addEventListener('keydown', function(e) {
                switch(e.keyCode) {
                    case 37: // Left arrow
                    case 38: // Up arrow
                        e.preventDefault();
                        self.focusPrevious();
                        break;
                    case 39: // Right arrow
                    case 40: // Down arrow
                        e.preventDefault();
                        self.focusNext();
                        break;
                    case 13: // Enter
                        var focused = document.activeElement;
                        if (focused && focused.click) {
                            focused.click();
                        }
                        break;
                }
            });
        },
        
        focusNext: function() {
            this.updateFocusableElements();
            if (this.focusableElements.length === 0) return;
            
            this.currentFocusIndex = (this.currentFocusIndex + 1) % this.focusableElements.length;
            this.focusableElements[this.currentFocusIndex].focus();
        },
        
        focusPrevious: function() {
            this.updateFocusableElements();
            if (this.focusableElements.length === 0) return;
            
            this.currentFocusIndex = this.currentFocusIndex === 0 ? 
                this.focusableElements.length - 1 : 
                this.currentFocusIndex - 1;
            this.focusableElements[this.currentFocusIndex].focus();
        }
    };

    console.log('TV browser polyfills loaded successfully');
})();