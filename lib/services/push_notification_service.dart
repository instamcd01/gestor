import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../config/supabase_config.dart';
import '../firebase_options.dart';

/// Push (Firebase Cloud Messaging) — só Android por enquanto, ver
/// `DefaultFirebaseOptions`. O envio em si (quem manda o push quando uma
/// notificação é criada) é responsabilidade do trigger
/// `notificar_push_notificacao` no banco + workflow n8n `notificacao-push`;
/// esse serviço só cuida do lado do dispositivo (permissão + token).
class PushNotificationService {
  static bool _inicializado = false;

  static Future<void> inicializar() async {
    if (_inicializado || kIsWeb || !Platform.isAndroid) return;

    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      _inicializado = true;

      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      await _salvarToken();
      FirebaseMessaging.instance.onTokenRefresh.listen((_) => _salvarToken());
    } catch (e) {
      debugPrint('Erro ao inicializar notificações push: $e');
    }
  }

  static Future<void> _salvarToken() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      await supabase.from('usuarios').update({'fcm_token': token}).eq('id', userId);
    } catch (e) {
      debugPrint('Erro ao salvar token de notificação: $e');
    }
  }
}
