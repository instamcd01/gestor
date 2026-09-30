import 'package:flutter/material.dart';
import '../models/venda.dart';
import '../repositories/venda_repository.dart';

class HistoricoVendasProvider with ChangeNotifier {
  final VendaRepository _repository = VendaRepository();

  final List<Venda> _vendas = [];
  double saldoUsado = 0.0;
  bool _carregando = false;
  String? _erro;
  String? _empresaId;

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
    _empresaId = empresaId;
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
    notifyListeners();

    try {
      final vendasCarregadas = await _repository.listar(desde: _carregadoDesde);
      _vendas
        ..clear()
        ..addAll(vendasCarregadas);
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
  /// ver VendaRepository.cancelar) e recarrega a lista pra refletir o
  /// novo status.
  Future<void> cancelarVenda(String idVenda, {String? motivoCodigo, String? motivoDescricao}) async {
    await _repository.cancelar(idVenda, motivoCodigo: motivoCodigo, motivoDescricao: motivoDescricao);
    await carregarVendas();
  }

  /// Estorna o pagamento online (Mercado Pago) e cancela a venda —
  /// ver VendaRepository.estornarPagamentoOnline.
  Future<void> estornarPagamentoOnline(String idVenda) async {
    await _repository.estornarPagamentoOnline(idVenda);
    await carregarVendas();
  }

  /// Avança um pedido pro próximo status do ciclo de vida (ver
  /// `Venda.proximoStatus`) — usado pela Fila de Pedidos.
  Future<void> avancarStatusPedido(String idVenda, String novoStatus) async {
    await _repository.avancarStatus(idVenda, novoStatus);
    await carregarVendas();
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
    await carregarVendas();
  }
}
