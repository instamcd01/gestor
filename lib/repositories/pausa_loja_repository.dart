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
  }) async {
    final status = !inicio.isAfter(DateTime.now()) ? 'ativa' : 'agendada';
    await supabase.from('pausas_loja').insert({
      'empresa_id': empresaId,
      'criado_por': criadoPor,
      'motivo': motivo,
      'inicio': inicio.toUtc().toIso8601String(),
      'fim': fim.toUtc().toIso8601String(),
      'status': status,
    });
  }

  /// Cancela antes do fim — o trigger cuida de cancelar em cascata as
  /// interrupções de marketplace que essa pausa tinha criado.
  Future<void> cancelar(String pausaId) async {
    await supabase.from('pausas_loja').update({'status': 'cancelada'}).eq('id', pausaId);
  }
}
