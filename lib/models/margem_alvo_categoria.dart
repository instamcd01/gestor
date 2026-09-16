/// Margem-alvo (% sobre o preço de venda, não sobre o custo — confirmado
/// com o usuário 15/09) configurada por categoria, opcionalmente refinada
/// por subcategoria. `subcategoria` vazia (`''`) significa "vale pra
/// categoria inteira" — sentinela usada em vez de `null` só pra manter o
/// unique constraint do banco simples com upsert.
class MargemAlvoCategoria {
  final String? id;
  final String categoria;
  final String subcategoria;
  final double margemAlvoPercentual;

  MargemAlvoCategoria({
    this.id,
    required this.categoria,
    this.subcategoria = '',
    required this.margemAlvoPercentual,
  });

  factory MargemAlvoCategoria.fromSupabase(Map<String, dynamic> row) {
    return MargemAlvoCategoria(
      id: row['id'] as String?,
      categoria: row['categoria'] as String,
      subcategoria: row['subcategoria'] as String? ?? '',
      margemAlvoPercentual: (row['margem_alvo_percentual'] as num).toDouble(),
    );
  }
}
