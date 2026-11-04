const CACHE = 'tiny-notes-backend-v3';
const FILES = ['./', './index.html', './assets/styles.css', './assets/app.js', './assets/api.js', './assets/config.js', './assets/notes-store.js', './assets/sync.js'];
const allowed = new Set(FILES.map(path => new URL(path, self.registration.scope).href));
self.addEventListener('install', event => {
  event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(FILES)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', event => {
  event.waitUntil(caches.keys().then(keys => Promise.all(keys.filter(key => key.startsWith('tiny-notes-') && key !== CACHE).map(key => caches.delete(key)))).then(() => self.clients.claim()));
});
self.addEventListener('fetch', event => {
  // Never cache backend requests, login responses, sessions or log data.
  if (event.request.method !== 'GET' || !allowed.has(event.request.url)) return;
  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    try {
      const response = await fetch(event.request, { cache: 'no-cache' });
      if (response.ok) await cache.put(event.request, response.clone());
      return response;
    } catch {
      return await cache.match(event.request) || new Response('Offline', { status: 503 });
    }
  })());
});
