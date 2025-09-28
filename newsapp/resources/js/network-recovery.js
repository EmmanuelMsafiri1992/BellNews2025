// Network Recovery System for TV Browsers
// Handles automatic recovery from network issues and IP changes

(function() {
    'use strict';

    // Recovery Configuration
    var config = {
        maxRetries: 5,
        retryInterval: 5000, // 5 seconds
        healthCheckInterval: 30000, // 30 seconds
        connectionTimeout: 10000, // 10 seconds
        exponentialBackoff: true,
        maxBackoffDelay: 120000, // 2 minutes
        debugMode: true
    };

    // Network Recovery Manager
    window.NetworkRecovery = {
        isRecovering: false,
        retryCount: 0,
        recoveryListeners: [],
        lastKnownGoodURL: null,
        connectionStatus: 'unknown', // 'connected', 'disconnected', 'recovering'
        
        // Initialize recovery system
        init: function() {
            this.log('Initializing Network Recovery System...');
            this.startHealthCheck();
            this.bindVisibilityEvents();
            return this;
        },
        
        // Add listener for recovery events
        onRecovery: function(callback) {
            if (typeof callback === 'function') {
                this.recoveryListeners.push(callback);
            }
        },
        
        // Start recovery process
        startRecovery: function(reason) {
            if (this.isRecovering) {
                this.log('Recovery already in progress...');
                return;
            }
            
            this.isRecovering = true;
            this.connectionStatus = 'recovering';
            this.retryCount = 0;
            
            this.log('Starting recovery process. Reason: ' + reason);
            this.notifyRecoveryStart(reason);
            
            this.attemptRecovery();
        },
        
        // Attempt to recover connection
        attemptRecovery: function() {
            var self = this;
            
            this.retryCount++;
            this.log('Recovery attempt ' + this.retryCount + '/' + config.maxRetries);
            
            // First, try to detect new IP
            if (window.IPManager) {
                window.IPManager.detectCurrentIP();
                
                // Wait for IP detection to complete
                setTimeout(function() {
                    self.testConnection().then(function(success) {
                        if (success) {
                            self.recoverySuccess();
                        } else {
                            self.scheduleNextAttempt();
                        }
                    }).catch(function(error) {
                        self.log('Recovery test failed: ' + error.message);
                        self.scheduleNextAttempt();
                    });
                }, 2000);
            } else {
                // Fallback without IP Manager
                this.testConnection().then(function(success) {
                    if (success) {
                        self.recoverySuccess();
                    } else {
                        self.scheduleNextAttempt();
                    }
                }).catch(function(error) {
                    self.log('Recovery test failed: ' + error.message);
                    self.scheduleNextAttempt();
                });
            }
        },
        
        // Schedule next recovery attempt
        scheduleNextAttempt: function() {
            var self = this;
            
            if (this.retryCount >= config.maxRetries) {
                this.log('Max recovery attempts reached. Giving up.');
                this.recoveryFailed();
                return;
            }
            
            var delay = config.retryInterval;
            
            // Apply exponential backoff
            if (config.exponentialBackoff) {
                delay = Math.min(
                    config.retryInterval * Math.pow(2, this.retryCount - 1),
                    config.maxBackoffDelay
                );
            }
            
            this.log('Scheduling next attempt in ' + (delay / 1000) + ' seconds');
            
            setTimeout(function() {
                self.attemptRecovery();
            }, delay);
        },
        
        // Test connection to server
        testConnection: function() {
            var self = this;
            var baseURL = window.IPManager ? window.IPManager.getBaseURL() : this.getDefaultURL();
            
            return new Promise(function(resolve) {
                // Test multiple endpoints
                var endpoints = ['/api/health', '/api/ping', '/api/settings'];
                var testPromises = [];
                
                endpoints.forEach(function(endpoint) {
                    testPromises.push(self.testEndpoint(baseURL + endpoint));
                });
                
                Promise.all(testPromises).then(function(results) {
                    var successful = results.some(function(result) { return result; });
                    resolve(successful);
                });
            });
        },
        
        // Test specific endpoint
        testEndpoint: function(url) {
            var self = this;
            
            return new Promise(function(resolve) {
                var timeout = setTimeout(function() {
                    resolve(false);
                }, config.connectionTimeout);
                
                // Use fetch or XHR based on availability
                var makeRequest = window.fetch ? 
                    self.fetchTest.bind(self) : 
                    self.xhrTest.bind(self);
                
                makeRequest(url).then(function(success) {
                    clearTimeout(timeout);
                    resolve(success);
                }).catch(function() {
                    clearTimeout(timeout);
                    resolve(false);
                });
            });
        },
        
        // Fetch-based test
        fetchTest: function(url) {
            return fetch(url, {
                method: 'GET',
                mode: 'cors',
                credentials: 'omit',
                timeout: config.connectionTimeout
            }).then(function(response) {
                return response.ok;
            }).catch(function() {
                return false;
            });
        },
        
        // XHR-based test
        xhrTest: function(url) {
            return new Promise(function(resolve) {
                var xhr = new XMLHttpRequest();
                
                xhr.timeout = config.connectionTimeout;
                xhr.onload = function() {
                    resolve(xhr.status < 500);
                };
                xhr.onerror = function() {
                    resolve(false);
                };
                xhr.ontimeout = function() {
                    resolve(false);
                };
                
                try {
                    xhr.open('GET', url, true);
                    xhr.send();
                } catch (e) {
                    resolve(false);
                }
            });
        },
        
        // Recovery successful
        recoverySuccess: function() {
            this.log('Recovery successful after ' + this.retryCount + ' attempts');
            
            this.isRecovering = false;
            this.retryCount = 0;
            this.connectionStatus = 'connected';
            
            if (window.IPManager) {
                this.lastKnownGoodURL = window.IPManager.getBaseURL();
            }
            
            this.notifyRecoverySuccess();
        },
        
        // Recovery failed
        recoveryFailed: function() {
            this.log('Recovery failed after ' + config.maxRetries + ' attempts');
            
            this.isRecovering = false;
            this.connectionStatus = 'disconnected';
            
            this.notifyRecoveryFailed();
        },
        
        // Start periodic health checks
        startHealthCheck: function() {
            var self = this;
            
            setInterval(function() {
                if (!self.isRecovering) {
                    self.performHealthCheck();
                }
            }, config.healthCheckInterval);
        },
        
        // Perform health check
        performHealthCheck: function() {
            var self = this;
            
            this.testConnection().then(function(success) {
                if (success) {
                    if (self.connectionStatus !== 'connected') {
                        self.connectionStatus = 'connected';
                        self.log('Connection restored');
                    }
                } else {
                    if (self.connectionStatus === 'connected') {
                        self.log('Connection lost, starting recovery...');
                        self.startRecovery('Health check failed');
                    }
                }
            }).catch(function(error) {
                self.log('Health check error: ' + error.message);
                if (self.connectionStatus === 'connected') {
                    self.startRecovery('Health check error');
                }
            });
        },
        
        // Handle visibility changes (when TV app comes back to foreground)
        bindVisibilityEvents: function() {
            var self = this;
            
            // Handle page visibility changes
            document.addEventListener('visibilitychange', function() {
                if (!document.hidden) {
                    self.log('Page became visible, performing health check');
                    setTimeout(function() {
                        self.performHealthCheck();
                    }, 1000);
                }
            });
            
            // Handle window focus events
            window.addEventListener('focus', function() {
                self.log('Window focused, performing health check');
                setTimeout(function() {
                    self.performHealthCheck();
                }, 1000);
            });
        },
        
        // Get default URL fallback
        getDefaultURL: function() {
            if (window.location.hostname && window.location.hostname !== 'localhost') {
                var protocol = window.location.protocol || 'http:';
                return protocol + '//' + window.location.hostname + ':8000';
            }
            return 'http://127.0.0.1:8000';
        },
        
        // Notify listeners of recovery start
        notifyRecoveryStart: function(reason) {
            this.recoveryListeners.forEach(function(callback) {
                try {
                    callback('start', reason);
                } catch (e) {
                    console.error('Error in recovery listener:', e);
                }
            });
        },
        
        // Notify listeners of recovery success
        notifyRecoverySuccess: function() {
            this.recoveryListeners.forEach(function(callback) {
                try {
                    callback('success');
                } catch (e) {
                    console.error('Error in recovery listener:', e);
                }
            });
        },
        
        // Notify listeners of recovery failure
        notifyRecoveryFailed: function() {
            this.recoveryListeners.forEach(function(callback) {
                try {
                    callback('failed');
                } catch (e) {
                    console.error('Error in recovery listener:', e);
                }
            });
        },
        
        // Get current status
        getStatus: function() {
            return {
                status: this.connectionStatus,
                isRecovering: this.isRecovering,
                retryCount: this.retryCount,
                lastKnownGoodURL: this.lastKnownGoodURL
            };
        },
        
        // Manual recovery trigger
        recover: function() {
            this.startRecovery('Manual recovery triggered');
        },
        
        // Logging utility
        log: function(message) {
            if (config.debugMode || window.NETWORK_DEBUG) {
                console.log('[Network Recovery] ' + message);
            }
        }
    };

    // Auto-initialize when IP Manager is available
    if (window.IPManager) {
        window.IPManager.onIPChange(function() {
            window.NetworkRecovery.log('IP changed, verifying connection...');
            setTimeout(function() {
                window.NetworkRecovery.performHealthCheck();
            }, 1000);
        });
    }

    // Initialize when DOM is ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function() {
            setTimeout(function() {
                window.NetworkRecovery.init();
            }, 500);
        });
    } else {
        setTimeout(function() {
            window.NetworkRecovery.init();
        }, 500);
    }

    console.log('Network Recovery system loaded');
})();