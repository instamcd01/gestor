/// Produto com estoque e sem venda há mais de N dias (RPC
/// `produtos_estoque_parado`). Os dados do produto em si (nome, preço,
/// custo...) vêm do ProdutoProvider — aqui só o que é calculado no banco.
class EstoqueParado {
  final String produtoId;

  /// null = nenhuma venda no histórico (inclui o importado do Kyte).
  final DateTime? ultimaVenda;
  final int? diasSemVenda;
  final int vendas12m;
  final int quantidade;

  /// Quantidade × custo — quanto dinheiro está parado nesse produto.
  final double capital;

  const EstoqueParado({
    required this.produtoId,
    required this.ultimaVenda,
    required this.diasSemVenda,
    required this.vendas12m,
    required this.quantidade,
    required this.capital,
  });

  factory EstoqueParado.fromSupabase(Map<String, dynamic> row) => EstoqueParado(
        produtoId: row['produto_id'] as String,
        ultimaVenda: row['ultima_venda'] != null ? DateTime.parse(row['ultima_venda'] as String).toLocal() : null,
        diasSemVenda: (row['dias_sem_venda'] as num?)?.toInt(),
        vendas12m: (row['vendas_12m'] as num?)?.toInt() ?? 0,
        quantidade: (row['quantidade'] as num).toInt(),
        capital: (row['capital'] as num?)?.toDouble() ?? 0,
      );

  /// Faixa usada no filtro da aba "Estoque parado".
  String get faixa {
    final dias = diasSemVenda;
    if (dias == null) return 'Nunca vendeu';
    if (dias <= 180) return '90 a 180 dias';
    if (dias <= 365) return '180 dias a 1 ano';
    return 'Mais de 1 ano';
  }
}
