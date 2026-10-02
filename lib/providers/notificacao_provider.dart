import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/notificacao.dart';
import '../repositories/notificacao_repository.dart';

/// A leitura/exclusão de notificações não precisa do empresaId — o RLS já
/// filtra pela empresa do usuário logado. Só as preferências e a retenção
/// (`empresas.preferencias_notificacao`/`retencao_notificacoes_dias`)
/// precisam saber o empresaId, pois leem/escrevem direto na tabela `empresas`.
class NotificacaoProvider with ChangeNotifier {
  final NotificacaoRepository _repository = NotificacaoRepository();

  String? _empresaId;
  List<Notificacao> _notificacoes = [];
  bool _carregando = false;
  String? _erro;
  Map<String, bool> _preferencias = {};
  int _retencaoDias = 30;
  RealtimeChannel? _canal;
  final _novas = StreamController<Notificacao>.broadcast();

  /// Notificações que chegaram pelo Realtime com o app aberto — usado pelo
  /// aviso do desktop (`NotificacaoDesktopService`), já que o push (FCM)
  /// só existe no Android.
  Stream<Notificacao> get novas => _novas.stream;

  List<Notificacao> get notificacoes => _notificacoes;
  bool get carregando => _carregando;
  String? get erro => _erro;
  int get totalNaoLidas => _notificacoes.where((n) => !n.lida).length;
  int get retencaoDias => _retencaoDias;
  bool get temLidas => _notificacoes.any((n) => n.lida);

  /// Categorias ausentes do jsonb (empresa nunca mexeu na preferência, ou
  /// erro ao carregar) contam como habilitadas — nunca silencia por engano.
  bool habilitado(String chave) => _preferencias[chave] ?? true;

  /// Som/vibração são por categoria e, ao contrário de [habilitado], vêm
  /// desligados por padrão pra toda categoria — exceto "novo pedido" e
  /// "erro no site" (esta migrada do alerta de WhatsApp, que sempre tocava
  /// som; sem esse default, viraria uma notificação silenciosa por engano).
  /// Sem esse default diferente, todo evento (estoque, despesa, avaliação...)
  /// tocaria som sozinho na primeira vez que o app rodasse essa versão.
  bool alertaHabilitado(String categoria, String tipoAlerta) {
    final chave = PreferenciaAlerta.chave(categoria, tipoAlerta);
    return _preferencias[chave] ??
        (categoria == TipoNotificacao.novoPedido || categoria == TipoNotificacao.erroSistema);
  }

  int naoLidasPorEntidade(String entidadeTipo) =>
      _notificacoes.where((n) => !n.lida && n.entidadeTipo == entidadeTipo).length;

  Future<void> carregar() async {
    _carregando = true;
    _erro = null;
    notifyListeners();

    try {
      _notificacoes = await _repository.listar();
    } catch (e) {
      _erro = 'Erro ao carregar notificações: $e';
      debugPrint(_erro);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> marcarComoLida(String id) async {
    final index = _notificacoes.indexWhere((n) => n.id == id);
    if (index == -1 || _notificacoes[index].lida) return;

    await _repository.marcarComoLida(id);
    final atual = _notificacoes[index];
    _notificacoes[index] = Notificacao(
      id: atual.id,
      tipo: atual.tipo,
      titulo: atual.titulo,
      mensagem: atual.mensagem,
      entidadeTipo: atual.entidadeTipo,
      entidadeId: atual.entidadeId,
      lida: true,
      createdAt: atual.createdAt,
    );
    notifyListeners();
  }

  Future<void> marcarTodasComoLidas() async {
    await _repository.marcarTodasComoLidas();
    await carregar();
  }

  /// Remove localmente antes de confirmar no banco — a lista não deve
  /// esperar a viagem de rede pra sumir o item que acabou de ser descartado
  /// (swipe-to-dismiss). Se falhar, recarrega pra restaurar o estado real.
  Future<void> excluir(String id) async {
    final removida = _notificacoes.firstWhere((n) => n.id == id, orElse: () => _notificacoes.first);
    _notificacoes = _notificacoes.where((n) => n.id != id).toList();
    notifyListeners();

    try {
      await _repository.excluir(id);
    } catch (e) {
      debugPrint('Erro ao excluir notificação: $e');
      _notificacoes = [..._notificacoes, removida]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      notifyListeners();
      rethrow;
    }
  }

  Future<void> excluirLidas() async {
    await _repository.excluirLidas();
    await carregar();
  }

  void definirEmpresa(String empresaId) {
    if (_empresaId == empresaId) return;
    _empresaId = empresaId;
    carregarPreferencias();
    carregarRetencaoDias();
    _ouvirNovas(empresaId);
  }

  /// Sem isso a lista só atualizava no login ou ao abrir a tela de
  /// Notificações. O RLS de `notificacoes` vale também pro Realtime, então
  /// tipos restritos (custo, despesa...) não chegam pra vendedor.
  void _ouvirNovas(String empresaId) {
    _canal?.unsubscribe();
    _canal = supabase
        .channel('notificacoes_$empresaId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notificacoes',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'empresa_id', value: empresaId),
          callback: (payload) {
            final nova = Notificacao.fromSupabase(payload.newRecord);
            if (_notificacoes.any((n) => n.id == nova.id)) return;
            _notificacoes = [nova, ..._notificacoes];
            notifyListeners();
            _novas.add(nova);
          },
        )
        .subscribe((status, _) {
          // Ao reconectar (rede caiu, PC dormiu), o que chegou nesse meio
          // tempo não vem pelo canal — recarrega a lista pra não perder.
          if (status == RealtimeSubscribeStatus.subscribed) carregar();
        });
  }

  @override
  void dispose() {
    _canal?.unsubscribe();
    _novas.close();
    super.dispose();
  }

  Future<void> carregarPreferencias() async {
    if (_empresaId == null) return;
    try {
      _preferencias = await _repository.buscarPreferencias(_empresaId!);
      notifyListeners();
    } catch (e) {
      debugPrint('Erro ao carregar preferências de notificação: $e');
      // Mantém tudo habilitado (valor padrão de `habilitado`) em caso de falha.
    }
  }

  Future<void> definirPreferencia(String chave, bool valor) async {
    _preferencias = {..._preferencias, chave: valor};
    notifyListeners();

    if (_empresaId == null) return;
    await _repository.salvarPreferencias(_empresaId!, _preferencias);
  }

  Future<void> carregarRetencaoDias() async {
    if (_empresaId == null) return;
    try {
      _retencaoDias = await _repository.buscarRetencaoDias(_empresaId!);
      notifyListeners();
    } catch (e) {
      debugPrint('Erro ao carregar retenção de notificações: $e');
      // Mantém o padrão de 30 dias em caso de falha.
    }
  }

  Future<void> definirRetencaoDias(int dias) async {
    _retencaoDias = dias;
    notifyListeners();

    if (_empresaId == null) return;
    await _repository.salvarRetencaoDias(_empresaId!, dias);
  }
}
