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

  List<Venda> get vendas => _vendas;
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
      final vendasCarregadas = await _repository.listar();
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

  /// Mantido pelo nome antigo por compatibilidade com telas existentes.
  Future<void> carregarVendasDoFirestore() async {
    await carregarVendas();
  }

  /// Cancela a venda no banco (estorno de estoque/saldo/métricas incluso,
  /// ver VendaRepository.cancelar) e recarrega a lista pra refletir o
  /// novo status.
  Future<void> cancelarVenda(String idVenda) async {
    await _repository.cancelar(idVenda);
    await carregarVendas();
  }

  /// Avança um pedido pro próximo status do ciclo de vida (ver
  /// `Venda.proximoStatus`) — usado pela Fila de Pedidos.
  Future<void> avancarStatusPedido(String idVenda, String novoStatus) async {
    await _repository.avancarStatus(idVenda, novoStatus);
    await carregarVendas();
  }
}
