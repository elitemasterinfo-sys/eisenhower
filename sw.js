// Service Worker for Eisenhower Matrix PWA
// App files open from the cache at once and are refreshed in the background (fast start on a slow VPN, works offline).
// Requests to other sites (Firebase, Telegram) are never touched.
const CACHE_NAME = 'eisenhower-pwa-v8';
const STATIC_ASSETS = [
  './',
  './index.html',
  './manifest.json',
  './icon-192.png',
  './icon-512.png',
  './qrcode.js',
  './fonts/vazirmatn-arabic.woff2',
  './fonts/vazirmatn-latin.woff2'
];

self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => {
      return cache.addAll(STATIC_ASSETS).catch(err => {
        console.warn('PWA Cache addAll warning:', err);
      });
    }).then(() => self.skipWaiting())
  );
});

self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys => {
      // Only this app's old caches: other apps on the same github.io domain keep theirs
      return Promise.all(
        keys.filter(k => k.startsWith('eisenhower-') && k !== CACHE_NAME).map(k => caches.delete(k))
      );
    }).then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', event => {
  const req = event.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== self.location.origin) return;
  // The shared-password file must always be the latest one, so it skips the cache
  if (new URL(req.url).pathname.endsWith('/vault.json')) return;

  event.respondWith(
    caches.open(CACHE_NAME).then(async cache => {
      const cached = await cache.match(req, { ignoreSearch: req.mode === 'navigate' });
      const fresh = fetch(req).then(res => {
        if (res && res.ok && res.type === 'basic') cache.put(req, res.clone());
        return res;
      }).catch(() => null);

      if (cached) {
        event.waitUntil(fresh);
        return cached;
      }
      const res = await fresh;
      if (res) return res;
      if (req.mode === 'navigate') {
        const shell = await cache.match('./index.html');
        if (shell) return shell;
      }
      return Response.error();
    })
  );
});
