import '../config/supabase_config.dart';
import '../models/interrupcao_marketplace.dart';

class InterrupcaoMarketplaceRepository {
  /// Pausa ativa ou ainda sendo criada, se houver — só uma por vez faz
  /// sentido mostrar na tela.
  Future<InterrupcaoMarketplace?> buscarAtiva() async {
    final data = await supabase
        .from('marketplace_interrupcoes')
        .select()
        .inFilter('status', ['pendente', 'ativa'])
        .order('created_at', ascending: false)
        .limit(1);

    final rows = data as List;
    if (rows.isEmpty) return null;
    return InterrupcaoMarketplace.fromSupabase(rows.first as Map<String, dynamic>);
  }

  /// O trigger `trg_notificar_interrupcao_insert` cuida de criar a pausa
  /// de verdade na iFood a partir daqui.
  Future<void> pausar({
    required String empresaId,
    required String marketplaceId,
    required String motivo,
    required DateTime fim,
  }) async {
    await supabase.from('marketplace_interrupcoes').insert({
      'empresa_id': empresaId,
      'marketplace_id': marketplaceId,
      'motivo': motivo,
      'fim': fim.toUtc().toIso8601String(),
    });
  }

  /// O trigger `trg_notificar_interrupcao_cancelar` cuida de cancelar de
  /// verdade na iFood a partir daqui.
  Future<void> cancelar(String interrupcaoId) async {
    await supabase.from('marketplace_interrupcoes').update({'status': 'cancelada'}).eq('id', interrupcaoId);
  }
}
