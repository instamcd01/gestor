import '../config/supabase_config.dart';
import '../models/disputa_marketplace.dart';

class DisputaMarketplaceRepository {
  Future<List<DisputaMarketplace>> listar() async {
    final data = await supabase
        .from('marketplace_disputas')
        .select('*, marketplaces(nome)')
        .order('created_at', ascending: false);

    return (data as List)
        .map((row) => DisputaMarketplace.fromSupabase(row as Map<String, dynamic>))
        .toList();
  }

  /// Aceitar ou rejeitar uma disputa. O trigger `trg_notificar_resposta_disputa`
  /// cuida de mandar a decisão pra iFood a partir daqui — não há chamada de
  /// API aqui, e essa decisão nunca deve ser tomada automaticamente.
  Future<void> responder(String disputaId, {required bool aceitar, String? motivo}) async {
    await supabase.from('marketplace_disputas').update({
      'status': aceitar ? 'aceita' : 'rejeitada',
      'motivo_resposta': motivo,
    }).eq('id', disputaId);
  }

  /// Contraproposta (reembolso/benefício/tempo extra) usando uma das
  /// alternativas que a própria iFood ofereceu nessa disputa.
  Future<void> responderComAlternativa(
    String disputaId, {
    required String alternativaIdExterno,
    required String tipo,
    double? valor,
    int? minutos,
  }) async {
    await supabase.from('marketplace_disputas').update({
      'status': 'alternativa',
      'alternativa_id_externo': alternativaIdExterno,
      'alternativa_tipo': tipo,
      'alternativa_valor': valor,
      'alternativa_minutos': minutos,
    }).eq('id', disputaId);
  }
}
