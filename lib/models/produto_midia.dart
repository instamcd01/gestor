/// Uma mídia (imagem ou vídeo por link) associada a um produto.
/// Imagens usam `ordem` 1-6 (limite reforçado também no banco); vídeos têm
/// sua própria sequência de `ordem`, independente da de imagens.
class ProdutoMidia {
  final String id;
  final String produtoId;
  final String tipo; // 'imagem' | 'video'
  final String url;
  final int ordem;

  const ProdutoMidia({
    required this.id,
    required this.produtoId,
    required this.tipo,
    required this.url,
    required this.ordem,
  });

  bool get isImagem => tipo == 'imagem';
  bool get isVideo => tipo == 'video';

  factory ProdutoMidia.fromSupabase(Map<String, dynamic> row) {
    return ProdutoMidia(
      id: row['id'] as String,
      produtoId: row['produto_id'] as String,
      tipo: row['tipo'] as String,
      url: row['url'] as String,
      ordem: (row['ordem'] as num).toInt(),
    );
  }
}
