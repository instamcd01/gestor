// Mostra os avisos da loja com o Gestor (web) fechado — inclusive no iPhone,
// com o site salvo na Tela de Início. O próprio SDK exibe a notificação quando
// a mensagem traz `notification`; o toque abre o link de `webpush.fcm_options`
// (definido no workflow n8n "Notificacao - Push FCM").
//
// Os valores abaixo são os mesmos de `DefaultFirebaseOptions.web` em
// lib/firebase_options.dart (públicos, do app Web no console do Firebase).
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');

const config = {
  apiKey: '',
  appId: '',
  messagingSenderId: '380570421425',
  projectId: 'deliverypet-6d0e7',
  authDomain: 'deliverypet-6d0e7.firebaseapp.com',
  storageBucket: 'deliverypet-6d0e7.firebasestorage.app',
};

if (config.appId) {
  firebase.initializeApp(config);
  firebase.messaging();
}
