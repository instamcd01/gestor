import '../config/supabase_config.dart';
import '../models/push_campanha.dart';

/// Filtro é um mapa de chaves fixas conhecidas pela RPC no banco
/// (segmento/especie_pet/porte_pet/cidade/categoria_comprada/
/// dias_sem_comprar_min/saldo_petcash_min/reaproveitar_view) — nunca SQL
/// vindo do cliente, mesma disciplina do resto do projeto.
class PushCampanhaRepository {
  Future<int> contarAudiencia(Map<String, dynamic> filtro) async {
    final data = await supabase.rpc('contar_audiencia_push_campanha', params: {'p_filtro': filtro});
    return (data as num).toInt();
  }

  Future<String> criar({
    required String titulo,
    required String mensagem,
    String? link,
    required Map<String, dynamic> filtro,
  }) async {
    final data = await supabase.rpc('criar_push_campanha', params: {
      'p_titulo': titulo,
      'p_mensagem': mensagem,
      'p_link': link,
      'p_filtro': filtro,
    });
    return data as String;
  }

  Future<List<PushCampanha>> listar() async {
    final data = await supabase.rpc('listar_push_campanhas');
    return (data as List).map((row) => PushCampanha.fromSupabase(row as Map<String, dynamic>)).toList();
  }
}
