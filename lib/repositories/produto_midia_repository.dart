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
  /// índice 0 = ordem 1, etc) — via RPC (`reordenar_midias_produto`) que
  /// grava tudo numa transação só, com a constraint única
  /// `(produto_id, tipo, ordem)` marcada `DEFERRABLE INITIALLY DEFERRED`
  /// (só checada no fim da transação, não a cada UPDATE). Antes disso era
  /// feito em 2 passadas no cliente com valores negativos temporários pra
  /// evitar colisão — funcionava no caso limpo, mas quebrava de verdade
  /// (`duplicate key`) sempre que já existia alguma linha presa em `ordem`
  /// negativa de uma tentativa anterior interrompida (cada `.update()` do
  /// cliente é sua própria transação, então o valor negativo temporário de
  /// uma linha podia colidir com o valor negativo já persistido de outra).
  Future<void> reordenar(List<String> idsNaOrdemFinal) async {
    await supabase.rpc('reordenar_midias_produto', params: {'p_ids': idsNaOrdemFinal});
  }
}
