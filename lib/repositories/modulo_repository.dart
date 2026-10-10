import '../config/supabase_config.dart';
import '../models/modulo.dart';

/// Catálogo de módulos (`modulos`) + quais estão ativos na loja
/// (`empresa_modulos`, RLS já restringe à própria empresa). Instalar e
/// desinstalar só pelas RPCs — elas checam dono e dependências no banco.
class ModuloRepository {
  Future<List<Modulo>> listar() async {
    final catalogo = await supabase.from('modulos').select().order('ordem', ascending: true);
    final ativos = await supabase.from('empresa_modulos').select('modulo_slug').eq('ativo', true);
    final slugsAtivos = {for (final row in ativos as List) row['modulo_slug'] as String};
    return (catalogo as List)
        .map((row) => Modulo.fromSupabase(
              row as Map<String, dynamic>,
              ativo: slugsAtivos.contains(row['slug']),
            ))
        .toList();
  }

  Future<void> instalar(String slug) => supabase.rpc('instalar_modulo', params: {'p_slug': slug});

  Future<void> desinstalar(String slug) => supabase.rpc('desinstalar_modulo', params: {'p_slug': slug});
}
