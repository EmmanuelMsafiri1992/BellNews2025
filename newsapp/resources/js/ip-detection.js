// Dynamic IP Detection System for TV Browsers
// This module automatically detects the current server IP and handles IP changes

(function() {
    'use strict';

    // IP Detection Configuration
    var config = {
        ports: [8000, 5000, 5002], // Ports to test
        timeout: 5000, // 5 second timeout per request
        retryInterval: 30000, // Check every 30 seconds
        maxRetries: 3,
        fallbackHosts: ['localhost', '127.0.0.1'], // Fallback hosts
        healthEndpoints: ['/api/settings', '/api/news', '/'], // Endpoints to test
        debugMode: false
    };

    // Global IP manager
    window.IPManager = {
        currentIP: null,
        currentPort: null,
        baseURL: null,
        isDetecting: false,
        listeners: [],
        retryCount: 0,
        
        // Initialize IP detection
        init: function() {
            this.log('Initializing IP detection system...');
            this.detectCurrentIP();
            this.startPeriodicCheck();
            return this;
        },
        
        // Add listener for IP changes
        onIPChange: function(callback) {
            if (typeof callback === 'function') {
                this.listeners.push(callback);
            }
        },
        
        // Get current base URL
        getBaseURL: function() {
            return this.baseURL || this.buildURL(this.getCurrentHost(), this.currentPort || 8000);
        },
        
        // Get current host (IP or hostname)
        getCurrentHost: function() {
            return this.currentIP || window.location.hostname || 'localhost';
        },
        
        // Build full URL
        buildURL: function(host, port) {
            var protocol = window.location.protocol || 'http:';
            return protocol + '//' + host + ':' + port;
        },
        
        // Detect current IP address
        detectCurrentIP: function() {
            var self = this;
            
            if (this.isDetecting) {
                this.log('IP detection already in progress...');
                return;
            }
            
            this.isDetecting = true;
            this.log('Starting IP detection...');
            
            // Method 1: Try to get IP from current location
            this.tryCurrentLocation()
                .then(function(result) {
                    if (result.success) {
                        self.setCurrentIP(result.host, result.port);
                        self.isDetecting = false;
                        return;
                    }
                    
                    // Method 2: Scan network for available IPs
                    return self.scanNetworkIPs();
                })
                .then(function(result) {
                    if (result && result.success) {
                        self.setCurrentIP(result.host, result.port);
                    } else {
                        self.log('Failed to detect IP, using fallback');
                        self.useFallback();
                    }
                    self.isDetecting = false;
                })
                .catch(function(error) {
                    self.log('Error during IP detection: ' + error.message);
                    self.useFallback();
                    self.isDetecting = false;
                });
        },
        
        // Try current browser location
        tryCurrentLocation: function() {
            var self = this;
            var currentHost = window.location.hostname;
            
            return new Promise(function(resolve) {
                if (!currentHost || currentHost === 'localhost' || currentHost === '127.0.0.1') {
                    resolve({ success: false, reason: 'Invalid current host' });
                    return;
                }
                
                self.testHost(currentHost, config.ports[0])
                    .then(function(success) {
                        if (success) {
                            resolve({ success: true, host: currentHost, port: config.ports[0] });
                        } else {
                            resolve({ success: false, reason: 'Current host not responsive' });
                        }
                    })
                    .catch(function(error) {
                        resolve({ success: false, reason: error.message });
                    });
            });
        },
        
        // Scan network IPs (TV browser compatible method)
        scanNetworkIPs: function() {
            var self = this;
            
            return new Promise(function(resolve) {
                // Generate likely IP addresses based on common network ranges
                var ipRanges = self.generateIPRanges();
                var testPromises = [];
                
                // Test each IP + port combination
                ipRanges.forEach(function(ip) {
                    config.ports.forEach(function(port) {
                        testPromises.push(
                            self.testHost(ip, port).then(function(success) {
                                return { success: success, host: ip, port: port };
                            }).catch(function() {
                                return { success: false, host: ip, port: port };
                            })
                        );
                    });
                });
                
                // Wait for all tests to complete and find the first successful one
                Promise.all(testPromises).then(function(results) {
                    var successful = results.find(function(result) {
                        return result.success;
                    });
                    
                    if (successful) {
                        resolve(successful);
                    } else {
                        resolve({ success: false, reason: 'No responsive hosts found' });
                    }
                });
            });
        },
        
        // Generate likely IP addresses
        generateIPRanges: function() {
            var ips = [];
            
            // Common private network ranges
            var ranges = [
                { base: '192.168.1.', start: 1, end: 254 },
                { base: '192.168.33.', start: 1, end: 254 }, // Your current network
                { base: '192.168.0.', start: 1, end: 254 },
                { base: '10.0.0.', start: 1, end: 254 },
                { base: '172.16.0.', start: 1, end: 254 }
            ];
            
            // Add current network range first (if we can detect it)
            var currentIP = this.getCurrentNetworkBase();
            if (currentIP) {
                ranges.unshift({ base: currentIP, start: 1, end: 254 });
            }
            
            // Generate IPs with priority for common ones
            var commonIPs = [3, 1, 2, 100, 101, 145, 150]; // Your known IPs + common ones
            
            ranges.forEach(function(range) {
                // Add common IPs first
                commonIPs.forEach(function(ip) {
                    if (ip >= range.start && ip <= range.end) {
                        ips.push(range.base + ip);
                    }
                });
                
                // Then add a few more from the range
                for (var i = range.start; i <= Math.min(range.start + 10, range.end); i++) {
                    if (commonIPs.indexOf(i) === -1) {
                        ips.push(range.base + i);
                    }
                }
            });
            
            return ips;
        },
        
        // Get current network base (192.168.x. format)
        getCurrentNetworkBase: function() {
            try {
                var currentHost = window.location.hostname;
                if (currentHost && currentHost !== 'localhost') {
                    var parts = currentHost.split('.');
                    if (parts.length === 4) {
                        return parts[0] + '.' + parts[1] + '.' + parts[2] + '.';
                    }
                }
            } catch (e) {
                this.log('Error getting network base: ' + e.message);
            }
            return null;
        },
        
        // Test if a host:port combination is responsive
        testHost: function(host, port) {
            var self = this;
            var url = this.buildURL(host, port);
            
            return new Promise(function(resolve) {
                var timeout = setTimeout(function() {
                    resolve(false);
                }, config.timeout);
                
                // Try multiple endpoints
                var testEndpoint = function(endpointIndex) {
                    if (endpointIndex >= config.healthEndpoints.length) {
                        clearTimeout(timeout);
                        resolve(false);
                        return;
                    }
                    
                    var endpoint = config.healthEndpoints[endpointIndex];
                    var testURL = url + endpoint;
                    
                    // Use fetch if available, otherwise XMLHttpRequest
                    var makeRequest = window.fetch ? 
                        self.fetchRequest.bind(self) : 
                        self.xhrRequest.bind(self);
                    
                    makeRequest(testURL)
                        .then(function(success) {
                            clearTimeout(timeout);
                            if (success) {
                                self.log('Host responsive: ' + url);
                                resolve(true);
                            } else {
                                testEndpoint(endpointIndex + 1);
                            }
                        })
                        .catch(function() {
                            testEndpoint(endpointIndex + 1);
                        });
                };
                
                testEndpoint(0);
            });
        },
        
        // Fetch request method
        fetchRequest: function(url) {
            return fetch(url, {
                method: 'GET',
                mode: 'cors',
                credentials: 'omit',
                timeout: config.timeout
            }).then(function(response) {
                return response.status < 500; // Accept any response that's not server error
            }).catch(function() {
                return false;
            });
        },
        
        // XMLHttpRequest method (TV browser fallback)
        xhrRequest: function(url) {
            return new Promise(function(resolve) {
                var xhr = new XMLHttpRequest();
                
                xhr.timeout = config.timeout;
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
        
        // Set current IP and notify listeners
        setCurrentIP: function(host, port) {
            var oldURL = this.baseURL;
            
            this.currentIP = host;
            this.currentPort = port;
            this.baseURL = this.buildURL(host, port);
            this.retryCount = 0;
            
            this.log('IP updated: ' + this.baseURL);
            
            // Store in safe localStorage
            if (window.safeLocalStorage) {
                window.safeLocalStorage.setItem('detectedIP', host);
                window.safeLocalStorage.setItem('detectedPort', port.toString());
            }
            
            // Notify listeners if IP changed
            if (oldURL !== this.baseURL) {
                this.notifyListeners(host, port, this.baseURL);
            }
        },
        
        // Use fallback configuration
        useFallback: function() {
            var fallbackHost = config.fallbackHosts[0];
            var fallbackPort = config.ports[0];
            
            this.log('Using fallback: ' + fallbackHost + ':' + fallbackPort);
            this.setCurrentIP(fallbackHost, fallbackPort);
        },
        
        // Notify all listeners of IP change
        notifyListeners: function(host, port, baseURL) {
            var self = this;
            this.listeners.forEach(function(callback) {
                try {
                    callback(host, port, baseURL);
                } catch (e) {
                    self.log('Error in IP change listener: ' + e.message);
                }
            });
        },
        
        // Start periodic IP checking
        startPeriodicCheck: function() {
            var self = this;
            
            setInterval(function() {
                if (!self.isDetecting) {
                    self.verifyCurrentIP();
                }
            }, config.retryInterval);
        },
        
        // Verify current IP is still valid
        verifyCurrentIP: function() {
            var self = this;
            
            if (!this.currentIP || !this.currentPort) {
                this.detectCurrentIP();
                return;
            }
            
            this.testHost(this.currentIP, this.currentPort)
                .then(function(success) {
                    if (!success) {
                        self.log('Current IP no longer responsive, re-detecting...');
                        self.detectCurrentIP();
                    } else {
                        self.log('Current IP verified: ' + self.baseURL);
                    }
                })
                .catch(function(error) {
                    self.log('Error verifying IP: ' + error.message);
                    self.detectCurrentIP();
                });
        },
        
        // Load saved IP from storage
        loadSavedIP: function() {
            if (window.safeLocalStorage) {
                var savedIP = window.safeLocalStorage.getItem('detectedIP');
                var savedPort = window.safeLocalStorage.getItem('detectedPort');
                
                if (savedIP && savedPort) {
                    this.log('Loaded saved IP: ' + savedIP + ':' + savedPort);
                    this.setCurrentIP(savedIP, parseInt(savedPort, 10));
                    return true;
                }
            }
            return false;
        },
        
        // Logging utility
        log: function(message) {
            if (config.debugMode || window.IP_DEBUG) {
                console.log('[IP Detection] ' + message);
            }
        }
    };

    // Initialize when DOM is ready
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', function() {
            setTimeout(function() {
                window.IPManager.init();
            }, 100);
        });
    } else {
        setTimeout(function() {
            window.IPManager.init();
        }, 100);
    }

    console.log('IP Detection system loaded');
})();