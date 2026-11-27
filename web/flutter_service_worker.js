// Limpador (26/11): o app não usa mais service worker. Quem ainda tem o antigo instalado recebe este,
// que apaga o cache velho, se desregistra e recarrega a página na versão nova.
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (e) => e.waitUntil((async () => {
  for (const k of await caches.keys()) { if (k.startsWith('flutter')) await caches.delete(k); }
  await self.registration.unregister();
  for (const c of await self.clients.matchAll({ type: 'window' })) c.navigate(c.url);
})()));
