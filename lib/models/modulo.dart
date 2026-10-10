/// Slugs dos módulos instaláveis (tabela `modulos`) — usar estas constantes
/// em vez de string solta ao marcar menu/tela como dependente de módulo.
/// A BASE do app não é módulo: toda loja tem.
abstract final class Modulos {
  static const lojaOnline = 'loja_online';
  static const petcash = 'petcash';
  static const whatsapp = 'whatsapp';
  static const atendenteIa = 'atendente_ia';
  static const marketing = 'marketing';
  static const ifood = 'ifood';
  static const food99 = '99food';
  static const notasFiscais = 'notas_fiscais';
  static const compras = 'compras';
  static const entregas = 'entregas';
  static const gestaoFinanceira = 'gestao_financeira';
  static const planejamento = 'planejamento';
  static const conteudoSocial = 'conteudo_social';

  /// Qualquer marketplace com integração construída — pra telas que
  /// servem aos dois (Avaliações, Financeiro por Marketplace).
  static const marketplaces = [ifood, food99];
}

/// Um módulo do catálogo (`modulos`) + se está ativo na loja atual
/// (`empresa_modulos`).
class Modulo {
  final String slug;
  final String nome;
  final String descricao;
  final String icone;
  final int ordem;
  final List<String> dependeDe;
  final List<String> aproveita;
  final bool disponivel;
  final bool ativo;

  const Modulo({
    required this.slug,
    required this.nome,
    required this.descricao,
    required this.icone,
    required this.ordem,
    this.dependeDe = const [],
    this.aproveita = const [],
    this.disponivel = true,
    this.ativo = false,
  });

  factory Modulo.fromSupabase(Map<String, dynamic> row, {required bool ativo}) {
    return Modulo(
      slug: row['slug'] as String,
      nome: row['nome']?.toString() ?? '',
      descricao: row['descricao']?.toString() ?? '',
      icone: row['icone']?.toString() ?? '',
      ordem: (row['ordem'] as num?)?.toInt() ?? 0,
      dependeDe: List<String>.from(row['depende_de'] as List? ?? const []),
      aproveita: List<String>.from(row['aproveita'] as List? ?? const []),
      disponivel: row['disponivel'] as bool? ?? true,
      ativo: ativo,
    );
  }
}
