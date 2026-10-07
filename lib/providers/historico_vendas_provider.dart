import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';
import '../models/venda.dart';
import '../repositories/venda_repository.dart';

class HistoricoVendasProvider with ChangeNotifier {
  final VendaRepository _repository = VendaRepository();

  final List<Venda> _vendas = [];
  double saldoUsado = 0.0;
  bool _carregando = false;
  bool _atualizandoFila = false;
  String? _erro;
  String? _empresaId;

  RealtimeChannel? _canal;
  Timer? _debounceAlteracoes;
  final Set<String> _idsAlterados = {};
  final Set<String> _idsAlteradosDuranteCarga = {};

  /// Início da janela de vendas já carregada (null = histórico inteiro).
  /// Padrão: início do mês anterior — cobre hoje/semana/mês atual/mês
  /// passado, os períodos padrão das telas. Tela que precisa de período
  /// mais antigo chama [garantirPeriodo]; pedidos em andamento vêm sempre,
  /// de qualquer data (ver `VendaRepository.listar`).
  DateTime? _carregadoDesde = _inicioPadrao();

  static DateTime _inicioPadrao() {
    final hoje = DateTime.now();
    return DateTime(hoje.year, hoje.month - 1, 1);
  }

  List<Venda> get vendas => _vendas;
  DateTime? get carregadoDesde => _carregadoDesde;
  bool get carregouTudo => _carregadoDesde == null;
  bool get carregando => _carregando;
  bool get atualizandoFila => _atualizandoFila;
  String? get erro => _erro;

  /// Pedidos ainda em andamento (pendente/preparando/saiu para entrega),
  /// de qualquer canal — usado pela Fila de Pedidos. Mais antigos primeiro
  /// (fila é FIFO).
  List<Venda> get pedidosAtivos {
    final ativos = _vendas.where((v) => v.emAndamento).toList();
    ativos.sort((a, b) => a.dataVenda.compareTo(b.dataVenda));
    return ativos;
  }

  /// Chamado uma vez pelo AuthGate assim que sabemos a empresa do usuário
  /// logado — necessário pra registrar novas vendas (empresa_id é obrigatório).
  void definirEmpresa(String empresaId) {
    if (_empresaId == empresaId) return;
    _empresaId = empresaId;
    _ouvirPedidos(empresaId);
  }

  /// Sem isso a Fila só via pedido novo (ou mudança de status feita em
  /// outro aparelho/pelo site/iFood) ao recarregar a janela inteira de
  /// vendas — centenas de pedidos com itens e produtos completos, segundos
  /// de espera — enquanto a notificação do mesmo pedido já tinha chegado
  /// em tempo real. O RLS de `pedidos` vale também pro Realtime.
  void _ouvirPedidos(String empresaId) {
    _canal?.unsubscribe();
    _canal = supabase
        .channel('pedidos_$empresaId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'pedidos',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'empresa_id', value: empresaId),
          callback: (payload) {
            final id = (payload.newRecord['id'] ?? payload.oldRecord['id'])?.toString();
            if (id == null) return;
            _idsAlterados.add(id);
            if (_carregando) _idsAlteradosDuranteCarga.add(id);
            // Os itens do pedido são gravados logo depois do INSERT do
            // pedido, e um mesmo pedido costuma receber várias alterações em
            // sequência — espera assentar e busca tudo de uma vez.
            _debounceAlteracoes?.cancel();
            _debounceAlteracoes = Timer(const Duration(milliseconds: 1500), _aplicarAlteracoes);
          },
        )
        .subscribe((status, _) {
          // Ao reconectar (rede caiu, PC dormiu), o que mudou nesse meio
          // tempo não vem pelo canal — atualiza a fila pra não perder.
          if (status == RealtimeSubscribeStatus.subscribed && _vendas.isNotEmpty) atualizarFila();
        });
  }

  Future<void> _aplicarAlteracoes() async {
    if (_idsAlterados.isEmpty) return;
    final ids = _idsAlterados.toList();
    _idsAlterados.clear();
    try {
      await _recarregarPedidos(ids);
    } catch (e) {
      debugPrint('Erro ao atualizar pedidos alterados: $e');
    }
  }

  /// Busca só esses pedidos e substitui/insere/remove na lista em memória.
  Future<void> _recarregarPedidos(List<String> ids) async {
    final atualizados = await _repository.buscarPorIds(ids);
    _mesclar(atualizados, idsConsultados: ids);
    notifyListeners();
  }

  /// Única lista de vendas do app — tempo real e atualização da Fila só
  /// mexem nos pedidos consultados, nunca criam outra cópia. Id consultado
  /// que não voltou foi excluído; pedido fora da janela carregada (antigo e
  /// já encerrado) não entra, igual à carga completa.
  void _mesclar(List<Venda> atualizados, {required Iterable<String> idsConsultados}) {
    final porId = {for (final v in atualizados) if (v.idVenda != null) v.idVenda!: v};
    _vendas.removeWhere((v) => v.idVenda != null && idsConsultados.contains(v.idVenda) && !porId.containsKey(v.idVenda));
    for (final venda in porId.values) {
      final indice = _vendas.indexWhere((v) => v.idVenda == venda.idVenda);
      if (indice >= 0) {
        _vendas[indice] = venda;
      } else if (_dentroDaJanela(venda)) {
        _vendas.add(venda);
      }
    }
    _vendas.sort((a, b) => b.dataVenda.compareTo(a.dataVenda));
  }

  bool _dentroDaJanela(Venda venda) {
    final desde = _carregadoDesde;
    return desde == null || !venda.dataVenda.isBefore(desde) || venda.emAndamento || venda.aguardandoPagamento;
  }

  /// Atualização leve pra Fila de Pedidos: só pedidos em andamento/
  /// aguardando pagamento e os de hoje (o que a Fila mostra), mais os que
  /// estavam em andamento na memória e podem ter sido encerrados em outro
  /// lugar — em vez de recarregar a janela inteira de vendas.
  Future<void> atualizarFila() async {
    if (_atualizandoFila) return;
    _atualizandoFila = true;
    notifyListeners();
    try {
      final agora = DateTime.now();
      final recentes = await _repository.listar(desde: DateTime(agora.year, agora.month, agora.day));
      final idsRecentes = {for (final v in recentes) v.idVenda};
      final idsAbertosForaDaLista = _vendas
          .where((v) => (v.emAndamento || v.aguardandoPagamento) && v.idVenda != null && !idsRecentes.contains(v.idVenda))
          .map((v) => v.idVenda!)
          .toList();
      final encerrados = await _repository.buscarPorIds(idsAbertosForaDaLista);
      _mesclar(
        [...recentes, ...encerrados],
        idsConsultados: [...recentes.map((v) => v.idVenda).whereType<String>(), ...idsAbertosForaDaLista],
      );
      _erro = null;
    } catch (e) {
      _erro = 'Erro ao carregar vendas: $e';
      debugPrint(_erro);
    } finally {
      _atualizandoFila = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _canal?.unsubscribe();
    _debounceAlteracoes?.cancel();
    super.dispose();
  }

  void adicionarVenda(Venda venda) {
    _vendas.add(venda);
    notifyListeners();
  }

  /// Registra a venda no Supabase (pedidos + itens_pedido) e, se a venda
  /// usou saldo do cliente, já desconta o valor usado.
  Future<Venda> registrarVenda(Venda venda) async {
    if (_empresaId == null) {
      throw StateError('Nenhuma empresa definida no HistoricoVendasProvider ainda.');
    }

    final vendaRegistrada = await _repository.registrar(venda, empresaId: _empresaId!);

    if (venda.saldoUsado > 0 && venda.cliente.idCliente != null) {
      await _repository.descontarSaldoCliente(
        venda.cliente.idCliente!,
        venda.saldoUsado,
        pedidoId: vendaRegistrada.idVenda,
      );
    }

    _vendas.insert(0, vendaRegistrada);
    notifyListeners();
    return vendaRegistrada;
  }

  Future<void> carregarVendas() async {
    _carregando = true;
    _erro = null;
    _idsAlteradosDuranteCarga.clear();
    notifyListeners();

    try {
      final vendasCarregadas = await _repository.listar(desde: _carregadoDesde);
      _vendas
        ..clear()
        ..addAll(vendasCarregadas);
      // Alteração que chegou pelo tempo real enquanto a carga estava em
      // andamento pode ter sido sobrescrita pela foto (mais antiga) da carga.
      if (_idsAlteradosDuranteCarga.isNotEmpty) {
        _idsAlterados.addAll(_idsAlteradosDuranteCarga);
        _idsAlteradosDuranteCarga.clear();
        unawaited(_aplicarAlteracoes());
      }
    } catch (e) {
      _erro = 'Erro ao carregar vendas: $e';
      debugPrint(_erro);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  /// Garante que as vendas a partir de [inicio] estão carregadas — só vai
  /// ao banco se o período começa antes da janela atual (a janela só
  /// cresce; voltar pra um período curto não recarrega nada). [inicio]
  /// null = histórico inteiro. Devolve true se recarregou.
  Future<bool> garantirPeriodo(DateTime? inicio) async {
    final atual = _carregadoDesde;
    if (atual == null) return false;
    if (inicio != null) {
      final dia = DateTime(inicio.year, inicio.month, inicio.day);
      if (!dia.isBefore(atual)) return false;
      _carregadoDesde = dia;
    } else {
      _carregadoDesde = null;
    }
    await carregarVendas();
    return true;
  }

  /// Mantido pelo nome antigo por compatibilidade com telas existentes.
  Future<void> carregarVendasDoFirestore() async {
    await carregarVendas();
  }

  /// Cancela a venda no banco (estorno de estoque/saldo/métricas incluso,
  /// ver VendaRepository.cancelar) e atualiza esse pedido na lista.
  Future<void> cancelarVenda(String idVenda, {String? motivoCodigo, String? motivoDescricao}) async {
    await _repository.cancelar(idVenda, motivoCodigo: motivoCodigo, motivoDescricao: motivoDescricao);
    await _recarregarPedidos([idVenda]);
  }

  /// Estorna o pagamento online (Mercado Pago) e cancela a venda —
  /// ver VendaRepository.estornarPagamentoOnline.
  Future<void> estornarPagamentoOnline(String idVenda) async {
    await _repository.estornarPagamentoOnline(idVenda);
    await _recarregarPedidos([idVenda]);
  }

  /// Avança um pedido pro próximo status do ciclo de vida (ver
  /// `Venda.proximoStatus`) — usado pela Fila de Pedidos.
  Future<void> avancarStatusPedido(String idVenda, String novoStatus) async {
    await _repository.avancarStatus(idVenda, novoStatus);
    await _recarregarPedidos([idVenda]);
  }

  /// Troca forma de pagamento (e parcelas) de uma venda já registrada —
  /// ver `VendaRepository.alterarFormaPagamento`.
  Future<void> alterarFormaPagamento(
    String idVenda,
    String tipoPagamento, {
    int? parcelas,
    double? valorPago,
    double? troco,
  }) async {
    await _repository.alterarFormaPagamento(idVenda, tipoPagamento, parcelas: parcelas, valorPago: valorPago, troco: troco);
    await _recarregarPedidos([idVenda]);
  }
}
