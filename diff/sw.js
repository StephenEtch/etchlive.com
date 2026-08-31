/* Playback Track Diff — offline cache.
   The whole tool is one HTML file, so "offline" just means keeping that file
   and its icons. Nothing else is ever fetched, and no audio touches the network. */
const CACHE = 'playback-track-diff-v2';
const SHELL = ['./', './index.html', './manifest.json', './icon-32.png',
               './icon-192.png', './icon-512.png', './icon-maskable-512.png', './apple-touch-icon.png'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).catch(() => {}));
});

self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.filter(k => k !== CACHE).map(k => caches.delete(k)));
    await self.clients.claim();
  })());
});

self.addEventListener('message', (e) => { if (e.data === 'skipWaiting') self.skipWaiting(); });

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== self.location.origin) return;

  // The page itself: prefer the network so a redeploy lands, but never wait
  // long for it — a venue connection that half-works is worse than none.
  if (req.mode === 'navigate'){
    e.respondWith((async () => {
      try {
        const net = await Promise.race([
          fetch(req),
          new Promise((_, rej) => setTimeout(() => rej(new Error('slow')), 2500))
        ]);
        const c = await caches.open(CACHE);
        c.put('./index.html', net.clone());
        return net;
      } catch (err){
        return (await caches.match('./index.html')) || (await caches.match('./')) || Response.error();
      }
    })());
    return;
  }

  e.respondWith((async () => {
    const hit = await caches.match(req);
    if (hit) return hit;
    try {
      const net = await fetch(req);
      if (net && net.ok) (await caches.open(CACHE)).put(req, net.clone());
      return net;
    } catch (err){ return Response.error(); }
  })());
});
