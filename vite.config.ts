import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath, URL } from 'node:url';
import { VitePWA } from 'vite-plugin-pwa';

export default defineConfig({
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['favicon.svg'],
      manifest: {
        name: 'LedgerMind 2.0',
        short_name: 'LedgerMind',
        description: 'Offline-first transaction parser and analytics dashboard.',
        theme_color: '#0e7a6a',
        background_color: '#f5faf7',
        display: 'standalone',
        icons: [
          {
            src: 'favicon.svg',
            sizes: 'any',
            type: 'image/svg+xml'
          }
        ]
      }
    })
  ],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url))
    }
  },
  test: {
    environment: 'jsdom',
    include: ['src/**/*.test.ts']
  }
});
