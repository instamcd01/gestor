/// Um pedido de marketplace (iFood, 99Food, ...) com os dados financeiros
/// que a integração já capturou em `marketplace_pedidos`, junto com os
/// dados básicos do pedido (`pedidos`) e o nome do canal (`marketplaces`).
/// Usado pela [DashboardMarketplaceScreen] — cada linha aqui é um pedido,
/// a agregação por canal/status é feita na tela.
class MarketplacePedidoFinanceiro {
  final String pedidoId;
  final DateTime dataPedido;
  final String statusPedido;
  final double valorTotalPedido;
  final String marketplaceNome;

  final String? statusMarketplace;
  final double? valorBrutoMarketplace;
  final double? valorLiquidoRecebido;
  final double? taxaComissao;
  final double? taxaEntregaMarketplace;
  final double? taxaGateway;
  final double? outrasTaxas;
  final double? taxaServicoCliente;
  final double? valorRepassado;
  final DateTime? dataRepassado;
  final double? avaliacaoMarketplace;
  final Duration? tempoConfirmacao;
  final Duration? tempoPreparo;

  MarketplacePedidoFinanceiro({
    required this.pedidoId,
    required this.dataPedido,
    required this.statusPedido,
    required this.valorTotalPedido,
    required this.marketplaceNome,
    this.statusMarketplace,
    this.valorBrutoMarketplace,
    this.valorLiquidoRecebido,
    this.taxaComissao,
    this.taxaEntregaMarketplace,
    this.taxaGateway,
    this.outrasTaxas,
    this.taxaServicoCliente,
    this.valorRepassado,
    this.dataRepassado,
    this.avaliacaoMarketplace,
    this.tempoConfirmacao,
    this.tempoPreparo,
  });

  /// Soma de todas as taxas já conhecidas (algumas ainda ficam null
  /// enquanto a loja estiver em sandbox — ver seção financeiro do mapa
  /// de integração).
  double get taxasConhecidas =>
      (taxaComissao ?? 0) + (taxaEntregaMarketplace ?? 0) + (taxaGateway ?? 0) + (outrasTaxas ?? 0);

  factory MarketplacePedidoFinanceiro.fromSupabase(Map<String, dynamic> row) {
    final marketplaceRow = row['marketplaces'] as Map<String, dynamic>?;
    final financeiroRow = row['marketplace_pedidos'] as Map<String, dynamic>?;

    return MarketplacePedidoFinanceiro(
      pedidoId: row['id'] as String,
      dataPedido: DateTime.tryParse(row['created_at'].toString())?.toLocal() ?? DateTime.now(),
      statusPedido: row['status']?.toString() ?? '',
      valorTotalPedido: (row['valor_total'] as num?)?.toDouble() ?? 0.0,
      marketplaceNome: marketplaceRow?['nome']?.toString() ?? 'Marketplace',
      statusMarketplace: financeiroRow?['status_marketplace']?.toString(),
      valorBrutoMarketplace: (financeiroRow?['valor_bruto_marketplace'] as num?)?.toDouble(),
      valorLiquidoRecebido: (financeiroRow?['valor_liquido_recebido'] as num?)?.toDouble(),
      taxaComissao: (financeiroRow?['taxa_comissao'] as num?)?.toDouble(),
      taxaEntregaMarketplace: (financeiroRow?['taxa_entrega_marketplace'] as num?)?.toDouble(),
      taxaGateway: (financeiroRow?['taxa_gateway'] as num?)?.toDouble(),
      outrasTaxas: (financeiroRow?['outras_taxas'] as num?)?.toDouble(),
      taxaServicoCliente: (financeiroRow?['taxa_servico_cliente'] as num?)?.toDouble(),
      valorRepassado: (financeiroRow?['valor_repassado'] as num?)?.toDouble(),
      dataRepassado: DateTime.tryParse(financeiroRow?['data_repassado']?.toString() ?? ''),
      avaliacaoMarketplace: (financeiroRow?['avaliacao_marketplace'] as num?)?.toDouble(),
      tempoConfirmacao: _parseIntervalo(financeiroRow?['tempo_confirmacao_marketplace']?.toString()),
      tempoPreparo: _parseIntervalo(financeiroRow?['tempo_preparo_marketplace']?.toString()),
    );
  }

  /// O Postgres devolve `interval` como texto no formato `HH:MM:SS.ffffff`
  /// (ou `D day(s) HH:MM:SS` pra valores acima de 24h, que não esperamos
  /// aqui — tempo de confirmação/preparo de um pedido é sempre minutos).
  static Duration? _parseIntervalo(String? texto) {
    if (texto == null || texto.isEmpty) return null;
    final partes = texto.split(':');
    if (partes.length != 3) return null;
    final horas = int.tryParse(partes[0]) ?? 0;
    final minutos = int.tryParse(partes[1]) ?? 0;
    final segundos = double.tryParse(partes[2]) ?? 0;
    return Duration(hours: horas, minutes: minutos, seconds: segundos.floor());
  }
}
