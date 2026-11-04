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

  /// Nomes dos marketplaces em que cada produto da empresa está à venda
  /// (`disponivel`), pra coluna e filtro "Canais" da tabela no PC. Paginado:
  /// o Supabase corta em 1000 linhas e só o iFood já passa disso.
  /// [produtoIds] limita a alguns produtos (recarregar depois de salvar).
  Future<Map<String, Set<String>>> canaisDisponiveis({List<String>? produtoIds}) async {
    const pagina = 1000;
    final resultado = <String, Set<String>>{};
    for (var inicio = 0;; inicio += pagina) {
      var consulta = supabase.from('produto_canal').select('produto_id, marketplaces(nome)').eq('disponivel', true);
      if (produtoIds != null) consulta = consulta.inFilter('produto_id', produtoIds);
      final data = await consulta.order('produto_id').order('marketplace_id').range(inicio, inicio + pagina - 1);
      for (final row in (data as List).cast<Map<String, dynamic>>()) {
        final nome = (row['marketplaces'] as Map<String, dynamic>?)?['nome'] as String?;
        if (nome == null) continue;
        resultado.putIfAbsent(row['produto_id'] as String, () => <String>{}).add(nome);
      }
      if (data.length < pagina) break;
    }
    return resultado;
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

  /// Só o PREÇO de um canal que já existe — não cria canal nem mexe em
  /// `disponivel` (usado na revisão de preço: aplicar no iFood não deve
  /// ligar um produto que estava desligado lá). O trigger
  /// `trg_notificar_catalogo_produto_canal` envia a mudança pro marketplace.
  /// Espelha em `produtos.preco_ifood` (campo legado, ainda lido na
  /// exportação de planilha e regravado pela tela de edição) pra não ficar
  /// divergente — só quando [espelharPrecoIfoodLegado].
  Future<void> atualizarPreco({
    required String produtoId,
    required String marketplaceId,
    required double preco,
    bool espelharPrecoIfoodLegado = false,
  }) async {
    await supabase
        .from('produto_canal')
        .update({'preco': preco})
        .eq('produto_id', produtoId)
        .eq('marketplace_id', marketplaceId);
    if (espelharPrecoIfoodLegado) {
      await supabase.from('produtos').update({'preco_ifood': preco}).eq('id', produtoId);
    }
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
