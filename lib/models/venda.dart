import 'package:gestor/models/cliente.dart';
import 'package:gestor/models/produto.dart';

/// Estados possíveis de um pedido/venda ao longo do ciclo de vida — a
/// coluna `pedidos.status` no banco é texto livre (sem CHECK constraint),
/// então esses valores são a convenção seguida pelo app inteiro.
class StatusPedido {
  static const pendente = 'pendente';
  static const preparando = 'preparando';
  static const saiuParaEntrega = 'saiu_para_entrega';
  static const entregue = 'entregue';
  static const cancelado = 'cancelado';

  static const emAndamento = [pendente, preparando, saiuParaEntrega];

  static String rotulo(String status) {
    switch (status) {
      case pendente:
        return 'Pendente';
      case preparando:
        return 'Em preparo';
      case saiuParaEntrega:
        return 'Saiu para entrega';
      case entregue:
        return 'Entregue';
      case cancelado:
        return 'Cancelada';
      default:
        return status;
    }
  }
}

class Venda {
  final String? idVenda;
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
  final String status;            // ver StatusPedido (espelha pedidos.status)
  final String canalVenda;        // 'loja_fisica', 'whatsapp', 'ifood', 'site', etc.

  Venda({
    this.idVenda,
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
    this.status = StatusPedido.entregue,
    this.canalVenda = 'loja_fisica',
  });

  bool get cancelada => status == StatusPedido.cancelado;
  bool get finalizada => status == StatusPedido.entregue;
  bool get emAndamento => StatusPedido.emAndamento.contains(status);
  bool get temEntrega => valorEntrega > 0 || entregaSelecionada.isNotEmpty;

  /// Próximo status no ciclo de vida (pula "saiu para entrega" quando o
  /// pedido é retirada/balcão, sem entrega). Retorna null se já estiver
  /// num estado final (entregue/cancelado).
  String? get proximoStatus {
    switch (status) {
      case StatusPedido.pendente:
        return StatusPedido.preparando;
      case StatusPedido.preparando:
        return temEntrega ? StatusPedido.saiuParaEntrega : StatusPedido.entregue;
      case StatusPedido.saiuParaEntrega:
        return StatusPedido.entregue;
      default:
        return null;
    }
  }
}


class ItemVenda {
  final Produto produto;
  final int quantidade;
  final double precoUnitario; // preço de venda aplicado no momento da venda

  // Custo do produto NO MOMENTO da venda (vem de itens_pedido.custo_unitario
  // ao reidratar do banco). Se não informado, cai pro custo atual do produto
  // — correto só enquanto a venda está sendo montada, nunca pra uma venda
  // já registrada, cujo custo histórico pode diferir do custo atual.
  final double? _custoUnitarioNoMomento;

  ItemVenda({
    required this.produto,
    required this.quantidade,
    required this.precoUnitario,
    double? custoUnitario,
  }) : _custoUnitarioNoMomento = custoUnitario;

  // --- Getters calculados ---
  double get precoTotal => precoUnitario * quantidade;

  double get custoUnitario => _custoUnitarioNoMomento ?? produto.custo;

  double get custoTotal => custoUnitario * quantidade;

  double get lucroUnitario => precoUnitario - custoUnitario;

  double get lucroTotal => (precoUnitario - custoUnitario) * quantidade;

  double get margemPercentual => precoUnitario > 0 ? (lucroUnitario / precoUnitario * 100) : 0.0;
}





