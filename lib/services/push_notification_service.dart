import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config/supabase_config.dart';
import '../firebase_options.dart';
import '../models/notificacao.dart';
import '../providers/notificacao_provider.dart';

/// Push (Firebase Cloud Messaging) — só Android por enquanto, ver
/// `DefaultFirebaseOptions`. O envio em si (quem manda o push quando uma
/// notificação é criada) é responsabilidade do trigger
/// `notificar_push_notificacao` no banco + workflow n8n `notificacao-push`;
/// esse serviço só cuida do lado do dispositivo (permissão + token).
///
/// Com o app em segundo plano/fechado, o Android já mostra o push sozinho
/// (canal `notificacoes_padrao`, criado nativo em `MainActivity`, com som
/// padrão do aparelho). Só falta cobertura pro app aberto: o FCM não avisa
/// nada sozinho nesse caso, por isso o listener `onMessage` abaixo, que
/// toca som/vibra manualmente (via `MainActivity`) — por categoria, conforme
/// `NotificacaoProvider.alertaHabilitado` (tela Configurações > Notificações).
class PushNotificationService {
  static bool _inicializado = false;
  static const _canalNativo = MethodChannel('gestor/notificacao_alerta');

  static Future<void> inicializar(NotificacaoProvider preferencias) async {
    if (_inicializado || kIsWeb || !Platform.isAndroid) return;

    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      _inicializado = true;

      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      await _salvarToken();
      FirebaseMessaging.instance.onTokenRefresh.listen((_) => _salvarToken());
      FirebaseMessaging.onMessage.listen((mensagem) => _alertarPrimeiroPlano(mensagem, preferencias));
    } catch (e) {
      debugPrint('Erro ao inicializar notificações push: $e');
    }
  }

  static Future<void> _alertarPrimeiroPlano(RemoteMessage mensagem, NotificacaoProvider preferencias) async {
    final tipo = mensagem.data['tipo'] as String?;
    if (tipo == null || tipo.isEmpty) return;

    try {
      if (preferencias.alertaHabilitado(tipo, PreferenciaAlerta.som)) {
        await _canalNativo.invokeMethod('tocarSom');
      }
      if (preferencias.alertaHabilitado(tipo, PreferenciaAlerta.vibracao)) {
        await _canalNativo.invokeMethod('vibrar');
      }
    } catch (e) {
      debugPrint('Erro ao alertar em primeiro plano: $e');
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
