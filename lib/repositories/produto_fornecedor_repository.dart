import '../config/supabase_config.dart';
import '../models/produto_fornecedor.dart';

/// Vínculos produto↔fornecedor (`produto_fornecedores`) e suas faixas de
/// desconto por quantidade (`faixas_desconto_produto_fornecedor`).
class ProdutoFornecedorRepository {
  static const _selectCompleto = '*, fornecedor:fornecedores(id, nome), faixas_desconto_produto_fornecedor(*)';

  Future<List<ProdutoFornecedor>> listarPorProduto(String produtoId) async {
    final data = await supabase
        .from('produto_fornecedores')
        .select(_selectCompleto)
        .eq('produto_id', produtoId)
        .order('principal', ascending: false);

    return (data as List).map((row) => ProdutoFornecedor.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  Future<ProdutoFornecedor> criar(ProdutoFornecedor vinculo, {required String empresaId}) async {
    if (vinculo.principal) {
      await _limparPrincipal(vinculo.produtoId);
    }
    final row = await supabase
        .from('produto_fornecedores')
        .insert({...vinculo.toSupabaseMap(), 'empresa_id': empresaId})
        .select(_selectCompleto)
        .single();
    final vinculoId = row['id'] as String;

    if (vinculo.faixasDesconto.isNotEmpty) {
      await supabase.from('faixas_desconto_produto_fornecedor').insert(
            vinculo.faixasDesconto.map((f) => {...f.toSupabaseMap(), 'produto_fornecedor_id': vinculoId}).toList(),
          );
    }

    return await _buscarPorId(vinculoId);
  }

  Future<ProdutoFornecedor> atualizar(ProdutoFornecedor vinculo) async {
    if (vinculo.id == null) {
      throw ArgumentError('Vínculo sem id não pode ser atualizado');
    }
    if (vinculo.principal) {
      await _limparPrincipal(vinculo.produtoId, exceto: vinculo.id);
    }
    await supabase.from('produto_fornecedores').update(vinculo.toSupabaseMap()).eq('id', vinculo.id!);

    // Substitui as faixas inteiras — mais simples que diff item a item, e
    // a lista costuma ser pequena (poucas faixas por fornecedor).
    await supabase.from('faixas_desconto_produto_fornecedor').delete().eq('produto_fornecedor_id', vinculo.id!);
    if (vinculo.faixasDesconto.isNotEmpty) {
      await supabase.from('faixas_desconto_produto_fornecedor').insert(
            vinculo.faixasDesconto.map((f) => {...f.toSupabaseMap(), 'produto_fornecedor_id': vinculo.id}).toList(),
          );
    }

    return await _buscarPorId(vinculo.id!);
  }

  Future<void> excluir(String vinculoId) async {
    await supabase.from('produto_fornecedores').delete().eq('id', vinculoId);
  }

  /// Chamado ao importar uma NF-e: mantém o vínculo produto↔fornecedor
  /// sempre refletindo a compra real, sem exigir cadastro manual. Se já
  /// existe vínculo com esse fornecedor pro produto, só atualiza o custo
  /// (preço mais recente pago); se não existe, cria um novo — marcando
  /// como principal só se for o primeiro fornecedor desse produto (não
  /// sobrescreve uma escolha manual de principal já feita).
  Future<void> vincularDeEntrada({
    required String produtoId,
    required String fornecedorId,
    required String empresaId,
    required double custoUnitario,
  }) async {
    if (custoUnitario <= 0) return;
    final existentes = await listarPorProduto(produtoId);
    final match = existentes.where((v) => v.fornecedorId == fornecedorId).toList();

    if (match.isNotEmpty) {
      final vinculo = match.first;
      if (vinculo.id != null && vinculo.custoUnitario != custoUnitario) {
        await supabase.from('produto_fornecedores').update({'custo_unitario': custoUnitario}).eq('id', vinculo.id!);
      }
      return;
    }

    await criar(
      ProdutoFornecedor(
        produtoId: produtoId,
        fornecedorId: fornecedorId,
        custoUnitario: custoUnitario,
        principal: existentes.isEmpty,
      ),
      empresaId: empresaId,
    );
  }

  Future<ProdutoFornecedor> _buscarPorId(String id) async {
    final row = await supabase.from('produto_fornecedores').select(_selectCompleto).eq('id', id).single();
    return ProdutoFornecedor.fromSupabase(row);
  }

  /// O índice único parcial (`produto_fornecedores_unico_principal`) só
  /// permite 1 linha com `principal = true` por produto — precisa
  /// desmarcar as outras antes de marcar uma nova, senão o insert/update
  /// falha com violação de unicidade.
  Future<void> _limparPrincipal(String produtoId, {String? exceto}) async {
    var query = supabase.from('produto_fornecedores').update({'principal': false}).eq('produto_id', produtoId);
    if (exceto != null) {
      query = query.neq('id', exceto);
    }
    await query;
  }
}
