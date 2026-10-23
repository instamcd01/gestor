import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';

import '../providers/notificacao_provider.dart';
import 'navegacao_notificacao.dart';

/// Aviso do sistema (toast do Windows) no desktop — equivalente ao push do
/// Android (`PushNotificationService`), que o FCM não cobre no desktop.
/// A fonte é o Realtime de `NotificacaoProvider.novas`, então só avisa com
/// o app aberto (minimizado serve). Clicar no aviso abre a tela dele
/// (`abrirNotificacao`), igual ao toque no push.
class NotificacaoDesktopService {
  static bool _inicializado = false;

  static Future<void> inicializar(NotificacaoProvider provider) async {
    if (_inicializado || kIsWeb || !(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) return;
    _inicializado = true;

    try {
      // No Windows o toast exige um atalho no Menu Iniciar com o ID do app;
      // requireCreate cria na primeira vez.
      await localNotifier.setup(appName: 'INARI', shortcutPolicy: ShortcutPolicy.requireCreate);
      provider.novas.listen((n) {
        final aviso = LocalNotification(title: n.titulo, body: n.mensagem);
        aviso.onClick = () async {
          await provider.marcarComoLida(n.id);
          await abrirNotificacao(tipo: n.tipo, entidadeId: n.entidadeId);
        };
        aviso.show();
      });
    } catch (e) {
      debugPrint('Erro ao inicializar notificações do desktop: $e');
    }
  }
}
