import '../config/supabase_config.dart';
import '../models/zona_entrega.dart';

/// Acesso a dados das zonas de entrega (faixas de distância x preço).
/// Isolamento por empresa garantido pelo RLS.
class ZonaEntregaRepository {
  Future<List<ZonaEntrega>> listar() async {
    final data = await supabase.from('zonas_entrega').select().order('distancia_min_km');

    return (data as List)
        .map((row) => ZonaEntrega.fromSupabase(row as Map<String, dynamic>))
        .toList();
  }

  Future<ZonaEntrega> criar(ZonaEntrega zona, {required String empresaId}) async {
    final inserida = await supabase
        .from('zonas_entrega')
        .insert({...zona.toSupabaseMap(), 'empresa_id': empresaId})
        .select()
        .single();

    return ZonaEntrega.fromSupabase(inserida);
  }

  Future<void> atualizar(ZonaEntrega zona) async {
    if (zona.id == null) {
      throw ArgumentError('Zona sem id não pode ser atualizada');
    }
    await supabase.from('zonas_entrega').update(zona.toSupabaseMap()).eq('id', zona.id!);
  }

  Future<void> excluir(String id) async {
    await supabase.from('zonas_entrega').delete().eq('id', id);
  }
}
