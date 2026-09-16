import '../config/supabase_config.dart';
import '../models/margem_alvo_categoria.dart';

/// Margem-alvo por categoria/subcategoria (base do preço sugerido no
/// cadastro/edição de produto) — ver `calcular_preco_sugerido` no banco
/// pra quem aplica isso de fato num produto específico.
class MargemAlvoCategoriaRepository {
  Future<List<MargemAlvoCategoria>> listar() async {
    final data = await supabase.from('margem_alvo_categoria').select();
    return (data as List).map((row) => MargemAlvoCategoria.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  /// Upsert por (empresa, categoria, subcategoria) — chamando de novo pra
  /// uma linha já existente atualiza em vez de duplicar.
  Future<void> salvar({
    required String empresaId,
    required String categoria,
    String subcategoria = '',
    required double margemAlvoPercentual,
  }) async {
    await supabase.from('margem_alvo_categoria').upsert(
      {
        'empresa_id': empresaId,
        'categoria': categoria,
        'subcategoria': subcategoria,
        'margem_alvo_percentual': margemAlvoPercentual,
      },
      onConflict: 'empresa_id,categoria,subcategoria',
    );
  }

  Future<void> remover(String id) async {
    await supabase.from('margem_alvo_categoria').delete().eq('id', id);
  }
}
