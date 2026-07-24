import '../config/supabase_config.dart';

/// Separação de pedido de Mercado na iFood (Picking API) — trocar/remover
/// item em falta na hora de separar o pedido. Todas as escritas aqui
/// disparam triggers no banco que chamam a API de verdade via n8n; o app
/// nunca fala com a iFood diretamente.
class SeparacaoPedidoRepository {
  Future<void> iniciar(String marketplacePedidoId) async {
    await supabase
        .from('marketplace_pedidos')
        .update({'separacao_status': 'separando', 'separacao_erro': null}).eq('id', marketplacePedidoId);
  }

  Future<void> finalizar(String marketplacePedidoId) async {
    await supabase
        .from('marketplace_pedidos')
        .update({'separacao_status': 'finalizada', 'separacao_erro': null}).eq('id', marketplacePedidoId);
  }

  Future<void> removerItem({required String marketplacePedidoId, required String itemPedidoId}) async {
    await supabase.from('marketplace_separacao_acoes').insert({
      'marketplace_pedido_id': marketplacePedidoId,
      'item_pedido_id': itemPedidoId,
      'tipo_acao': 'remover',
    });
  }

  Future<void> substituirItem({
    required String marketplacePedidoId,
    required String itemPedidoId,
    required String produtoSubstitutoId,
    required double quantidade,
  }) async {
    await supabase.from('marketplace_separacao_acoes').insert({
      'marketplace_pedido_id': marketplacePedidoId,
      'item_pedido_id': itemPedidoId,
      'tipo_acao': 'substituir',
      'produto_substituto_id': produtoSubstitutoId,
      'quantidade': quantidade,
    });
  }
}
