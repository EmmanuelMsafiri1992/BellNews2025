<!DOCTYPE html>
<html lang="{{ str_replace('_', '-', app()->getLocale()) }}" dir="{{ (app()->getLocale() === 'he' || app()->getLocale() === 'ar') ? 'rtl' : 'ltr' }}">

<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="viewport-fit=cover, width=device-width, initial-scale=1.0, minimum-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <title>WeARE - TV COMPATIBLE</title>

    <meta name="csrf-token" content="{{ csrf_token() }}">

    {{-- Preconnect to Google Fonts for faster loading --}}
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    {{-- Using Inter font for better readability across devices, with fallbacks --}}
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap" rel="stylesheet">
    
    {{-- Legacy TV styles for older Smart TVs (2015-2017) --}}
    <link href="{{ asset('css/legacy-tv-styles.css') }}" rel="stylesheet">

    {{-- CRITICAL: Load legacy TV polyfills FIRST for oldest TVs --}}
    <script src="{{ asset('js/legacy-tv-polyfills.js') }}"></script>
    
    {{-- CRITICAL: Load localhost override BEFORE Vue.js app --}}
    <script src="{{ asset('js/localhost-fix.js') }}"></script>
    
    {{-- Direct fallback script for maximum TV compatibility --}}
    <script src="{{ asset('js/app-fallback.js') }}"></script>

    {{-- Removed old Nunito font link to use Inter, or you can keep both if needed --}}
    {{-- <link href="https://fonts.googleapis.com/css?family=Nunito" rel="stylesheet"> --}}
</head>

{{-- Ensure body takes full height and uses Inter font --}}
<body class="bg-white font-inter antialiased min-h-screen flex flex-col">

    {{-- Blade conditional logic to decide if Vue app should load --}}
    @php
        // Define URL paths where the Vue app should NOT be mounted.
        // These are typically Blade-only pages (authentication, admin panels).
        $noVuePaths = [
            'login',
            'register',
            'password/*', // Covers all password reset routes
            'admin*', // Covers all routes under the '/admin' prefix
        ];

        $loadVueApp = true; // Assume Vue app should load by default

        foreach ($noVuePaths as $path) {
            if (request()->is($path)) {
                $loadVueApp = false;
                break;
            }
        }
    @endphp

    <!-- Debug: $loadVueApp = {{ $loadVueApp ? 'true' : 'false' }} -->
    @if ($loadVueApp)
        {{-- Load the restored original Vue.js application --}}
        @include('news.app')
    @else
        {{-- For authentication pages, and other dedicated Blade-only pages (like admin panel list/forms),
             only render the content specified in their respective Blade files.
             The <div id="app-blade-content"> is optional, but helps differentiate. --}}
        <div id="app-blade-content" class="min-h-screen flex-1">
            @yield('content')
        </div>

        {{-- Load only CSS for Blade-only pages --}}
        @vite('resources/css/app.css')
    @endif

    {{-- Universal fallback script for TV compatibility --}}
    <script>
        // Direct content injection for TV compatibility
        (function() {
            function loadContent() {
                var appDiv = document.getElementById("app");
                if (!appDiv || appDiv.innerHTML.trim() !== "") return;
                
                var content = document.createElement("div");
                content.className = "min-h-screen bg-gray-100 py-6 flex flex-col justify-center sm:py-12";
                content.innerHTML = '<div class="relative py-3 sm:max-w-xl sm:mx-auto"><div class="absolute inset-0 bg-gradient-to-r from-blue-400 to-blue-600 shadow-lg transform -skew-y-6 sm:skew-y-0 sm:-rotate-6 sm:rounded-3xl"></div><div class="relative px-4 py-10 bg-white shadow-lg sm:rounded-3xl sm:p-20"><div class="max-w-md mx-auto"><div class="divide-y divide-gray-200"><div class="py-8 text-base leading-6 space-y-4 text-gray-700 sm:text-lg sm:leading-7"><h1 class="text-3xl font-bold text-gray-900 mb-6 text-center">WeARE News App</h1><p class="text-center mb-6">Welcome to your news application optimized for TV browsers and all devices.</p><div class="bg-green-50 border border-green-200 rounded-lg p-4 mb-6"><h3 class="text-green-800 font-semibold mb-2">✅ Features:</h3><ul class="text-green-700 space-y-1"><li>• TV Browser Compatible</li><li>• Legacy Device Support</li><li>• Remote Control Navigation</li><li>• Multi-Platform Ready</li></ul></div></div><div class="pt-6 text-base leading-6 font-bold sm:text-lg sm:leading-7"><div class="space-y-4"><button onclick="window.location.href=\'/login\'" class="w-full bg-blue-500 hover:bg-blue-700 text-white font-bold py-4 px-6 rounded-lg text-lg">🔐 Login</button><button onclick="window.location.href=\'/admin/dashboard\'" class="w-full bg-green-500 hover:bg-green-700 text-white font-bold py-4 px-6 rounded-lg text-lg">🛠️ Admin</button><button onclick="window.location.href=\'/admin/news\'" class="w-full bg-purple-500 hover:bg-purple-700 text-white font-bold py-4 px-6 rounded-lg text-lg">📰 News</button></div><div class="mt-6 p-4 bg-gray-50 rounded-lg"><p class="text-center text-sm text-gray-600">Status: <span class="text-green-500 font-semibold">✅ Ready</span></p></div></div></div></div></div></div>';
                appDiv.appendChild(content);
                console.log("Content loaded successfully!");
            }
            
            if (document.readyState === "loading") {
                document.addEventListener("DOMContentLoaded", loadContent);
            } else {
                loadContent();
            }
        })();
    </script>

</body>

</html>
