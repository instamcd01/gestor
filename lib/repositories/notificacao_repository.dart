import '../config/supabase_config.dart';
import '../models/notificacao.dart';

/// Lê, marca como lida e exclui — inserir uma notificação continua sendo
/// responsabilidade exclusiva das triggers/jobs no banco (ver
/// `models/notificacao.dart`); a limpeza automática de lidas antigas
/// também roda só no banco (`limpar_notificacoes_antigas`, via pg_cron).
class NotificacaoRepository {
  Future<List<Notificacao>> listar() async {
    final data = await supabase
        .from('notificacoes')
        .select()
        .order('created_at', ascending: false)
        .limit(100);

    return (data as List).map((row) => Notificacao.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  Future<void> marcarComoLida(String id) async {
    await supabase.from('notificacoes').update({'lida': true}).eq('id', id);
  }

  Future<void> marcarTodasComoLidas() async {
    await supabase.from('notificacoes').update({'lida': true}).eq('lida', false);
  }

  Future<void> excluir(String id) async {
    await supabase.from('notificacoes').delete().eq('id', id);
  }

  Future<void> excluirLidas() async {
    await supabase.from('notificacoes').delete().eq('lida', true);
  }

  Future<int> buscarRetencaoDias(String empresaId) async {
    final data = await supabase.from('empresas').select('retencao_notificacoes_dias').eq('id', empresaId).single();
    return data['retencao_notificacoes_dias'] as int? ?? 30;
  }

  Future<void> salvarRetencaoDias(String empresaId, int dias) async {
    await supabase.from('empresas').update({'retencao_notificacoes_dias': dias}).eq('id', empresaId);
  }

  Future<Map<String, bool>> buscarPreferencias(String empresaId) async {
    final data = await supabase.from('empresas').select('preferencias_notificacao').eq('id', empresaId).single();
    final raw = data['preferencias_notificacao'] as Map<String, dynamic>? ?? {};
    return raw.map((chave, valor) => MapEntry(chave, valor as bool));
  }

  Future<void> salvarPreferencias(String empresaId, Map<String, bool> preferencias) async {
    await supabase.from('empresas').update({'preferencias_notificacao': preferencias}).eq('id', empresaId);
  }
}
