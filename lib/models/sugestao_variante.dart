/// Sugestão automática de agrupamento de variantes (ex: mesma ração em
/// pesos diferentes), gerada pelo trigger `detectar_sugestao_variante` do
/// banco — nunca aplicada sozinha, sempre pendente de revisão manual (ver
/// docs/superpowers/specs/2026-08-03-variantes-produto-design.md).
class SugestaoVariante {
  final String id;
  final String produtoId;
  final String produtoCandidatoId;
  final String tipoVariacao;
  final String varianteLabelSugerido;

  /// `"estruturado"` (comparação exata de campos, alta confiança) ou
  /// `"heuristico"` (regex/dicionário sobre o nome, catálogo legado).
  final String origem;
  final String status;

  const SugestaoVariante({
    required this.id,
    required this.produtoId,
    required this.produtoCandidatoId,
    required this.tipoVariacao,
    required this.varianteLabelSugerido,
    required this.origem,
    required this.status,
  });

  factory SugestaoVariante.fromSupabase(Map<String, dynamic> row) {
    return SugestaoVariante(
      id: row['id'] as String,
      produtoId: row['produto_id'] as String,
      produtoCandidatoId: row['produto_candidato_id'] as String,
      tipoVariacao: row['tipo_variacao']?.toString() ?? '',
      varianteLabelSugerido: row['variante_label_sugerido']?.toString() ?? '',
      origem: row['origem']?.toString() ?? 'heuristico',
      status: row['status']?.toString() ?? 'pendente',
    );
  }
}
