import '../config/supabase_config.dart';
import '../models/marketplace.dart';

/// Leitura do catálogo de marketplaces (iFood, 99Food, Rappi, ...).
/// É uma tabela compartilhada entre empresas — só leitura pelo app,
/// não há criação/edição pelo tenant (RLS só libera SELECT).
class MarketplaceRepository {
  Future<List<Marketplace>> listarAtivos() async {
    final data = await supabase
        .from('marketplaces')
        .select()
        .eq('ativo', true)
        .order('nome', ascending: true);

    return (data as List)
        .map((row) => Marketplace.fromSupabase(row as Map<String, dynamic>))
        .toList();
  }
}
