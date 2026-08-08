import '../config/supabase_config.dart';
import '../models/pedido_compra.dart';

/// Pedidos de compra a fornecedor (`pedidos_compra`/`itens_pedido_compra`)
/// e a RPC de sugestão automática (`sugestoes_pedido_compra`).
class PedidoCompraRepository {
  static const _selectCompleto = '''
    *,
    fornecedor:fornecedores(*),
    itens_pedido_compra(
      *,
      produto:produtos!itens_pedido_compra_produto_id_fkey(id, nome),
      produto_substituto:produtos!itens_pedido_compra_produto_substituto_id_fkey(id, nome)
    )
  ''';

  Future<List<PedidoCompra>> listar({StatusPedidoCompra? status}) async {
    var query = supabase.from('pedidos_compra').select(_selectCompleto);
    if (status != null) {
      query = query.eq('status', status.name);
    }
    final data = await query.order('created_at', ascending: false);
    return (data as List).map((row) => PedidoCompra.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  Future<PedidoCompra> buscarPorId(String id) async {
    final row = await supabase.from('pedidos_compra').select(_selectCompleto).eq('id', id).single();
    return PedidoCompra.fromSupabase(row);
  }

  /// Roda a análise de vendas + estoque + prazo de entrega e retorna a
  /// quantidade sugerida por produto, já agrupável por fornecedor na tela.
  Future<List<SugestaoCompra>> buscarSugestoes({
    required String empresaId,
    int diasAnalise = 30,
    int diasSeguranca = 7,
  }) async {
    final data = await supabase.rpc('sugestoes_pedido_compra', params: {
      'p_empresa_id': empresaId,
      'p_dias_analise': diasAnalise,
      'p_dias_seguranca': diasSeguranca,
    });
    return (data as List).map((row) => SugestaoCompra.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  Future<PedidoCompra> criar({
    required PedidoCompra pedido,
    required String empresaId,
    required List<ItemPedidoCompra> itens,
    String? criadoPor,
  }) async {
    final row = await supabase
        .from('pedidos_compra')
        .insert({...pedido.toSupabaseMap(), 'empresa_id': empresaId, 'criado_por': criadoPor})
        .select()
        .single();
    final pedidoId = row['id'] as String;

    if (itens.isNotEmpty) {
      await supabase.from('itens_pedido_compra').insert(
            itens.map((item) => {...item.toSupabaseMap(), 'pedido_compra_id': pedidoId}).toList(),
          );
    }

    return await buscarPorId(pedidoId);
  }

  Future<void> atualizarCabecalho(PedidoCompra pedido) async {
    if (pedido.id == null) {
      throw ArgumentError('Pedido sem id não pode ser atualizado');
    }
    await supabase.from('pedidos_compra').update(pedido.toSupabaseMap()).eq('id', pedido.id!);
  }

  Future<void> atualizarStatus(String pedidoId, StatusPedidoCompra status, {Map<String, dynamic>? camposExtras}) async {
    await supabase.from('pedidos_compra').update({'status': status.name, ...?camposExtras}).eq('id', pedidoId);
  }

  Future<void> substituirItens(String pedidoId, List<ItemPedidoCompra> itens) async {
    await supabase.from('itens_pedido_compra').delete().eq('pedido_compra_id', pedidoId);
    if (itens.isNotEmpty) {
      await supabase.from('itens_pedido_compra').insert(
            itens.map((item) => {...item.toSupabaseMap(), 'pedido_compra_id': pedidoId}).toList(),
          );
    }
  }

  Future<void> atualizarItem(ItemPedidoCompra item) async {
    if (item.id == null) {
      throw ArgumentError('Item sem id não pode ser atualizado');
    }
    await supabase.from('itens_pedido_compra').update(item.toSupabaseMap()).eq('id', item.id!);
  }

  Future<void> excluir(String pedidoId) async {
    await supabase.from('pedidos_compra').delete().eq('id', pedidoId);
  }
}
