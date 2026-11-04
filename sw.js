const CACHE='tiny-notes-v1';
self.addEventListener('install',event=>{event.waitUntil(caches.open(CACHE).then(c=>c.addAll(['./','./index.html'])).then(()=>self.skipWaiting()))});
self.addEventListener('activate',event=>{event.waitUntil(self.clients.claim())});
self.addEventListener('fetch',event=>{
  if(event.request.method!=='GET')return;
  const u=new URL(event.request.url);
  if(u.origin!==self.location.origin){
    if(u.hostname==='cdn.jsdelivr.net')event.respondWith(caches.open(CACHE).then(async c=>{const cached=await c.match(event.request);if(cached)return cached;const response=await fetch(event.request);if(response.ok||response.type==='opaque')c.put(event.request,response.clone());return response}));
    return;
  }
  event.respondWith(fetch(event.request).then(r=>{if(r.ok){const copy=r.clone();caches.open(CACHE).then(c=>c.put(event.request,copy))}return r}).catch(()=>caches.match(event.request)));
});
