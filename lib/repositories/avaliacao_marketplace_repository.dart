import '../config/supabase_config.dart';
import '../models/avaliacao_marketplace.dart';

class AvaliacaoMarketplaceRepository {
  Future<List<AvaliacaoMarketplace>> listar() async {
    final data = await supabase
        .from('marketplace_pedidos')
        .select('id, pedido_id, avaliacao_marketplace, avaliacao_comentario, avaliacao_id_externo, '
            'avaliacao_resposta_loja, avaliacao_respondida_em, created_at, marketplaces(nome)')
        .not('avaliacao_marketplace', 'is', null)
        .order('created_at', ascending: false);

    return (data as List)
        .map((row) => AvaliacaoMarketplace.fromSupabase(row as Map<String, dynamic>))
        .toList();
  }

  /// Grava a resposta da loja. O trigger `trg_notificar_resposta_avaliacao`
  /// cuida de mandar pra iFood a partir daqui — não há chamada de API aqui.
  Future<void> responder(String marketplacePedidoId, String resposta) async {
    await supabase
        .from('marketplace_pedidos')
        .update({'avaliacao_resposta_loja': resposta}).eq('id', marketplacePedidoId);
  }
}
