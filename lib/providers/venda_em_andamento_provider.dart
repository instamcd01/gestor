import 'package:flutter/material.dart';
import '../models/venda.dart';
import '../models/cliente.dart';
import '../models/produto.dart';
import 'carrinho_provider.dart';

class VendaEmAndamentoProvider with ChangeNotifier {
  Cliente? cliente;
  final CarrinhoProvider carrinho;

  double valorPago = 0.0;
  double troco = 0.0;
  String metodoPagamento = '';
  String observacao = '';
  double saldoUsado = 0.0;

  VendaEmAndamentoProvider({required this.carrinho});

  // --- Totais calculados automaticamente ---
  double get subtotal => carrinho.subtotal;
  double get desconto => carrinho.desconto;
  double get valorEntrega => carrinho.valorEntregaCalculado;
  double get total => carrinho.totalCarrinho;

  double get custoTotal =>
      carrinho.itens.fold(0.0, (sum, item) => sum + (item.produto.custo * item.quantidade));

  double get lucroTotal => total - custoTotal;

  int get totalItens => carrinho.totalUnidades;

  // --- Lista de itens já no formato para Venda ---
  List<ItemVenda> get itensVenda => carrinho.itens.map((item) {
    final precoUnit = item.produto.precoPromocional ?? item.produto.preco;
    final custoUnit = item.produto.custo;
    final lucroUnit = precoUnit - custoUnit;

    return ItemVenda(
      produto: item.produto,
      quantidade: item.quantidade,
      precoUnitario: precoUnit,
      // precoTotal: precoUnit * item.quantidade,
      // custoUnitario: custoUnit,
      // custoTotal: custoUnit * item.quantidade,
      // lucroUnitario: lucroUnit,
      // lucroTotal: lucroUnit * item.quantidade,
    );
  }).toList();

  // --- Cria a venda finalizada ---
  Venda gerarVenda({required String idVenda}) {
    if (cliente == null) {
      throw Exception('Cliente não selecionado para a venda.');
    }

    return Venda(
      idVenda: idVenda,
      cliente: cliente!,
      dataVenda: DateTime.now(),
      subtotal: subtotal,
      desconto: desconto,
      valorEntrega: valorEntrega,
      entregaSelecionada: carrinho.entregaSelecionadaId,
      valorTotal: total,
      valorPago: valorPago,
      troco: troco,
      metodoPagamento: metodoPagamento,
      totalItens: totalItens,
      custoTotal: custoTotal,
      lucroTotal: lucroTotal,
      itens: itensVenda,
      observacao: observacao, saldoUsado: saldoUsado,
    );
  }

  // --- Resetar venda para iniciar nova ---
  void resetarVenda() {
    cliente = null;
    valorPago = 0.0;
    troco = 0.0;
    metodoPagamento = '';
    observacao = '';
    carrinho.limparCarrinho();
    notifyListeners();
  }

  // --- Atualizações de estado ---
  void atualizarCliente(Cliente c) {
    cliente = c;
    notifyListeners();
  }

  void atualizarPagamento({required double pago, required String metodo}) {
    valorPago = pago;
    metodoPagamento = metodo;
    troco = pago - total;
    notifyListeners();
  }

  void atualizarObservacao(String obs) {
    observacao = obs;
    notifyListeners();
  }
}
