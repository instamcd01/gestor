/// Dica (guia educativo) do site — página `/loja/<slug>/dicas/<guia>` do
/// gestor-loja, lida pela view `catalogo_conteudos_publico` (só publicadas).
/// Nasce como rascunho na Edge Function `guias-rascunho` quando a loja posta
/// um Reel educativo; o dono revisa e publica aqui.
///
/// `corpo` fica como lista de mapas (blocos `h2`/`p` com `texto`,
/// `lista`/`passos` com `itens`) — mesmo formato que o site renderiza.
class ConteudoGuia {
  final String id;
  final String slug;
  final String titulo;
  final String resumo;
  final String? respostaCurta;
  final List<Map<String, dynamic>> corpo;
  final List<Map<String, dynamic>> videos;
  final List<Map<String, dynamic>> perguntas;
  final String? capaUrl;
  final String? serie;
  final String status; // 'rascunho' | 'publicado'
  final DateTime? publicadoEm;
  final DateTime criadoEm;

  ConteudoGuia({
    required this.id,
    required this.slug,
    required this.titulo,
    required this.resumo,
    this.respostaCurta,
    required this.corpo,
    required this.videos,
    required this.perguntas,
    this.capaUrl,
    this.serie,
    required this.status,
    this.publicadoEm,
    required this.criadoEm,
  });

  bool get rascunho => status == 'rascunho';

  static List<Map<String, dynamic>> _lista(dynamic valor) =>
      (valor as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  factory ConteudoGuia.fromSupabase(Map<String, dynamic> row) => ConteudoGuia(
        id: row['id'] as String,
        slug: row['slug'] as String,
        titulo: row['titulo'] as String,
        resumo: row['resumo'] as String,
        respostaCurta: row['resposta_curta'] as String?,
        corpo: _lista(row['corpo']),
        videos: _lista(row['videos']),
        perguntas: _lista(row['perguntas']),
        capaUrl: row['capa_url'] as String?,
        serie: row['serie'] as String?,
        status: row['status'] as String,
        publicadoEm: row['publicado_em'] == null ? null : DateTime.parse(row['publicado_em'] as String),
        criadoEm: DateTime.parse(row['created_at'] as String),
      );
}
