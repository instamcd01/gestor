import '../config/supabase_config.dart';
import '../models/produto_midia.dart';

/// Acesso a dados de `produto_midias` (imagens e vídeos por link de um
/// produto). A sincronização com `produtos.imagem_url`/`imagem_url_secundaria`
/// (usadas pelo site e pelo auto-preenchimento por código de barras)
/// acontece via trigger no banco — não precisa ser replicada aqui.
class ProdutoMidiaRepository {
  Future<List<ProdutoMidia>> listar(String produtoId) async {
    final data = await supabase
        .from('produto_midias')
        .select()
        .eq('produto_id', produtoId)
        .order('tipo', ascending: true)
        .order('ordem', ascending: true);

    return (data as List)
        .map((row) => ProdutoMidia.fromSupabase(row as Map<String, dynamic>))
        .toList();
  }

  Future<ProdutoMidia> inserir({
    required String produtoId,
    required String empresaId,
    required String tipo,
    required String url,
    required int ordem,
  }) async {
    final row = await supabase
        .from('produto_midias')
        .insert({
          'produto_id': produtoId,
          'empresa_id': empresaId,
          'tipo': tipo,
          'url': url,
          'ordem': ordem,
        })
        .select()
        .single();
    return ProdutoMidia.fromSupabase(row);
  }

  Future<void> atualizarUrl(String id, String novaUrl) async {
    await supabase.from('produto_midias').update({'url': novaUrl}).eq('id', id);
  }

  Future<void> remover(String id) async {
    await supabase.from('produto_midias').delete().eq('id', id);
  }

  /// Renumera a `ordem` de uma lista de mídias (já na ordem final desejada,
  /// índice 0 = ordem 1, etc). Feito em duas passadas com valores negativos
  /// temporários pra nunca colidir com a constraint única
  /// `(produto_id, tipo, ordem)` no meio do processo (ex: trocar quem é 1 e
  /// quem é 2 direto daria conflito de unicidade na primeira atualização).
  Future<void> reordenar(List<String> idsNaOrdemFinal) async {
    for (var i = 0; i < idsNaOrdemFinal.length; i++) {
      await supabase
          .from('produto_midias')
          .update({'ordem': -(i + 1)})
          .eq('id', idsNaOrdemFinal[i]);
    }
    for (var i = 0; i < idsNaOrdemFinal.length; i++) {
      await supabase
          .from('produto_midias')
          .update({'ordem': i + 1})
          .eq('id', idsNaOrdemFinal[i]);
    }
  }
}
