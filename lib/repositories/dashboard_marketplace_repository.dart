import '../config/supabase_config.dart';
import '../models/marketplace_pedido_financeiro.dart';

/// Leitura dos dados financeiros de pedidos vindos de marketplace, pra
/// alimentar o dashboard financeiro por canal. Parte de `pedidos` (que já
/// tem RLS direto por `empresa_id`) e embute `marketplace_pedidos` (as
/// taxas/valores capturados pela integração) e `marketplaces` (nome do
/// canal) — nenhuma das duas tem `empresa_id` própria, então a leitura
/// direta delas violaria RLS.
class DashboardMarketplaceRepository {
  Future<List<MarketplacePedidoFinanceiro>> listarPorPeriodo({
    required DateTime inicio,
    required DateTime fim,
  }) async {
    final data = await supabase
        .from('pedidos')
        .select('id, created_at, status, valor_total, marketplaces(nome), marketplace_pedidos(*)')
        .not('marketplace_id', 'is', null)
        .gte('created_at', inicio.toIso8601String())
        .lte('created_at', fim.toIso8601String())
        .order('created_at', ascending: false);

    return (data as List)
        .map((row) => MarketplacePedidoFinanceiro.fromSupabase(row as Map<String, dynamic>))
        .toList();
  }
}
