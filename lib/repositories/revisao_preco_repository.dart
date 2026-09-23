import '../config/supabase_config.dart';

/// Contexto de decisão de um produto pendente em "Revisar preço" (Análise de
/// produtos) — lido da view `v_revisao_preco`. "Anterior" = estado antes da
/// PRIMEIRA mudança de custo desde a última vez que o preço foi mexido (se o
/// custo subiu 2x sem revisão, a base é antes da 1ª alta), a partir de
/// `historico_precos_produto`.
class RevisaoPrecoContexto {
  final String produtoId;
  final double? custoAnterior;
  final double? precoAnterior;
  final DateTime? custoAlteradoEm;
  final int vendas60d;
  final double? precoIfood;
  final bool ifoodDisponivel;

  /// Markup (% sobre o custo) mediano da categoria, catálogo ativo inteiro.
  final double? markupCategoria;

  const RevisaoPrecoContexto({
    required this.produtoId,
    this.custoAnterior,
    this.precoAnterior,
    this.custoAlteradoEm,
    required this.vendas60d,
    this.precoIfood,
    required this.ifoodDisponivel,
    this.markupCategoria,
  });

  factory RevisaoPrecoContexto.fromSupabase(Map<String, dynamic> row) {
    double? numero(String campo) => (row[campo] as num?)?.toDouble();
    return RevisaoPrecoContexto(
      produtoId: row['produto_id'] as String,
      custoAnterior: numero('custo_anterior'),
      precoAnterior: numero('preco_anterior'),
      custoAlteradoEm: row['custo_alterado_em'] != null ? DateTime.parse(row['custo_alterado_em'] as String) : null,
      vendas60d: (row['vendas_60d'] as num?)?.toInt() ?? 0,
      precoIfood: numero('preco_ifood'),
      ifoodDisponivel: row['ifood_disponivel'] as bool? ?? false,
      markupCategoria: numero('markup_categoria'),
    );
  }

  /// Markup (% sobre o custo) que o produto tinha antes da mudança de custo.
  double? get markupAnterior {
    final custo = custoAnterior;
    final preco = precoAnterior;
    if (custo == null || custo <= 0 || preco == null || preco <= 0) return null;
    return (preco / custo - 1) * 100;
  }

  /// Preço que mantém o markup anterior sobre o custo novo — a sugestão
  /// padrão (critério neutro: respeita a decisão de preço já tomada antes).
  double? precoSugerido(double custoAtual) {
    final markup = markupAnterior;
    if (markup == null || custoAtual <= 0) return null;
    return custoAtual * (1 + markup / 100);
  }
}

class RevisaoPrecoRepository {
  Future<Map<String, RevisaoPrecoContexto>> carregar() async {
    final data = await supabase.from('v_revisao_preco').select();
    return {
      for (final row in (data as List).cast<Map<String, dynamic>>())
        row['produto_id'] as String: RevisaoPrecoContexto.fromSupabase(row),
    };
  }
}
