enum LayoutNavegacao { drawer, sidebar }

/// Um modelo/tema visual pronto (ex: "Moderno", "Clássico") — catálogo
/// compartilhado entre todas as empresas do SaaS (tabela `modelos_visuais`,
/// só leitura pelo tenant). Cada empresa escolhe um e pode personalizar
/// cor/logo por cima (ver BrandingProvider).
class ModeloVisual {
  final String id;
  final String nome;
  final String descricao;
  final String corPrimariaPadrao;
  final String corSecundariaPadrao;
  final String fonte;
  final double radiusCard;
  final double radiusBotao;
  final double radiusChip;
  final double radiusFab;
  final bool cardElevado;
  final bool densidadeCompacta;
  final LayoutNavegacao layoutNavegacao;

  ModeloVisual({
    required this.id,
    required this.nome,
    required this.descricao,
    required this.corPrimariaPadrao,
    required this.corSecundariaPadrao,
    required this.fonte,
    required this.radiusCard,
    required this.radiusBotao,
    required this.radiusChip,
    required this.radiusFab,
    required this.cardElevado,
    required this.densidadeCompacta,
    required this.layoutNavegacao,
  });

  factory ModeloVisual.fromSupabase(Map<String, dynamic> row) {
    return ModeloVisual(
      id: row['id'] as String,
      nome: row['nome']?.toString() ?? '',
      descricao: row['descricao']?.toString() ?? '',
      corPrimariaPadrao: row['cor_primaria_padrao']?.toString() ?? '#F5821F',
      corSecundariaPadrao: row['cor_secundaria_padrao']?.toString() ?? '#1E3A5F',
      fonte: row['fonte']?.toString() ?? 'Inter',
      radiusCard: (row['radius_card'] as num?)?.toDouble() ?? 16,
      radiusBotao: (row['radius_botao'] as num?)?.toDouble() ?? 12,
      radiusChip: (row['radius_chip'] as num?)?.toDouble() ?? 8,
      radiusFab: (row['radius_fab'] as num?)?.toDouble() ?? 16,
      cardElevado: row['card_estilo']?.toString() == 'elevado',
      densidadeCompacta: row['densidade']?.toString() == 'compacta',
      layoutNavegacao:
          row['layout_navegacao']?.toString() == 'sidebar' ? LayoutNavegacao.sidebar : LayoutNavegacao.drawer,
    );
  }
}
