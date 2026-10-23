import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../config/supabase_config.dart';
import '../firebase_options.dart';
import '../models/notificacao.dart';
import '../providers/notificacao_provider.dart';
import 'navegacao_notificacao.dart';

/// Push (Firebase Cloud Messaging) — Android e navegador (Gestor web, inclusive
/// iPhone com o site salvo na Tela de Início, iOS 16.4+). O envio em si (quem
/// manda o push quando uma notificação é criada) é responsabilidade do trigger
/// `notificar_push_notificacao` no banco + workflow n8n `notificacao-push`;
/// esse serviço só cuida do lado do dispositivo (permissão + token, gravado em
/// `usuario_dispositivos_push` — vários aparelhos por usuário).
///
/// Com o app em segundo plano/fechado, o Android já mostra o push sozinho
/// (canal `notificacoes_padrao`, criado nativo em `MainActivity`, com som
/// padrão do aparelho). Só falta cobertura pro app aberto: o FCM não avisa
/// nada sozinho nesse caso, por isso o listener `onMessage` abaixo, que
/// toca som/vibra manualmente (via `MainActivity`) — por categoria, conforme
/// `NotificacaoProvider.alertaHabilitado` (tela Configurações > Notificações).
/// No navegador, quem mostra com o app fechado é `web/firebase-messaging-sw.js`;
/// com ele aberto, a sininho já atualiza em tempo real.
///
/// Toque no aviso abre a tela dele (`abrirNotificacaoPorId`): no Android pelo
/// `notificacao_id` do `data` da mensagem; no navegador o link do push
/// (workflow n8n) traz `?notificacao=<id>`.
class PushNotificationService {
  static bool _inicializado = false;
  static const _canalNativo = MethodChannel('gestor/notificacao_alerta');

  static bool get _plataformaSuportada => kIsWeb ? DefaultFirebaseOptions.webConfigurado : Platform.isAndroid;

  static Future<void> inicializar(NotificacaoProvider preferencias) async {
    if (_inicializado || !_plataformaSuportada) return;

    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      _inicializado = true;

      if (kIsWeb) {
        final tocada = Uri.base.queryParameters['notificacao'];
        if (tocada != null && tocada.isNotEmpty) {
          // Tira o ?notificacao da barra pra um F5 não reabrir a mesma tela.
          SystemNavigator.routeInformationUpdated(uri: Uri.parse(Uri.base.path), replace: true);
          _abrirTocada(tocada, preferencias);
        }
        // No navegador a permissão só pode ser pedida num toque do usuário
        // (iPhone exige) — isso fica no botão de Configurações > Notificações.
        // Aqui só renova o token de quem já permitiu antes.
        final settings = await FirebaseMessaging.instance.getNotificationSettings();
        if (settings.authorizationStatus == AuthorizationStatus.authorized) await _salvarToken();
        return;
      }

      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      await _salvarToken();
      FirebaseMessaging.instance.onTokenRefresh.listen((_) => _salvarToken());
      FirebaseMessaging.onMessage.listen((mensagem) => _alertarPrimeiroPlano(mensagem, preferencias));
      FirebaseMessaging.onMessageOpenedApp.listen((mensagem) => _abrirTocada(mensagem.data['notificacao_id'], preferencias));
      final inicial = await FirebaseMessaging.instance.getInitialMessage();
      if (inicial != null) _abrirTocada(inicial.data['notificacao_id'], preferencias);
    } catch (e) {
      debugPrint('Erro ao inicializar notificações push: $e');
    }
  }

  /// Situação dos avisos neste navegador, pra tela de Configurações.
  static Future<EstadoPushNavegador> estadoNavegador() async {
    if (!kIsWeb || !DefaultFirebaseOptions.webConfigurado) return EstadoPushNavegador.indisponivel;
    try {
      if (!_inicializado) {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
        _inicializado = true;
      }
      // Falso no iPhone fora da Tela de Início e em navegador sem suporte.
      if (!await FirebaseMessaging.instance.isSupported()) return EstadoPushNavegador.naoSuportado;
      final settings = await FirebaseMessaging.instance.getNotificationSettings();
      return switch (settings.authorizationStatus) {
        AuthorizationStatus.authorized => EstadoPushNavegador.ativo,
        AuthorizationStatus.denied => EstadoPushNavegador.bloqueado,
        _ => EstadoPushNavegador.desativado,
      };
    } catch (e) {
      debugPrint('Erro ao checar notificações do navegador: $e');
      return EstadoPushNavegador.naoSuportado;
    }
  }

  /// Chamado no toque do botão "Ativar avisos neste aparelho" — o pedido de
  /// permissão precisa sair direto de um gesto do usuário.
  static Future<EstadoPushNavegador> ativarNoNavegador() async {
    if (!kIsWeb || !_inicializado) return estadoNavegador();
    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      if (settings.authorizationStatus != AuthorizationStatus.authorized) return estadoNavegador();
      await _salvarToken();
      return EstadoPushNavegador.ativo;
    } catch (e) {
      debugPrint('Erro ao ativar notificações no navegador: $e');
      return estadoNavegador();
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

  /// Espera a Home montar (o login acabou de terminar) antes de empilhar a tela.
  static void _abrirTocada(Object? id, NotificacaoProvider provider) {
    if (id is! String || id.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => abrirNotificacaoPorId(id, provider));
  }

  static Future<void> _salvarToken() async {
    if (supabase.auth.currentUser == null) return;

    try {
      final token = await FirebaseMessaging.instance.getToken(
        vapidKey: kIsWeb ? DefaultFirebaseOptions.webVapidKey : null,
      );
      if (token == null) return;
      await supabase.rpc('registrar_dispositivo_push', params: {
        'p_token': token,
        'p_plataforma': kIsWeb ? 'web' : 'android',
      });
    } catch (e) {
      debugPrint('Erro ao salvar token de notificação: $e');
    }
  }
}

enum EstadoPushNavegador {
  /// Não é navegador, ou o app Web do Firebase ainda não foi configurado.
  indisponivel,

  /// Navegador sem suporte — no iPhone, o site não está aberto pela Tela de Início.
  naoSuportado,
  desativado,
  bloqueado,
  ativo,
}
