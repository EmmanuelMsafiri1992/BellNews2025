<?php

use Illuminate\Support\Facades\Route;
use Illuminate\Http\Request;
use App\Http\Controllers\NewsController;
use App\Http\Controllers\SettingController; // Ensure this controller exists and is imported

// Unified News API endpoint.
// It's generally better to use a named route and a specific API method like 'apiIndex'.
Route::get('/news', [NewsController::class, 'apiIndex'])->name('api.news.index');

// Public API endpoint to fetch global settings
Route::get('/settings', [SettingController::class, 'index'])->name('api.settings.index');

// Network information endpoint for IP detection
Route::get('/network-info', function (Request $request) {
    $serverIP = $request->server('HTTP_HOST');
    $clientIP = $request->ip();
    $serverName = $request->server('SERVER_NAME');
    $serverPort = $request->server('SERVER_PORT');
    $requestScheme = $request->isSecure() ? 'https' : 'http';
    
    // Get all possible server IPs
    $serverIPs = [];
    
    // Try to get the actual server IP
    $possibleIPs = [
        $request->server('HTTP_HOST'),
        $request->server('SERVER_NAME'),
        $request->server('LOCAL_ADDR'),
        $request->getHost(),
    ];
    
    foreach ($possibleIPs as $ip) {
        if ($ip && !in_array($ip, $serverIPs) && $ip !== 'localhost') {
            $serverIPs[] = $ip;
        }
    }
    
    // Get network interfaces (if available)
    $networkInterfaces = [];
    if (function_exists('exec') && !in_array('exec', explode(',', ini_get('disable_functions')))) {
        try {
            $output = [];
            exec('hostname -I 2>/dev/null || hostname', $output);
            if (!empty($output)) {
                $ips = explode(' ', trim($output[0]));
                foreach ($ips as $ip) {
                    $ip = trim($ip);
                    if (filter_var($ip, FILTER_VALIDATE_IP) && $ip !== '127.0.0.1') {
                        $networkInterfaces[] = $ip;
                    }
                }
            }
        } catch (Exception $e) {
            // Ignore exec errors
        }
    }
    
    return response()->json([
        'success' => true,
        'network_info' => [
            'server_ip' => $serverIP,
            'client_ip' => $clientIP,
            'server_name' => $serverName,
            'server_port' => $serverPort,
            'scheme' => $requestScheme,
            'server_ips' => array_unique($serverIPs),
            'network_interfaces' => array_unique($networkInterfaces),
            'base_url' => $requestScheme . '://' . ($serverIP ?: $serverName) . ':' . $serverPort,
            'timestamp' => now()->toISOString()
        ]
    ]);
})->name('api.network.info');

// Health check endpoint for IP detection
Route::get('/health', function (Request $request) {
    return response()->json([
        'status' => 'ok',
        'timestamp' => now()->toISOString(),
        'host' => $request->getHost(),
        'ip' => $request->ip(),
        'app' => 'NewsApp'
    ]);
})->name('api.health');

// Simple ping endpoint for connectivity testing
Route::get('/ping', function () {
    return response()->json(['pong' => true, 'timestamp' => time()]);
})->name('api.ping');
