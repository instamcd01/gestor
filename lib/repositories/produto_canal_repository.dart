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
}
