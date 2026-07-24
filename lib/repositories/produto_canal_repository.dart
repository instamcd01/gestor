import '../config/supabase_config.dart';

/// Preço e disponibilidade de um produto por marketplace (`produto_canal`).
/// É o que permite o mesmo produto ter preços diferentes no iFood, 99Food,
/// Rappi etc., além do preço padrão da loja.
class ProdutoCanalRepository {
  Future<List<Map<String, dynamic>>> listarPorProduto(String produtoId) async {
    final data = await supabase
        .from('produto_canal')
        .select()
        .eq('produto_id', produtoId);

    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<void> salvar({
    required String produtoId,
    required String marketplaceId,
    required double preco,
    required bool disponivel,
  }) async {
    await supabase.from('produto_canal').upsert(
      {
        'produto_id': produtoId,
        'marketplace_id': marketplaceId,
        'preco': preco,
        'disponivel': disponivel,
      },
      onConflict: 'produto_id,marketplace_id',
    );
  }

  /// Upsert em massa (importação de planilha) — um só round-trip pra
  /// centenas/milhares de linhas em vez de uma chamada por produto.
  Future<void> salvarEmLote(
    List<({String produtoId, String marketplaceId, double preco, bool disponivel})> itens, {
    int tamanhoLote = 500,
  }) async {
    for (var i = 0; i < itens.length; i += tamanhoLote) {
      final lote = itens.sublist(i, i + tamanhoLote > itens.length ? itens.length : i + tamanhoLote);
      await supabase.from('produto_canal').upsert(
        lote
            .map((it) => {
                  'produto_id': it.produtoId,
                  'marketplace_id': it.marketplaceId,
                  'preco': it.preco,
                  'disponivel': it.disponivel,
                })
            .toList(),
        onConflict: 'produto_id,marketplace_id',
      );
    }
  }
}
