/// Banner rotativo da home do site (gestor-loja) — imagem ou vídeo,
/// configurado aqui no app e consumido pela view `catalogo_banners_publico`.
class BannerHome {
  final String? id;
  final String tipo; // 'imagem' | 'video'
  final String url;
  final String? urlThumbnail;
  final String? titulo;
  final String? linkDestino;
  final int ordem;
  final bool ativo;

  BannerHome({
    this.id,
    required this.tipo,
    required this.url,
    this.urlThumbnail,
    this.titulo,
    this.linkDestino,
    this.ordem = 0,
    this.ativo = true,
  });

  bool get isVideo => tipo == 'video';

  factory BannerHome.fromSupabase(Map<String, dynamic> row) {
    return BannerHome(
      id: row['id'] as String?,
      tipo: row['tipo']?.toString() ?? 'imagem',
      url: row['url']?.toString() ?? '',
      urlThumbnail: row['url_thumbnail']?.toString(),
      titulo: row['titulo']?.toString(),
      linkDestino: row['link_destino']?.toString(),
      ordem: (row['ordem'] as num?)?.toInt() ?? 0,
      ativo: row['ativo'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toSupabaseMap() {
    return {
      'tipo': tipo,
      'url': url,
      'url_thumbnail': urlThumbnail,
      'titulo': titulo,
      'link_destino': linkDestino,
      'ordem': ordem,
      'ativo': ativo,
    };
  }
}
