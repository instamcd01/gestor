// Avisos de oferta com o Kitsune fechado — inclusive no iPhone, com o app salvo
// na Tela de Início (iOS 16.4+). O SDK mostra a notificação sozinho (a mensagem
// traz `notification`); o toque abre o link de `webpush.fcm_options` (enviado
// pelo banco ao workflow n8n "Notificacao - Push FCM").
//
// Mesmos valores de `DefaultFirebaseOptions.web` em lib/firebase_options.dart.
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyAEVl5tYM0h-Pf4L5wyTNgo7CAXy4Zj52Y',
  appId: '1:380570421425:web:9c64ac6c91d09fa250fa90',
  messagingSenderId: '380570421425',
  projectId: 'deliverypet-6d0e7',
  authDomain: 'deliverypet-6d0e7.firebaseapp.com',
  storageBucket: 'deliverypet-6d0e7.firebasestorage.app',
});
firebase.messaging();

// Aviso mostrado pelo próprio app (Kitsune aberto, ver aviso_tela_web.dart): o
// toque abre/foca o Kitsune. Os avisos do FCM o SDK já trata (data.FCM_MSG).
self.addEventListener('notificationclick', (event) => {
  const data = event.notification.data;
  if (data && data.FCM_MSG) return;
  event.notification.close();
  event.waitUntil((async () => {
    const abertos = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
    for (const c of abertos) { if ('focus' in c) return c.focus(); }
    return self.clients.openWindow('/');
  })());
});
