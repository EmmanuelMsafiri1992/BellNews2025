<?php

return [
    /*
     * You can enable or disable CORS by setting this value to true or false.
     */
    'enabled' => env('CORS_ENABLED', true), // Ensure this is true

    /*
     * These are the paths to which CORS will be applied.
     * The default 'api/*' is crucial for your case.
     */
    'paths' => ['api/*', 'sanctum/csrf-cookie'],

    /*
     * The list of origins that can make CORS requests.
     * You will need to add your Vue.js frontend's URL here.
     */
    'allowed_origins' => [
        'http://localhost:8000', // Already likely present or implied for 127.0.0.1
        'http://192.168.33.3:8000',
    ],

    /*
     * The list of headers that are allowed to be sent with CORS requests.
     */
    'allowed_headers' => ['*'], // For development, '*' is often used initially

    /*
     * The list of methods that are allowed.
     */
    'allowed_methods' => ['*'], // For development, '*' is often used initially

    /*
     * The maximum age of the CORS preflight request (in seconds).
     */
    'max_age' => 0,

    /*
     * If true, the response will include a `Vary: Origin` header.
     */
    'supports_credentials' => false,
];
