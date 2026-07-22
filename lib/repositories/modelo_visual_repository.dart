import '../config/supabase_config.dart';
import '../models/modelo_visual.dart';

/// Leitura do catálogo de modelos visuais. Tabela compartilhada entre
/// empresas — só SELECT pelo tenant, sem criação/edição (RLS só libera
/// leitura de linhas ativas). Novos modelos entram via SQL direto.
class ModeloVisualRepository {
  Future<List<ModeloVisual>> listarAtivos() async {
    final data = await supabase
        .from('modelos_visuais')
        .select()
        .eq('ativo', true)
        .order('ordem');

    return (data as List).map((row) => ModeloVisual.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  Future<ModeloVisual?> buscarPorId(String id) async {
    final row = await supabase.from('modelos_visuais').select().eq('id', id).maybeSingle();
    return row != null ? ModeloVisual.fromSupabase(row) : null;
  }
}
