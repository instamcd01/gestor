/// Produto com estoque e sem venda há mais de N dias (RPC
/// `analise_estoque_parado`, que parte de `produtos_estoque_parado`). Os
/// dados do produto em si (nome, preço, custo...) vêm do ProdutoProvider —
/// aqui só o que é calculado no banco.
class EstoqueParado {
  final String produtoId;

  /// null = nenhuma venda no histórico (inclui o importado do Kyte).
  final DateTime? ultimaVenda;
  final int? diasSemVenda;
  final int vendas12m;
  final int quantidade;

  /// Quantidade × custo — quanto dinheiro está parado nesse produto.
  final double capital;

  final double? precoIfood;

  /// Comissão + taxa de pagamento online do iFood (%), da tabela vigente.
  final double taxaIfoodPct;

  /// Última entrada de NF-e (só existe desde 26/07 — compra antiga não tem).
  final DateTime? ultimaCompraEm;
  final double? ultimaCompraQtd;
  final String? ultimaCompraFornecedor;

  /// Validade do lote da última NF-e — dica, não o que está na prateleira.
  final DateTime? validadeNfe;
  final String? fornecedorPrincipal;

  /// Clientes reais (sem o genérico do relatório iFood).
  final int clientesCompraram;
  final int clientesComContato;

  /// Vendas dos outros tamanhos/sabores da mesma família, últimos 90 dias.
  final int familiaVendas90d;
  final String? familiaMaisVendido;

  /// Quanto vendeu nos próximos 90 dias do ano passado (sazonalidade).
  final int vendasAnoPassadoProx90d;

  final String? ultimaAcao;
  final String? ultimaAcaoDetalhe;
  final DateTime? ultimaAcaoEm;
  final int? vendasDesdeAcao;

  /// Última contagem física (checklist ou ajuste por contagem).
  final DateTime? ultimaContagemEm;

  const EstoqueParado({
    required this.produtoId,
    required this.ultimaVenda,
    required this.diasSemVenda,
    required this.vendas12m,
    required this.quantidade,
    required this.capital,
    this.precoIfood,
    this.taxaIfoodPct = 0,
    this.ultimaCompraEm,
    this.ultimaCompraQtd,
    this.ultimaCompraFornecedor,
    this.validadeNfe,
    this.fornecedorPrincipal,
    this.clientesCompraram = 0,
    this.clientesComContato = 0,
    this.familiaVendas90d = 0,
    this.familiaMaisVendido,
    this.vendasAnoPassadoProx90d = 0,
    this.ultimaAcao,
    this.ultimaAcaoDetalhe,
    this.ultimaAcaoEm,
    this.vendasDesdeAcao,
    this.ultimaContagemEm,
  });

  static DateTime? _data(dynamic v) => v != null ? DateTime.parse(v as String).toLocal() : null;

  factory EstoqueParado.fromSupabase(Map<String, dynamic> row) => EstoqueParado(
        produtoId: row['produto_id'] as String,
        ultimaVenda: _data(row['ultima_venda']),
        diasSemVenda: (row['dias_sem_venda'] as num?)?.toInt(),
        vendas12m: (row['vendas_12m'] as num?)?.toInt() ?? 0,
        quantidade: (row['quantidade'] as num).toInt(),
        capital: (row['capital'] as num?)?.toDouble() ?? 0,
        precoIfood: (row['preco_ifood'] as num?)?.toDouble(),
        taxaIfoodPct: (row['taxa_ifood_pct'] as num?)?.toDouble() ?? 0,
        ultimaCompraEm: _data(row['ultima_compra_em']),
        ultimaCompraQtd: (row['ultima_compra_qtd'] as num?)?.toDouble(),
        ultimaCompraFornecedor: row['ultima_compra_fornecedor'] as String?,
        validadeNfe: row['validade_nfe'] != null ? DateTime.parse(row['validade_nfe'] as String) : null,
        fornecedorPrincipal: row['fornecedor_principal'] as String?,
        clientesCompraram: (row['clientes_compraram'] as num?)?.toInt() ?? 0,
        clientesComContato: (row['clientes_com_contato'] as num?)?.toInt() ?? 0,
        familiaVendas90d: (row['familia_vendas_90d'] as num?)?.toInt() ?? 0,
        familiaMaisVendido: row['familia_mais_vendido'] as String?,
        vendasAnoPassadoProx90d: (row['vendas_ano_passado_prox_90d'] as num?)?.toInt() ?? 0,
        ultimaAcao: row['ultima_acao'] as String?,
        ultimaAcaoDetalhe: row['ultima_acao_detalhe'] as String?,
        ultimaAcaoEm: _data(row['ultima_acao_em']),
        vendasDesdeAcao: (row['vendas_desde_acao'] as num?)?.toInt(),
        ultimaContagemEm: _data(row['ultima_contagem_em']),
      );

  /// Faixa usada no filtro da aba "Estoque parado".
  String get faixa {
    final dias = diasSemVenda;
    if (dias == null) return 'Nunca vendeu';
    if (dias <= 180) return '90 a 180 dias';
    if (dias <= 365) return '180 dias a 1 ano';
    return 'Mais de 1 ano';
  }

  /// Menor preço no iFood sem prejuízo: o iFood desconta a taxa do valor
  /// cheio, então o que sobra (preço × (1 − taxa)) precisa cobrir o custo.
  double precoMinimoIfood(double custo) =>
      taxaIfoodPct >= 100 ? custo : custo / (1 - taxaIfoodPct / 100);
}

/// O que fazer com um produto parado. A ordem do enum é a prioridade.
enum SugestaoEstoqueParado {
  vencido('Vencido — retirar da venda'),
  venceLogo('Vence em breve — liquidar'),
  emAndamento('Ação em andamento — aguardar resultado'),
  conferir('Conferir se o estoque existe'),
  sazonal('Sazonal — deve voltar a vender'),
  avisarClientes('Avisar quem já comprou'),
  variante('Família vende, este não'),
  devolver('Negociar troca com o fornecedor'),
  promocao('Promoção ou kit');

  final String rotulo;
  const SugestaoEstoqueParado(this.rotulo);
}

/// Regra da sugestão — simples de propósito, pra dar pra explicar o porquê
/// na tela. [diasValidade] null = sem validade conferida.
({SugestaoEstoqueParado sugestao, String motivo}) sugerirAcaoEstoqueParado(
  EstoqueParado item, {
  required int? diasValidade,
}) {
  if (diasValidade != null && diasValidade < 0) {
    return (sugestao: SugestaoEstoqueParado.vencido, motivo: 'Venceu há ${-diasValidade} dias.');
  }
  if (diasValidade != null && diasValidade <= 60) {
    return (
      sugestao: SugestaoEstoqueParado.venceLogo,
      motivo: 'Vence em $diasValidade dias: vale vender até a preço de custo, montar kit ou doar antes de perder.',
    );
  }
  final acaoEm = item.ultimaAcaoEm;
  if (acaoEm != null && DateTime.now().difference(acaoEm).inDays <= 30) {
    final dias = DateTime.now().difference(acaoEm).inDays;
    return (
      sugestao: SugestaoEstoqueParado.emAndamento,
      motivo: '"${item.ultimaAcao}" há $dias dia(s) — vendeu ${item.vendasDesdeAcao ?? 0} desde então.',
    );
  }
  if (item.ultimaVenda == null && item.ultimaContagemEm == null) {
    return (
      sugestao: SugestaoEstoqueParado.conferir,
      motivo: 'Nenhuma venda registrada — pode ter sido vendido sem registro. Conte antes de gastar com promoção.',
    );
  }
  // 1 venda só no período do ano passado é acaso, não sazonalidade (31 dos
  // 51 casos reais em 02/10 eram 1 un.).
  if (item.vendasAnoPassadoProx90d >= 2) {
    return (
      sugestao: SugestaoEstoqueParado.sazonal,
      motivo: 'Vendeu ${item.vendasAnoPassadoProx90d} un. nos próximos 90 dias do ano passado — segure o preço.',
    );
  }
  if (item.clientesComContato > 0) {
    return (
      sugestao: SugestaoEstoqueParado.avisarClientes,
      motivo: '${item.clientesComContato} cliente(s) com contato já compraram — avisar sai mais barato que desconto geral.',
    );
  }
  if (item.familiaVendas90d > 0) {
    return (
      sugestao: SugestaoEstoqueParado.variante,
      motivo: 'A família vendeu ${item.familiaVendas90d} un. em 90 dias'
          '${item.familiaMaisVendido != null ? ' (mais vendido: ${item.familiaMaisVendido})' : ''}. '
          'Ofereça este no lugar e pare de recomprar este tamanho/sabor.',
    );
  }
  final fornecedor = item.fornecedorPrincipal ?? item.ultimaCompraFornecedor;
  if (item.ultimaVenda == null && fornecedor != null) {
    return (
      sugestao: SugestaoEstoqueParado.devolver,
      motivo: 'Nunca vendeu. Tente trocar com $fornecedor por algo que gira antes de dar desconto.',
    );
  }
  return (
    sugestao: SugestaoEstoqueParado.promocao,
    motivo: 'Sem sinal de procura — promoção dentro do preço mínimo, ou kit com um produto que vende bem.',
  );
}
