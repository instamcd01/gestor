import 'package:gestor/models/cliente.dart';
import 'package:gestor/models/produto.dart';

class Venda {
  final String idVenda;
  final Cliente cliente;
  final DateTime dataVenda;

  final double subtotal;          // valor dos produtos antes de frete/desconto
  final double desconto;          // desconto aplicado
  final double saldoUsado;
  final double valorEntrega;      // frete efetivo
  final String entregaSelecionada; // faixa de entrega ex: '0-2km'

  final double valorTotal;        // subtotal - desconto + frete
  final double valorPago;         // quanto o cliente pagou
  final double troco;             // se pagamento em dinheiro
  final String metodoPagamento;   // forma de pagamento

  final int totalItens;           // quantidade total de unidades
  final List<ItemVenda> itens;    // lista de produtos da venda

  final double custoTotal;        // soma do custo dos produtos
  final double lucroTotal;        // lucro líquido
  final String observacao;        // observações da venda
  final Map<String, double>? pagamentosDetalhados;

  Venda({
    required this.idVenda,
    required this.cliente,
    required this.dataVenda,
    required this.subtotal,
    required this.desconto,
    required this.saldoUsado,
    required this.valorEntrega,
    required this.entregaSelecionada,
    required this.valorTotal,
    required this.valorPago,
    required this.troco,
    required this.metodoPagamento,
    required this.totalItens,
    required this.itens,
    required this.custoTotal,
    required this.lucroTotal,
    this.observacao = '',
    this.pagamentosDetalhados,
  });
}


class ItemVenda {
  final Produto produto;
  final int quantidade;
  final double precoUnitario; // preço de venda aplicado no momento da venda

  ItemVenda({
    required this.produto,
    required this.quantidade,
    required this.precoUnitario,
  });

  // --- Getters calculados ---
  double get precoTotal => precoUnitario * quantidade;

  double get custoUnitario => produto.custo;

  double get custoTotal => produto.custo * quantidade;

  double get lucroUnitario => precoUnitario - produto.custo;

  double get lucroTotal => (precoUnitario - produto.custo) * quantidade;
}





