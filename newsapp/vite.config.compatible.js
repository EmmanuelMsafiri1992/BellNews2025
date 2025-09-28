import { defineConfig } from 'vite';
import laravel from 'laravel-vite-plugin';
import vue from '@vitejs/plugin-vue';
import legacy from '@vitejs/plugin-legacy';
import os from 'os';

function getLocalIp() {
  const interfaces = os.networkInterfaces();
  for (const name of Object.keys(interfaces)) {
    for (const iface of interfaces[name]) {
      if (iface.family === 'IPv4' && !iface.internal) {
        return iface.address;
      }
    }
  }
  return 'localhost';
}

export default defineConfig({
  plugins: [
    laravel({
      input: [
        'resources/css/app.css',
        'resources/js/app.js',
      ],
      refresh: true,
    }),
    vue(),
    legacy({
      targets: [
        'defaults',
        'ie >= 11',
        'chrome >= 30',
        'safari >= 8',
        'edge >= 12',
        'firefox >= 30',
        'samsung >= 4',
        'opera >= 20',
        'android >= 4.1',
        'ios_saf >= 8',
        '> 0.1%',
        'not dead',
        'not op_mini all'
      ],
      additionalLegacyPolyfills: [
        'regenerator-runtime/runtime',
        'core-js/es/array/includes',
        'core-js/es/array/find',
        'core-js/es/promise',
        'core-js/es/object/assign'
      ],
      renderLegacyChunks: true,
    }),
  ],
  css: {
    postcss: './postcss.config.js',
  },
  server: {
    host: '0.0.0.0',
    port: 5173,
    hmr: {
      host: getLocalIp(),
      clientPort: 5173,
    },
  },
  build: {
    target: 'es5',
    minify: true,
    cssCodeSplit: true,
    sourcemap: false,
  }
});