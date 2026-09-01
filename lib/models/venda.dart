import 'package:gestor/models/cliente.dart';
import 'package:gestor/models/produto.dart';

/// Estados possíveis de um pedido/venda ao longo do ciclo de vida — a
/// coluna `pedidos.status` no banco é texto livre (sem CHECK constraint),
/// então esses valores são a convenção seguida pelo app inteiro.
class StatusPedido {
  static const aguardandoPagamento = 'aguardando_pagamento';
  static const pendente = 'pendente';
  static const preparando = 'preparando';
  static const saiuParaEntrega = 'saiu_para_entrega';
  static const entregue = 'entregue';
  static const cancelado = 'cancelado';

  static const emAndamento = [pendente, preparando, saiuParaEntrega];

  static String rotulo(String status) {
    switch (status) {
      case aguardandoPagamento:
        return 'Aguardando pagamento';
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
  final String? cupomId;          // cupons.id quando o desconto veio de um cupom (não de desconto manual)
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
  final String? motivoCancelamentoCodigo; // pedidos.motivo_cancelamento_codigo — só existe quando cancelada; ver Venda.origemCancelamento
  final String? motivoCancelamentoDescricao; // pedidos.motivo_cancelamento_descricao — texto pronto pra mostrar, quando presente

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
  final String? linkConfirmacaoEntrega; // handover_page_url da 99Food -- entregador/lojista abre pra confirmar com o cliente, sem código
  final String? statusPagamento; // 'pago' (já cobrado pelo marketplace) / 'pendente' (cobrar na entrega)
  final String? mercadoPagoPaymentTypeId; // credit_card/debit_card/bank_transfer — só em pagamento online do site (Mercado Pago)
  final int? mercadoPagoInstallments; // parcelas reais cobradas (diferente de "parcelas" informativas dos métodos na entrega)
  final String? mercadoPagoPaymentId; // id do pagamento na API do Mercado Pago — referência pra consultar/disputar no painel deles
  final String? mercadoPagoRefundId; // id do estorno na API do Mercado Pago, só existe se `estornarPagamentoOnline` já rodou
  final DateTime? mercadoPagoEstornadoEm;
  final double? mercadoPagoTaxa; // quanto o PRÓPRIO Mercado Pago descontou da loja (split direto na conta dela, não é comissão do Gestor)
  final double? custoEmbalagem; // pedidos.custo_embalagem_valor — calculado por calcular_custos_operacionais_pedido() a partir de empresas.custo_embalagem_padrao
  final double? taxaMaquininha; // pedidos.taxa_maquininha_valor — só cartão cobrado na entrega/loja física (não cobre Mercado Pago online nem marketplace)
  final double? custoEntregaReal; // pedidos.custo_entrega_valor — custo real de entrega própria (modo fixo/km configurado em empresas), null se retirada/modo ainda não suportado
  final double? taxaComissaoMarketplace; // marketplace_pedidos.taxa_comissao — comissão real cobrada pelo iFood/99Food, calculada por calcular_comissao_marketplace()
  final double? taxaGatewayMarketplace; // marketplace_pedidos.taxa_gateway — taxa de pagamento online do marketplace (ex: 3,5% do contrato do iFood), separada da comissão
  final double? taxaServicoCliente; // taxa que a iFood cobra do cliente (receita da iFood, não da loja)
  final String? campanhaMarketplace; // nome da campanha/cupom aplicado (order.benefits[0].campaign.name)
  final String? cupomMarketplace; // id do cupom/campanha (order.benefits[0].campaign.id)
  final String? politicaSubstituicao; // order.picking.replacementOptions - se o cliente autoriza substituir item em falta
  final String? entregadorTipo; // order.delivery.deliveredBy - MERCHANT (loja entrega) ou IFOOD (só aí existe rastreio)
  final bool agendado;
  final DateTime? entregaPrevistaInicio; // início da janela prometida, só quando agendado
  final DateTime? entregaPrevistaFim; // fim da janela (agendado) ou estimativa única (pedido imediato)

  // Previsão de entrega/retirada em previsaoEntregaInicio/Fim abaixo —
  // pra pedido imediato é calculada pela LOJA (zona de entrega + hora do
  // pedido); pra pedido com agendadoManualmente=true é a janela escolhida
  // explicitamente (pelo cliente no checkout do site, ou pelo vendedor no
  // app pra pedido por telefone/WhatsApp), gravada nas mesmas duas colunas
  // (por finalizar_pedido_site no site, por registrar_pedido_completo no
  // app). Só existe pra pedidos com checkout do app (loja física/WhatsApp/
  // site) — pedidos iFood ainda não têm endereço/coordenadas suficientes
  // pra calcular a zona, e usam agendado/entregaPrevista* (acima) em vez disso.
  final bool agendadoManualmente;
  final DateTime? previsaoEntregaInicio;
  final DateTime? previsaoEntregaFim;

  /// 'expressa'/'economica'/'agendada' — só vem preenchido em pedido do
  /// site (ver `finalizar_pedido_site`); pedido criado no app (loja
  /// física/WhatsApp) não grava essa chave, então vem `null` mesmo sendo
  /// imediato — nesse caso trata-se como 'expressa' (ver `Venda.modalidade`).
  final String? modalidadeEntrega;

  Venda({
    this.idVenda,
    this.numeroSequencial,
    required this.cliente,
    required this.dataVenda,
    required this.subtotal,
    required this.desconto,
    this.cupomId,
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
    this.motivoCancelamentoCodigo,
    this.motivoCancelamentoDescricao,
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
    this.linkConfirmacaoEntrega,
    this.statusPagamento,
    this.mercadoPagoPaymentTypeId,
    this.mercadoPagoInstallments,
    this.mercadoPagoPaymentId,
    this.mercadoPagoRefundId,
    this.mercadoPagoEstornadoEm,
    this.mercadoPagoTaxa,
    this.custoEmbalagem,
    this.taxaMaquininha,
    this.custoEntregaReal,
    this.taxaComissaoMarketplace,
    this.taxaGatewayMarketplace,
    this.taxaServicoCliente,
    this.campanhaMarketplace,
    this.cupomMarketplace,
    this.politicaSubstituicao,
    this.entregadorTipo,
    this.agendado = false,
    this.entregaPrevistaInicio,
    this.entregaPrevistaFim,
    this.agendadoManualmente = false,
    this.previsaoEntregaInicio,
    this.previsaoEntregaFim,
    this.modalidadeEntrega,
  });

  /// Sempre usar isso pra atualizar campos localmente (ex: status após
  /// cancelamento) em vez de reconstruir `Venda(...)` na mão — um
  /// construtor manual esquece silenciosamente qualquer campo novo
  /// (todos têm default/nullable, então compila mesmo incompleto), o que
  /// já causou um bug real: cancelar uma venda de marketplace resetava
  /// `canalVenda` pra 'loja_fisica' e apagava rastreio/código de
  /// confirmação/link de entrega da tela, mesmo a venda continuando
  /// corretamente marcada como cancelada no banco.
  Venda copyWith({
    String? idVenda,
    int? numeroSequencial,
    Cliente? cliente,
    DateTime? dataVenda,
    double? subtotal,
    double? desconto,
    String? cupomId,
    double? saldoUsado,
    double? valorEntrega,
    String? entregaSelecionada,
    double? valorTotal,
    double? valorPago,
    double? troco,
    String? metodoPagamento,
    int? totalItens,
    List<ItemVenda>? itens,
    double? custoTotal,
    double? lucroTotal,
    String? observacao,
    Map<String, double>? pagamentosDetalhados,
    String? status,
    String? canalVenda,
    String? vendedorId,
    String? motivoCancelamentoCodigo,
    String? motivoCancelamentoDescricao,
    String? marketplacePedidoId,
    String? tipoEntregaMarketplace,
    String? codigoConfirmacaoStatus,
    String? codigoConfirmacaoErro,
    double? rastreioLatitude,
    double? rastreioLongitude,
    DateTime? rastreioEtaEntrega,
    DateTime? rastreioAtualizadoEm,
    String? separacaoStatus,
    String? separacaoErro,
    String? numeroExibicaoMarketplace,
    String? telefoneLocalizador,
    DateTime? telefoneLocalizadorExpiraEm,
    String? codigoRetiradaExibicao,
    String? linkConfirmacaoEntrega,
    String? statusPagamento,
    String? mercadoPagoPaymentTypeId,
    int? mercadoPagoInstallments,
    String? mercadoPagoPaymentId,
    String? mercadoPagoRefundId,
    DateTime? mercadoPagoEstornadoEm,
    double? mercadoPagoTaxa,
    double? custoEmbalagem,
    double? taxaMaquininha,
    double? custoEntregaReal,
    double? taxaComissaoMarketplace,
    double? taxaGatewayMarketplace,
    double? taxaServicoCliente,
    String? campanhaMarketplace,
    String? cupomMarketplace,
    String? politicaSubstituicao,
    String? entregadorTipo,
    bool? agendado,
    DateTime? entregaPrevistaInicio,
    DateTime? entregaPrevistaFim,
    bool? agendadoManualmente,
    DateTime? previsaoEntregaInicio,
    DateTime? previsaoEntregaFim,
    String? modalidadeEntrega,
  }) {
    return Venda(
      idVenda: idVenda ?? this.idVenda,
      numeroSequencial: numeroSequencial ?? this.numeroSequencial,
      cliente: cliente ?? this.cliente,
      dataVenda: dataVenda ?? this.dataVenda,
      subtotal: subtotal ?? this.subtotal,
      desconto: desconto ?? this.desconto,
      cupomId: cupomId ?? this.cupomId,
      saldoUsado: saldoUsado ?? this.saldoUsado,
      valorEntrega: valorEntrega ?? this.valorEntrega,
      entregaSelecionada: entregaSelecionada ?? this.entregaSelecionada,
      valorTotal: valorTotal ?? this.valorTotal,
      valorPago: valorPago ?? this.valorPago,
      troco: troco ?? this.troco,
      metodoPagamento: metodoPagamento ?? this.metodoPagamento,
      totalItens: totalItens ?? this.totalItens,
      itens: itens ?? this.itens,
      custoTotal: custoTotal ?? this.custoTotal,
      lucroTotal: lucroTotal ?? this.lucroTotal,
      observacao: observacao ?? this.observacao,
      pagamentosDetalhados: pagamentosDetalhados ?? this.pagamentosDetalhados,
      status: status ?? this.status,
      canalVenda: canalVenda ?? this.canalVenda,
      vendedorId: vendedorId ?? this.vendedorId,
      motivoCancelamentoCodigo: motivoCancelamentoCodigo ?? this.motivoCancelamentoCodigo,
      motivoCancelamentoDescricao: motivoCancelamentoDescricao ?? this.motivoCancelamentoDescricao,
      marketplacePedidoId: marketplacePedidoId ?? this.marketplacePedidoId,
      tipoEntregaMarketplace: tipoEntregaMarketplace ?? this.tipoEntregaMarketplace,
      codigoConfirmacaoStatus: codigoConfirmacaoStatus ?? this.codigoConfirmacaoStatus,
      codigoConfirmacaoErro: codigoConfirmacaoErro ?? this.codigoConfirmacaoErro,
      rastreioLatitude: rastreioLatitude ?? this.rastreioLatitude,
      rastreioLongitude: rastreioLongitude ?? this.rastreioLongitude,
      rastreioEtaEntrega: rastreioEtaEntrega ?? this.rastreioEtaEntrega,
      rastreioAtualizadoEm: rastreioAtualizadoEm ?? this.rastreioAtualizadoEm,
      separacaoStatus: separacaoStatus ?? this.separacaoStatus,
      separacaoErro: separacaoErro ?? this.separacaoErro,
      numeroExibicaoMarketplace: numeroExibicaoMarketplace ?? this.numeroExibicaoMarketplace,
      telefoneLocalizador: telefoneLocalizador ?? this.telefoneLocalizador,
      telefoneLocalizadorExpiraEm: telefoneLocalizadorExpiraEm ?? this.telefoneLocalizadorExpiraEm,
      codigoRetiradaExibicao: codigoRetiradaExibicao ?? this.codigoRetiradaExibicao,
      linkConfirmacaoEntrega: linkConfirmacaoEntrega ?? this.linkConfirmacaoEntrega,
      statusPagamento: statusPagamento ?? this.statusPagamento,
      mercadoPagoPaymentTypeId: mercadoPagoPaymentTypeId ?? this.mercadoPagoPaymentTypeId,
      mercadoPagoInstallments: mercadoPagoInstallments ?? this.mercadoPagoInstallments,
      mercadoPagoPaymentId: mercadoPagoPaymentId ?? this.mercadoPagoPaymentId,
      mercadoPagoRefundId: mercadoPagoRefundId ?? this.mercadoPagoRefundId,
      mercadoPagoEstornadoEm: mercadoPagoEstornadoEm ?? this.mercadoPagoEstornadoEm,
      mercadoPagoTaxa: mercadoPagoTaxa ?? this.mercadoPagoTaxa,
      custoEmbalagem: custoEmbalagem ?? this.custoEmbalagem,
      taxaMaquininha: taxaMaquininha ?? this.taxaMaquininha,
      custoEntregaReal: custoEntregaReal ?? this.custoEntregaReal,
      taxaComissaoMarketplace: taxaComissaoMarketplace ?? this.taxaComissaoMarketplace,
      taxaGatewayMarketplace: taxaGatewayMarketplace ?? this.taxaGatewayMarketplace,
      taxaServicoCliente: taxaServicoCliente ?? this.taxaServicoCliente,
      campanhaMarketplace: campanhaMarketplace ?? this.campanhaMarketplace,
      cupomMarketplace: cupomMarketplace ?? this.cupomMarketplace,
      politicaSubstituicao: politicaSubstituicao ?? this.politicaSubstituicao,
      entregadorTipo: entregadorTipo ?? this.entregadorTipo,
      agendado: agendado ?? this.agendado,
      entregaPrevistaInicio: entregaPrevistaInicio ?? this.entregaPrevistaInicio,
      entregaPrevistaFim: entregaPrevistaFim ?? this.entregaPrevistaFim,
      agendadoManualmente: agendadoManualmente ?? this.agendadoManualmente,
      previsaoEntregaInicio: previsaoEntregaInicio ?? this.previsaoEntregaInicio,
      previsaoEntregaFim: previsaoEntregaFim ?? this.previsaoEntregaFim,
      modalidadeEntrega: modalidadeEntrega ?? this.modalidadeEntrega,
    );
  }

  bool get pagoPeloMarketplace => statusPagamento == 'pago';

  /// Pago de verdade por um gateway online que não é o iFood (hoje só
  /// Mercado Pago, pelo site) — cobrar de novo na entrega seria cobrança
  /// duplicada. Não usa `ehMarketplace` porque essa venda não veio do
  /// iFood; usa `statusPagamento` (mesmo campo que já alimenta
  /// `pagoPeloMarketplace`), que é preenchido igual pra qualquer canal.
  ///
  /// Exige `mercadoPagoPaymentId` também — só `statusPagamento == 'pago'`
  /// não basta pra dizer "pago online": pedido `loja_fisica` com entrega
  /// também vira 'pago' sozinho quando marcado como entregue (pagamento
  /// presencial confirmado na hora, trigger
  /// `confirmar_pagamento_entrega_loja_fisica`), sem nenhum gateway
  /// envolvido — sem essa checagem, toda venda de entrega do app mostrava
  /// "Já pago online — NÃO cobrar na entrega" e o botão de estornar pelo
  /// Mercado Pago, ambos sem sentido pra um pagamento presencial.
  bool get pagoOnline => !ehMarketplace && statusPagamento == 'pago' && mercadoPagoPaymentId != null;

  /// true = essa venda foi cancelada com estorno de verdade pelo Mercado
  /// Pago (ver `VendaRepository.estornarPagamentoOnline`), não só um
  /// cancelamento comum (que nunca chegou a cobrar, nada a devolver).
  bool get estornadoOnline => mercadoPagoEstornadoEm != null;

  /// `lucroTotal` (calculado só a partir do custo dos produtos) menos TODO
  /// custo/taxa operacional real conhecido pra essa venda: embalagem,
  /// entrega própria, maquininha (cartão na entrega/loja), taxa do Mercado
  /// Pago (pagamento online) e comissão de marketplace (iFood/99Food) —
  /// cada um só entra na conta quando existir (pedidos sem essas
  /// configurações continuam mostrando só o lucro de produto, sem inventar
  /// custo). É o número final de "quanto sobrou de verdade", usado em vez
  /// de `lucroTotal` sozinho na tela de detalhe da venda.
  double get lucroLiquidoReal =>
      lucroTotal -
      (custoEmbalagem ?? 0) -
      (custoEntregaReal ?? 0) -
      (taxaMaquininha ?? 0) -
      (mercadoPagoTaxa ?? 0) -
      (ehMarketplace ? (taxaComissaoMarketplace ?? 0) : 0) -
      (ehMarketplace ? (taxaGatewayMarketplace ?? 0) : 0);

  /// "Pagamento Online" (rótulo genérico gravado no site pra qualquer
  /// meio pago via Mercado Pago) detalhado pra forma real usada — sem
  /// isso o lojista via só "Pagamento Online" e não sabia se foi
  /// crédito/débito/Pix nem quantas parcelas. `null` quando `metodoPagamento`
  /// não é online (nada a detalhar) ou o pagamento é antigo, de antes
  /// dessa informação começar a ser gravada.
  String? get detalheFormaPagamentoOnline {
    switch (mercadoPagoPaymentTypeId) {
      case 'credit_card':
        final parcelas = mercadoPagoInstallments ?? 1;
        return parcelas > 1 ? 'Cartão de crédito parcelado em ${parcelas}x' : 'Cartão de crédito à vista';
      case 'debit_card':
        return 'Cartão de débito';
      case 'bank_transfer':
        return 'Pix (Mercado Pago)';
      default:
        return null;
    }
  }

  bool get telefoneLocalizadorValido =>
      telefoneLocalizador != null &&
      telefoneLocalizador!.isNotEmpty &&
      (telefoneLocalizadorExpiraEm == null || telefoneLocalizadorExpiraEm!.isAfter(DateTime.now()));

  /// Quem efetivamente cancelou — 'cliente'/'sistema'/'loja'. Deduzido de
  /// `motivoCancelamentoCodigo` (não é um campo próprio no banco): os
  /// códigos conhecidos hoje são 'cliente_trocou_forma_pagamento' (cliente,
  /// site), 'pagamento_recusado'/'pagamento_abandonado' (sistema, Mercado
  /// Pago), e tudo mais (estorno pelo lojista, motivos do iFood,
  /// cancelamento manual — 'cancelado_pela_loja' ou o `null` de vendas
  /// canceladas antes dessa distinção existir) cai em 'loja', o caso mais
  /// comum. Só faz sentido quando `cancelada`.
  String? get origemCancelamento {
    if (!cancelada) return null;
    switch (motivoCancelamentoCodigo) {
      case 'cliente_trocou_forma_pagamento':
        return 'cliente';
      case 'pagamento_recusado':
      case 'pagamento_abandonado':
        return 'sistema';
      default:
        return 'loja';
    }
  }

  bool get cancelada => status == StatusPedido.cancelado;
  bool get finalizada => status == StatusPedido.entregue;
  bool get aguardandoPagamento => status == StatusPedido.aguardandoPagamento;
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

  /// Classificação única de "como/quando entregar", pra chip e filtro na
  /// Fila de Pedidos (ver `FilaPedidosScreen`): 'retirada' (não entra em
  /// rota), 'agendada' (janela escolhida — iFood ou manual), 'economica'
  /// (config única da loja, mais barata/lenta, só existe em pedido do
  /// site) ou 'expressa' (default — imediato, zona de distância). Pedido
  /// criado no app (loja física/WhatsApp) nunca grava `modalidadeEntrega`
  /// mesmo sendo imediato, por isso o fallback pra 'expressa'.
  String get modalidade {
    if (retirada) return 'retirada';
    if (agendado || agendadoManualmente) return 'agendada';
    if (modalidadeEntrega == 'economica') return 'economica';
    return 'expressa';
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
  final List<Map<String, dynamic>>? sugestoesSubstituicao; // bag.items[].replacement.list do virtual-bag

  /// Id do KIT (não do componente) que originou este item, quando ele veio
  /// da explosão de um kit em produtos reais (ver `CarrinhoProvider.adicionarKit`)
  /// — null pra item avulso normal. Grava em `itens_pedido.grupo_kit_id`.
  final String? grupoKitId;

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
    this.sugestoesSubstituicao,
    this.grupoKitId,
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





