import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { VitePWA } from 'vite-plugin-pwa';

// The build is served by the rewritten Dart web server (lib/services/web)
// from assets/web_app. `base: './'` keeps asset URLs relative so it works
// behind any mount (localhost, Tailscale, ngrok). In dev, /api and /ws are
// proxied to the running Flutter desktop app's web server on :8085.
export default defineConfig({
  base: './',
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      manifest: {
        name: 'Front Porch AI',
        short_name: 'Front Porch',
        description: 'AI character chat — Front Porch AI',
        theme_color: '#1f2937',
        background_color: '#0f172a',
        display: 'standalone',
        start_url: './',
        scope: './',
        icons: [
          { src: 'icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
          { src: 'icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
          { src: 'icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
          { src: 'icon.svg', sizes: 'any', type: 'image/svg+xml', purpose: 'any' },
        ],
      },
      workbox: {
        navigateFallback: 'index.html',
        globPatterns: ['**/*.{js,css,html,svg,png,woff2}'],
      },
    }),
  ],
  build: {
    outDir: '../assets/web_app',
    emptyOutDir: true,
  },
  server: {
    // Bind all interfaces + allow the Tailscale (.ts.net) host so the dev server
    // is reachable from a phone over Tailscale for live mobile preview. Dev-only;
    // does not affect the production build served by the Dart server.
    host: true,
    allowedHosts: ['localhost', '.ts.net', 'host.docker.internal'],
    port: 5173,
    proxy: {
      // The multiplexed stream connects to /api/ws and needs a real WebSocket
      // upgrade (ws:true). It MUST be listed before the generic /api rule (first
      // match wins) and must NOT changeOrigin: the Dart server enforces a
      // same-origin WebSocket allowlist, so the forwarded Host has to stay equal
      // to the browser's Origin host (preserved here) or the upgrade is rejected
      // 403. Without this, live token streaming silently never connects and the
      // chat only updates after leaving and re-entering the conversation.
      '/api/ws': { target: 'ws://localhost:8085', ws: true },
      '/api': { target: 'http://localhost:8085', changeOrigin: true },
    },
  },
  // `vite preview` serves the real production build (minified, no HMR) for a
  // fast, deterministic mobile preview over Tailscale — a refresh always shows
  // the latest rebuild. Same proxy as dev so /api + /api/ws hit the desktop app.
  preview: {
    host: true,
    allowedHosts: ['localhost', '.ts.net', 'host.docker.internal'],
    port: 5173,
    proxy: {
      // The multiplexed stream connects to /api/ws and needs a real WebSocket
      // upgrade (ws:true). It MUST be listed before the generic /api rule (first
      // match wins) and must NOT changeOrigin: the Dart server enforces a
      // same-origin WebSocket allowlist, so the forwarded Host has to stay equal
      // to the browser's Origin host (preserved here) or the upgrade is rejected
      // 403. Without this, live token streaming silently never connects and the
      // chat only updates after leaving and re-entering the conversation.
      '/api/ws': { target: 'ws://localhost:8085', ws: true },
      '/api': { target: 'http://localhost:8085', changeOrigin: true },
    },
  },
});
