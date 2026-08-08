/// Faixa de desconto em cascata por quantidade — a partir de
/// [quantidadeMinima] unidades pedidas desse produto nesse fornecedor,
/// [custoUnitario] passa a valer. O custo aplicado num pedido é sempre o
/// da maior faixa cuja [quantidadeMinima] é menor ou igual à quantidade
/// pedida (ver `ProdutoFornecedor.custoParaQuantidade`).
class FaixaDescontoProdutoFornecedor {
  final String? id;
  final int quantidadeMinima;
  final double custoUnitario;

  FaixaDescontoProdutoFornecedor({
    this.id,
    required this.quantidadeMinima,
    required this.custoUnitario,
  });

  factory FaixaDescontoProdutoFornecedor.fromSupabase(Map<String, dynamic> row) {
    return FaixaDescontoProdutoFornecedor(
      id: row['id'] as String?,
      quantidadeMinima: (row['quantidade_minima'] as num).toInt(),
      custoUnitario: (row['custo_unitario'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toSupabaseMap() {
    return {
      'quantidade_minima': quantidadeMinima,
      'custo_unitario': custoUnitario,
    };
  }
}

/// Vínculo entre um produto e um fornecedor que o vende — um produto pode
/// ter vários fornecedores cadastrados (`principal` marca o default usado
/// na sugestão de compra automática), cada um com seu custo, código de
/// produto próprio e faixas de desconto por quantidade.
class ProdutoFornecedor {
  final String? id;
  final String produtoId;
  final String fornecedorId;
  final String? fornecedorNome;
  final double custoUnitario;
  final String? codigoProdutoFornecedor;
  final int? multiploCompra;
  final bool principal;
  final bool ativo;
  final List<FaixaDescontoProdutoFornecedor> faixasDesconto;

  ProdutoFornecedor({
    this.id,
    required this.produtoId,
    required this.fornecedorId,
    this.fornecedorNome,
    required this.custoUnitario,
    this.codigoProdutoFornecedor,
    this.multiploCompra,
    this.principal = false,
    this.ativo = true,
    this.faixasDesconto = const [],
  });

  /// Custo unitário aplicado ao pedir [quantidade] unidades — a maior faixa
  /// cuja quantidade mínima cabe na quantidade pedida, senão o custo base.
  double custoParaQuantidade(int quantidade) {
    FaixaDescontoProdutoFornecedor? melhorFaixa;
    for (final faixa in faixasDesconto) {
      if (faixa.quantidadeMinima <= quantidade) {
        if (melhorFaixa == null || faixa.quantidadeMinima > melhorFaixa.quantidadeMinima) {
          melhorFaixa = faixa;
        }
      }
    }
    return melhorFaixa?.custoUnitario ?? custoUnitario;
  }

  /// Quantas unidades a mais preciso pedir pra alcançar a próxima faixa de
  /// desconto (e quanto economizaria por unidade) — `null` se já está na
  /// melhor faixa ou não tem faixa configurada. Usado na Sugestão de Compra
  /// pra sugerir "peça mais N e economize R$X".
  ({int unidadesFaltando, double economiaPorUnidade})? proximaFaixa(int quantidade) {
    final custoAtual = custoParaQuantidade(quantidade);
    FaixaDescontoProdutoFornecedor? proxima;
    for (final faixa in faixasDesconto) {
      if (faixa.quantidadeMinima > quantidade && faixa.custoUnitario < custoAtual) {
        if (proxima == null || faixa.quantidadeMinima < proxima.quantidadeMinima) {
          proxima = faixa;
        }
      }
    }
    if (proxima == null) return null;
    return (
      unidadesFaltando: proxima.quantidadeMinima - quantidade,
      economiaPorUnidade: custoAtual - proxima.custoUnitario,
    );
  }

  factory ProdutoFornecedor.fromSupabase(Map<String, dynamic> row) {
    final fornecedorRow = row['fornecedor'] as Map<String, dynamic>?;
    final faixasRows = (row['faixas_desconto_produto_fornecedor'] as List?) ?? [];
    return ProdutoFornecedor(
      id: row['id'] as String?,
      produtoId: row['produto_id'] as String,
      fornecedorId: row['fornecedor_id'] as String,
      fornecedorNome: fornecedorRow?['nome']?.toString(),
      custoUnitario: (row['custo_unitario'] as num?)?.toDouble() ?? 0.0,
      codigoProdutoFornecedor: row['codigo_produto_fornecedor']?.toString(),
      multiploCompra: (row['multiplo_compra'] as num?)?.toInt(),
      principal: row['principal'] as bool? ?? false,
      ativo: row['ativo'] as bool? ?? true,
      faixasDesconto: faixasRows
          .map((r) => FaixaDescontoProdutoFornecedor.fromSupabase(r as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.quantidadeMinima.compareTo(b.quantidadeMinima)),
    );
  }

  Map<String, dynamic> toSupabaseMap() {
    return {
      'produto_id': produtoId,
      'fornecedor_id': fornecedorId,
      'custo_unitario': custoUnitario,
      'codigo_produto_fornecedor': codigoProdutoFornecedor,
      'multiplo_compra': multiploCompra,
      'principal': principal,
      'ativo': ativo,
    };
  }
}
