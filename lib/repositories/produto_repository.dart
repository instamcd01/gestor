import '../config/supabase_config.dart';
import '../models/produto.dart';

/// Camada de acesso a dados de produtos. Fala diretamente com o Supabase.
/// O isolamento por empresa é garantido pelo RLS no banco — não precisamos
/// (nem devemos) filtrar por empresa_id manualmente aqui nas consultas de
/// leitura, o Postgres já faz isso.
class ProdutoRepository {
  static const _selectComEstoque =
      '*, estoque(id, quantidade_atual, quantidade_minima, deposito_id)';

  Future<List<Produto>> listar() async {
    final data = await supabase
        .from('produtos')
        .select(_selectComEstoque)
        .isFilter('deleted_at', null)
        .order('nome');

    return (data as List)
        .map((row) => Produto.fromSupabase(row as Map<String, dynamic>))
        .toList();
  }

  /// Cria o produto e já garante uma linha de estoque associada
  /// (quantidade zerada até o usuário definir, sem depósito ainda).
  Future<Produto> criar(Produto produto, {required String empresaId}) async {
    final produtoInserido = await supabase
        .from('produtos')
        .insert({...produto.toSupabaseMap(), 'empresa_id': empresaId})
        .select()
        .single();

    final produtoId = produtoInserido['id'] as String;

    final estoqueInserido = await supabase
        .from('estoque')
        .insert({
          'empresa_id': empresaId,
          'produto_id': produtoId,
          'quantidade_atual': produto.estoqueAtual,
          'quantidade_minima': produto.estoqueMinimo,
        })
        .select()
        .single();

    return Produto.fromSupabase({
      ...produtoInserido,
      'estoque': [estoqueInserido],
    });
  }

  Future<void> atualizar(Produto produto) async {
    if (produto.id == null) {
      throw ArgumentError('Produto sem id não pode ser atualizado');
    }

    await supabase
        .from('produtos')
        .update(produto.toSupabaseMap())
        .eq('id', produto.id!);

    if (produto.estoqueId != null) {
      await supabase.from('estoque').update({
        'quantidade_atual': produto.estoqueAtual,
        'quantidade_minima': produto.estoqueMinimo,
      }).eq('id', produto.estoqueId!);
    }
  }

  /// Exclusão lógica — preserva histórico (vendas antigas continuam
  /// referenciando o produto) em vez de apagar a linha de verdade.
  Future<void> excluir(String produtoId) async {
    await supabase
        .from('produtos')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', produtoId);
  }
}
