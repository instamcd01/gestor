import '../config/supabase_config.dart';
import '../models/rota_entrega.dart';

/// Acesso a dados de rotas de entrega (Fase 2 do custo real por venda, ver
/// [[gestor_custo_real_venda]]). Isolamento por empresa garantido pelo RLS
/// (`rotas_entrega_isolamento`/`rota_pedidos_isolamento`, via join com
/// `entregadores`/`pedidos`).
class RotaEntregaRepository {
  Future<List<RotaEntrega>> listarPorData(DateTime data) async {
    final dataIso = data.toIso8601String().split('T').first;
    final rows = await supabase
        .from('rotas_entrega')
        .select('*, entregador:entregadores(nome, custo_modo)')
        .eq('data_rota', dataIso)
        .order('created_at');
    return (rows as List).map((r) => RotaEntrega.fromSupabase(r as Map<String, dynamic>)).toList();
  }

  Future<String> criar({required String empresaId, required String entregadorId, required DateTime dataRota}) async {
    final row = await supabase
        .from('rotas_entrega')
        .insert({
          'empresa_id': empresaId,
          'entregador_id': entregadorId,
          'data_rota': dataRota.toIso8601String().split('T').first,
          'status': StatusRota.planejada,
        })
        .select('id')
        .single();
    return row['id'] as String;
  }

  Future<List<RotaPedidoItem>> pedidosDaRota(String rotaId) async {
    final rows =
        await supabase.from('rota_pedidos').select().eq('rota_id', rotaId).order('ordem', ascending: true);
    return (rows as List).map((r) => RotaPedidoItem.fromSupabase(r as Map<String, dynamic>)).toList();
  }

  /// Ids de pedidos que já estão em alguma rota ainda não concluída — usado
  /// pra não deixar o mesmo pedido entrar em duas rotas abertas ao mesmo
  /// tempo.
  Future<Set<String>> pedidosJaRoteados() async {
    final rotasAbertas = await supabase.from('rotas_entrega').select('id').neq('status', StatusRota.concluida);
    final rotaIds = (rotasAbertas as List).map((r) => r['id'] as String).toList();
    if (rotaIds.isEmpty) return {};

    final rows = await supabase.from('rota_pedidos').select('pedido_id').inFilter('rota_id', rotaIds);
    return (rows as List).map((r) => r['pedido_id'] as String).toSet();
  }

  Future<void> adicionarPedido(String rotaId, String pedidoId, int ordem) async {
    await supabase.from('rota_pedidos').insert({'rota_id': rotaId, 'pedido_id': pedidoId, 'ordem': ordem});
  }

  Future<void> removerPedido(String rotaId, String pedidoId) async {
    await supabase.from('rota_pedidos').delete().eq('rota_id', rotaId).eq('pedido_id', pedidoId);
  }

  Future<void> reordenar(String rotaId, List<String> pedidoIdsEmOrdem) async {
    for (var i = 0; i < pedidoIdsEmOrdem.length; i++) {
      await supabase
          .from('rota_pedidos')
          .update({'ordem': i})
          .eq('rota_id', rotaId)
          .eq('pedido_id', pedidoIdsEmOrdem[i]);
    }
  }

  Future<void> iniciar(String rotaId) async {
    await supabase.from('rotas_entrega').update({'status': StatusRota.emAndamento}).eq('id', rotaId);
  }

  Future<void> finalizar(String rotaId, {double? kmTotal}) async {
    await supabase.rpc('finalizar_rota_entrega', params: {'p_rota_id': rotaId, 'p_km_total': kmTotal});
  }

  Future<void> excluir(String rotaId) async {
    await supabase.from('rotas_entrega').delete().eq('id', rotaId);
  }
}
