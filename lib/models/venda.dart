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
  final int? numeroSequencial; // número curto/legível do pedido (ex: #123) — idVenda é o uuid interno
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
  final String? vendedorId;       // quem registrou a venda — null em pedidos de outras origens (iFood, site)

  // --- Campos específicos de marketplace (iFood), todos opcionais ---
  final String? marketplacePedidoId;    // marketplace_pedidos.id, precisa pra ações que gravam lá
  final String? tipoEntregaMarketplace; // DELIVERY/TAKEOUT/INDOOR (orderType da iFood)
  final String? codigoConfirmacaoStatus; // null/pendente/valido/invalido
  final String? codigoConfirmacaoErro;
  final double? rastreioLatitude;
  final double? rastreioLongitude;
  final DateTime? rastreioEtaEntrega;
  final DateTime? rastreioAtualizadoEm;
  final String? separacaoStatus; // null/separando/finalizada/erro
  final String? separacaoErro;
  final String? numeroExibicaoMarketplace; // "displayId" da iFood, número curto mostrado ao cliente
  final String? telefoneLocalizador; // código de discagem mascarada -- só funciona pra ligar, não WhatsApp
  final DateTime? telefoneLocalizadorExpiraEm;
  final String? codigoRetiradaExibicao; // pickupCode informativo da iFood (não é o código que o lojista digita)
  final String? statusPagamento; // 'pago' (já cobrado pelo marketplace) / 'pendente' (cobrar na entrega)
  final double? taxaServicoCliente; // taxa que a iFood cobra do cliente (receita da iFood, não da loja)
  final String? campanhaMarketplace; // nome da campanha/cupom aplicado (order.benefits[0].campaign.name)
  final String? cupomMarketplace; // id do cupom/campanha (order.benefits[0].campaign.id)
  final String? politicaSubstituicao; // order.picking.replacementOptions - se o cliente autoriza substituir item em falta
  final bool agendado;
  final DateTime? entregaPrevistaInicio; // início da janela prometida, só quando agendado
  final DateTime? entregaPrevistaFim; // fim da janela (agendado) ou estimativa única (pedido imediato)

  // Previsão calculada pela LOJA (zona escolhida no checkout + hora do
  // pedido) — independente do prazo que a iFood promete ao cliente dela
  // (os dois campos acima). Só existe pra pedidos com entrega feitos pelo
  // checkout do app (loja física/WhatsApp/site); pedidos iFood ainda não
  // têm endereço/coordenadas suficientes pra calcular a zona.
  final DateTime? previsaoEntregaInicio;
  final DateTime? previsaoEntregaFim;

  Venda({
    this.idVenda,
    this.numeroSequencial,
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
    this.vendedorId,
    this.marketplacePedidoId,
    this.tipoEntregaMarketplace,
    this.codigoConfirmacaoStatus,
    this.codigoConfirmacaoErro,
    this.rastreioLatitude,
    this.rastreioLongitude,
    this.rastreioEtaEntrega,
    this.rastreioAtualizadoEm,
    this.separacaoStatus,
    this.separacaoErro,
    this.numeroExibicaoMarketplace,
    this.telefoneLocalizador,
    this.telefoneLocalizadorExpiraEm,
    this.codigoRetiradaExibicao,
    this.statusPagamento,
    this.taxaServicoCliente,
    this.campanhaMarketplace,
    this.cupomMarketplace,
    this.politicaSubstituicao,
    this.agendado = false,
    this.entregaPrevistaInicio,
    this.entregaPrevistaFim,
    this.previsaoEntregaInicio,
    this.previsaoEntregaFim,
  });

  bool get pagoPeloMarketplace => statusPagamento == 'pago';

  bool get telefoneLocalizadorValido =>
      telefoneLocalizador != null &&
      telefoneLocalizador!.isNotEmpty &&
      (telefoneLocalizadorExpiraEm == null || telefoneLocalizadorExpiraEm!.isAfter(DateTime.now()));

  bool get cancelada => status == StatusPedido.cancelado;
  bool get finalizada => status == StatusPedido.entregue;
  bool get emAndamento => StatusPedido.emAndamento.contains(status);
  bool get temEntrega => valorEntrega > 0 || entregaSelecionada.isNotEmpty;
  bool get ehMarketplace => canalVenda == 'ifood';
  bool get temRastreio => rastreioLatitude != null && rastreioLongitude != null;

  /// true = cliente retira na loja (não precisa entrar em rota nenhuma).
  /// Não usa `temEntrega` de propósito — esse getter fica true mesmo pra
  /// retirada, porque `entregaSelecionada` guarda o texto "Retirada na
  /// Loja" (não vazio) nesse caso.
  bool get retirada {
    if (ehMarketplace) {
      return tipoEntregaMarketplace != null && tipoEntregaMarketplace != 'DELIVERY';
    }
    return entregaSelecionada.isEmpty || entregaSelecionada == 'Retirada na Loja';
  }

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
  final String? id; // itens_pedido.id -- só presente quando reidratado do banco
  final Produto produto;
  final int quantidade;
  final double precoUnitario; // preço de venda aplicado no momento da venda
  final String? observacaoCliente; // ex: "sem cebola" (order.items[].observations da iFood)

  // Custo do produto NO MOMENTO da venda (vem de itens_pedido.custo_unitario
  // ao reidratar do banco). Se não informado, cai pro custo atual do produto
  // — correto só enquanto a venda está sendo montada, nunca pra uma venda
  // já registrada, cujo custo histórico pode diferir do custo atual.
  final double? _custoUnitarioNoMomento;

  ItemVenda({
    this.id,
    required this.produto,
    required this.quantidade,
    required this.precoUnitario,
    this.observacaoCliente,
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





