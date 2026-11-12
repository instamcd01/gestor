import '../config/supabase_config.dart';
import '../models/pausa_loja.dart';

class PausaLojaRepository {
  /// Ativa (no máximo 1 por vez) + agendadas futuras — pra mostrar tudo
  /// numa tela só (status atual e o que já está marcado pra frente).
  Future<List<PausaLoja>> listarAtivasOuAgendadas() async {
    final data = await supabase
        .from('pausas_loja')
        .select()
        .inFilter('status', ['ativa', 'agendada'])
        .order('inicio');

    return (data as List).map((row) => PausaLoja.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  /// `inicio` no passado/presente já nasce 'ativa' (efeito imediato, sem
  /// esperar o próximo tick do cron); no futuro nasce 'agendada' e o
  /// pg_cron promove sozinho na hora certa. O trigger
  /// `trg_propagar_pausa_marketplace` cuida de refletir em
  /// iFood/99Food quando vira 'ativa'.
  Future<void> criar({
    required String empresaId,
    required String? criadoPor,
    String? motivo,
    required DateTime inicio,
    required DateTime fim,
    List<String>? canais,
  }) async {
    final status = !inicio.isAfter(DateTime.now()) ? 'ativa' : 'agendada';
    await supabase.from('pausas_loja').insert({
      'empresa_id': empresaId,
      'criado_por': criadoPor,
      'motivo': motivo,
      'inicio': inicio.toUtc().toIso8601String(),
      'fim': fim.toUtc().toIso8601String(),
      'status': status,
      'canais': canais,
    });
  }

  /// Interrupções geradas pelas pausas (status real em cada marketplace: pendente/ativa/erro).
  Future<List<Map<String, dynamic>>> interrupcoesDasPausas(List<String> pausaIds) async {
    final data = await supabase
        .from('marketplace_interrupcoes')
        .select('origem_pausa_id, marketplace_id, status, erro')
        .inFilter('origem_pausa_id', pausaIds);
    return (data as List).cast<Map<String, dynamic>>();
  }

  /// Marketplaces ligados na empresa (id + nome) — pra escolher em quais
  /// canais a pausa vale.
  Future<List<({String id, String nome})>> listarMarketplacesAtivos() async {
    final data = await supabase
        .from('empresa_marketplace_config')
        .select('marketplace_id, marketplaces(nome)')
        .eq('ativo', true);
    return (data as List).map((row) {
      final r = row as Map<String, dynamic>;
      return (id: r['marketplace_id'].toString(), nome: (r['marketplaces'] as Map?)?['nome']?.toString() ?? 'Marketplace');
    }).toList();
  }

  /// Cancela antes do fim — o trigger cuida de cancelar em cascata as
  /// interrupções de marketplace que essa pausa tinha criado.
  Future<void> cancelar(String pausaId) async {
    await supabase.from('pausas_loja').update({'status': 'cancelada'}).eq('id', pausaId);
  }
}
