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
  ///
  /// `motivoCodigo` é o código estruturado mandado pra API (`reason`) — pra
  /// rejeitar é obrigatório ser um dos 9 valores de `negotiationReasons`; pra
  /// aceitar é opcional e deve ser um dos `DisputaMarketplace.acceptReasons`
  /// daquela disputa específica. Nunca texto livre — a API responde
  /// `400 INVALID_REASON` (achado real lendo a doc oficial da Plataforma de
  /// Negociação). `motivo` é só a observação livre do lojista, vai pro
  /// `detailReason` (só usado no aceitar).
  Future<void> responder(
    String disputaId, {
    required bool aceitar,
    String? motivoCodigo,
    String? motivo,
  }) async {
    await supabase.from('marketplace_disputas').update({
      'status': aceitar ? 'aceita' : 'rejeitada',
      'motivo_resposta_codigo': motivoCodigo,
      'motivo_resposta': motivo,
    }).eq('id', disputaId);
  }

  /// Contraproposta (reembolso/benefício/tempo extra) usando uma das
  /// alternativas que a própria iFood ofereceu nessa disputa.
  /// `motivo` só se aplica a tempo extra (ADDITIONAL_TIME) — um dos
  /// `allowedsAdditionalTimeReasons` daquela alternativa específica.
  Future<void> responderComAlternativa(
    String disputaId, {
    required String alternativaIdExterno,
    required String tipo,
    double? valor,
    int? minutos,
    String? motivo,
  }) async {
    await supabase.from('marketplace_disputas').update({
      'status': 'alternativa',
      'alternativa_id_externo': alternativaIdExterno,
      'alternativa_tipo': tipo,
      'alternativa_valor': valor,
      'alternativa_minutos': minutos,
      'alternativa_motivo': motivo,
    }).eq('id', disputaId);
  }
}
