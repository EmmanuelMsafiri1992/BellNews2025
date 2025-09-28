<!DOCTYPE html>
<html lang="{{ str_replace('_', '-', app()->getLocale()) }}">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="X-UA-Compatible" content="ie=edge">
    <meta name="csrf-token" content="{{ csrf_token() }}">
    <title>School News - News</title>
    <link rel="icon" type="image/png" href="{{ asset('favicon.ico') }}">
    
    <!-- TV Browser Compatible Fonts -->
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    
    <!-- TV Browser Detection and Environment Setup -->
    <script>
        // TV Browser Detection
        (function() {
            var userAgent = navigator.userAgent.toLowerCase();
            var isTizen = userAgent.includes('tizen') || userAgent.includes('samsung');
            var isWebOS = userAgent.includes('webos') || userAgent.includes('lg');
            var isTV = isTizen || isWebOS || userAgent.includes('tv') || 
                      (screen.width >= 1920 && screen.height >= 1080);
            
            // Set global environment variables for the app
            window.ENV_API_BASE_URL = '{{ config("app.url", "http://127.0.0.1:8000") }}';
            window.IS_TV_BROWSER = isTV;
            window.TV_BROWSER_TYPE = isTizen ? 'tizen' : isWebOS ? 'webos' : 'unknown';
            
            // Add TV browser class to html element
            if (isTV) {
                document.documentElement.className += ' tv-browser';
            }
            if (isTizen) {
                document.documentElement.className += ' tizen-browser';
            }
            if (isWebOS) {
                document.documentElement.className += ' webos-browser';
            }
        })();
    </script>
    <!-- Include TV-compatible styles -->
    @vite(['resources/css/app.css', 'resources/js/app.js'])
    
    <style>
        /* Base styles for all devices */
        body {
            font-family: 'Inter', 'Roboto', Arial, sans-serif;
            background-color: #f7f9fc;
            margin: 0;
            padding: 0;
            color: #333;
            line-height: 1.6;
        }
        
        .container {
            max-width: 1280px;
            margin-left: auto;
            margin-right: auto;
            padding-left: 1rem;
            padding-right: 1rem;
        }
        
        #app {
            min-height: 100vh;
            display: flex;
            flex-direction: column;
        }
        
        /* TV-specific overrides */
        .tv-browser body {
            font-size: 20px;
            -webkit-font-smoothing: antialiased;
            text-rendering: optimizeLegibility;
        }
        
        .tv-browser .container {
            max-width: 90%;
            padding-left: 2rem;
            padding-right: 2rem;
        }
        
        /* Samsung Tizen TV specific fixes */
        .tizen-browser * {
            -webkit-transform: translateZ(0);
            transform: translateZ(0);
        }
        
        /* LG WebOS TV specific fixes */
        .webos-browser button:focus,
        .webos-browser .focusable:focus {
            outline: 4px solid #007bff !important;
            outline-offset: 2px !important;
            box-shadow: 0 0 0 8px rgba(0, 123, 255, 0.3) !important;
        }
        
        /* Loading fallback for TV browsers */
        .tv-loading-fallback {
            display: none;
            position: fixed;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            font-size: 24px;
            color: #333;
            background: rgba(255, 255, 255, 0.9);
            padding: 40px;
            border-radius: 8px;
            box-shadow: 0 4px 8px rgba(0, 0, 0, 0.1);
            z-index: 9999;
        }
        
        .tv-browser .tv-loading-fallback {
            display: block;
        }
        
        /* High contrast mode for better TV visibility */
        @media (prefers-contrast: high), (prefers-color-scheme: dark) {
            .tv-browser body {
                background-color: #1a1a1a;
                color: #ffffff;
            }
        }
    </style>
</head>
<body class="antialiased">
    <!-- TV Browser Loading Fallback -->
    <div class="tv-loading-fallback" id="tv-loading">
        <div>Loading News App for TV...</div>
        <div style="margin-top: 20px;">
            <div class="tv-loading"></div>
        </div>
    </div>
    
    <!-- Main App Container -->
    <div id="app">
        <!-- Vue.js app will mount here -->
    </div>

    <!-- Fallback content for browsers that don't support JavaScript -->
    <noscript>
        <div style="text-align: center; padding: 50px; font-size: 24px;">
            <h1>News App</h1>
            <p>This application requires JavaScript to function properly.</p>
            <p>Please enable JavaScript in your TV browser settings.</p>
        </div>
    </noscript>

    <!-- TV Remote Navigation Script -->
    <script>
        // Hide loading fallback once DOM is ready
        document.addEventListener('DOMContentLoaded', function() {
            setTimeout(function() {
                var loading = document.getElementById('tv-loading');
                if (loading) {
                    loading.style.display = 'none';
                }
            }, 3000); // Hide after 3 seconds
        });
        
        // TV Remote Navigation Enhancement
        if (window.IS_TV_BROWSER) {
            document.addEventListener('keydown', function(e) {
                // TV remote button mappings
                switch(e.keyCode) {
                    case 10009: // Return key on Samsung TV
                    case 461: // Return key on LG TV
                    case 27: // ESC key fallback
                        e.preventDefault();
                        // Handle back/return functionality
                        break;
                    case 415: // Play button
                        e.preventDefault();
                        // Handle play/pause if applicable
                        break;
                }
            });
        }
        
        // Show IP detection status (for debugging)
        setTimeout(function() {
            if (window.IPManager && window.IP_DEBUG) {
                var status = document.createElement('div');
                status.id = 'ip-status';
                status.style.cssText = 'position:fixed;top:10px;right:10px;background:rgba(0,0,0,0.8);color:white;padding:10px;font-size:12px;border-radius:4px;z-index:9999;font-family:monospace;';
                status.innerHTML = 'Detecting IP...';
                document.body.appendChild(status);
                
                window.IPManager.onIPChange(function(host, port, baseURL) {
                    status.innerHTML = 'Connected: ' + host + ':' + port;
                    setTimeout(function() {
                        status.style.display = 'none';
                    }, 5000);
                });
            }
        }, 1000);
    </script>

    <!-- App Initialization -->
    <script>
        // TV-safe app initialization
        (function() {
            try {
                // This will be replaced by Vite's app.js
                console.log('NewsApp initializing for', window.TV_BROWSER_TYPE || 'standard', 'browser');
            } catch (error) {
                console.error('App initialization error:', error);
                document.getElementById('app').innerHTML = '<div style="text-align:center;padding:50px;font-size:24px;">Error loading News App. Please refresh the page.</div>';
            }
        })();
    </script>
</body>
</html>
