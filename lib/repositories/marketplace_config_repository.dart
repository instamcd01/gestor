import '../config/supabase_config.dart';
import '../models/marketplace_config.dart';

/// Credenciais de integração por marketplace (RLS restringe a leitura só
/// pro dono da empresa — ver migration `configuracoes_gerais_pedidos_
/// recibo_pagamento_integracoes`). Se o usuário logado não for dono, as
/// consultas aqui retornam vazio.
class MarketplaceConfigRepository {
  Future<List<MarketplaceConfig>> listar() async {
    final data = await supabase.from('empresa_marketplace_config').select();
    return (data as List).map((row) => MarketplaceConfig.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  Future<void> salvar(MarketplaceConfig config, {required String empresaId}) async {
    await supabase.from('empresa_marketplace_config').upsert(
      {...config.toSupabaseMap(), 'empresa_id': empresaId},
      onConflict: 'empresa_id,marketplace_id',
    );
  }
}
