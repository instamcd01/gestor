import '../config/supabase_config.dart';
import '../models/reconciliacao_historico.dart';

/// Histórico permanente de reconciliação/exportação por marketplace (RLS
/// restringe ao dono da empresa, igual `MarketplaceConfigRepository`).
class ReconciliacaoHistoricoRepository {
  Future<List<ReconciliacaoHistorico>> listar(String marketplaceId, {int limite = 50}) async {
    final data = await supabase
        .from('marketplace_reconciliacao_historico')
        .select()
        .eq('marketplace_id', marketplaceId)
        .order('executado_em', ascending: false)
        .limit(limite);
    return (data as List).map((row) => ReconciliacaoHistorico.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  /// Registra um evento (hoje só usado pra exportação manual de catálogo
  /// feita direto do app — as reconciliações de estoque/financeiro são
  /// registradas pelo próprio workflow n8n, que já tem os números exatos).
  Future<void> registrar({
    required String empresaId,
    required String marketplaceId,
    required String tipo,
    required Map<String, dynamic> detalhes,
    required String mensagem,
  }) async {
    await supabase.from('marketplace_reconciliacao_historico').insert({
      'empresa_id': empresaId,
      'marketplace_id': marketplaceId,
      'tipo': tipo,
      'detalhes': detalhes,
      'mensagem': mensagem,
    });
  }
}
