import 'package:flutter/material.dart';
import '../models/pedido_compra.dart';
import '../repositories/pedido_compra_repository.dart';

class PedidoCompraProvider with ChangeNotifier {
  final PedidoCompraRepository _repository = PedidoCompraRepository();

  List<PedidoCompra> _pedidos = [];
  List<SugestaoCompra> _sugestoes = [];
  bool _carregando = false;
  bool _carregandoSugestoes = false;
  String? _erro;
  String? _empresaId;

  List<PedidoCompra> get pedidos => _pedidos;
  List<SugestaoCompra> get sugestoes => _sugestoes;
  bool get carregando => _carregando;
  bool get carregandoSugestoes => _carregandoSugestoes;
  String? get erro => _erro;

  void definirEmpresa(String empresaId) {
    _empresaId = empresaId;
  }

  Future<void> carregar({StatusPedidoCompra? status}) async {
    _carregando = true;
    _erro = null;
    notifyListeners();

    try {
      _pedidos = await _repository.listar(status: status);
    } catch (e) {
      _erro = 'Erro ao carregar pedidos de compra: $e';
      debugPrint(_erro);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> carregarSugestoes({int diasAnalise = 30, int diasSeguranca = 7}) async {
    if (_empresaId == null) {
      throw StateError('Nenhuma empresa definida no PedidoCompraProvider ainda.');
    }
    _carregandoSugestoes = true;
    _erro = null;
    notifyListeners();

    try {
      _sugestoes = await _repository.buscarSugestoes(
        empresaId: _empresaId!,
        diasAnalise: diasAnalise,
        diasSeguranca: diasSeguranca,
      );
    } catch (e) {
      _erro = 'Erro ao calcular sugestões de compra: $e';
      debugPrint(_erro);
    } finally {
      _carregandoSugestoes = false;
      notifyListeners();
    }
  }

  Future<PedidoCompra> criarPedido({
    required PedidoCompra pedido,
    required List<ItemPedidoCompra> itens,
    String? criadoPor,
  }) async {
    if (_empresaId == null) {
      throw StateError('Nenhuma empresa definida no PedidoCompraProvider ainda.');
    }
    final novo = await _repository.criar(
      pedido: pedido,
      empresaId: _empresaId!,
      itens: itens,
      criadoPor: criadoPor,
    );
    _pedidos.insert(0, novo);
    notifyListeners();
    return novo;
  }

  Future<PedidoCompra> recarregarPedido(String pedidoId) async {
    final atualizado = await _repository.buscarPorId(pedidoId);
    final index = _pedidos.indexWhere((p) => p.id == pedidoId);
    if (index != -1) _pedidos[index] = atualizado;
    notifyListeners();
    return atualizado;
  }

  Future<void> atualizarCabecalho(PedidoCompra pedido) async {
    await _repository.atualizarCabecalho(pedido);
    await recarregarPedido(pedido.id!);
  }

  Future<void> substituirItens(String pedidoId, List<ItemPedidoCompra> itens) async {
    await _repository.substituirItens(pedidoId, itens);
    await recarregarPedido(pedidoId);
  }

  Future<void> marcarComoEnviado(String pedidoId) async {
    await _repository.atualizarStatus(
      pedidoId,
      StatusPedidoCompra.enviado,
      camposExtras: {'data_envio': DateTime.now().toIso8601String()},
    );
    await recarregarPedido(pedidoId);
  }

  /// Grava a conferência do espelho: quantidades confirmadas por item (já
  /// atualizadas via `substituirItens`/`atualizarItem` antes desta chamada)
  /// e os anexos, e avança o status pra `confirmado`.
  Future<void> confirmarConferencia(String pedidoId, {required List<AnexoEspelho> anexos}) async {
    await _repository.atualizarStatus(
      pedidoId,
      StatusPedidoCompra.confirmado,
      camposExtras: {
        'data_confirmacao': DateTime.now().toIso8601String(),
        'anexos_espelho': anexos.map((a) => a.toJson()).toList(),
      },
    );
    await recarregarPedido(pedidoId);
  }

  Future<void> marcarComoRecebido(String pedidoId) async {
    await _repository.atualizarStatus(
      pedidoId,
      StatusPedidoCompra.recebido,
      camposExtras: {'data_recebimento': DateTime.now().toIso8601String()},
    );
    await recarregarPedido(pedidoId);
  }

  Future<void> cancelar(String pedidoId) async {
    await _repository.atualizarStatus(pedidoId, StatusPedidoCompra.cancelado);
    await recarregarPedido(pedidoId);
  }
}
