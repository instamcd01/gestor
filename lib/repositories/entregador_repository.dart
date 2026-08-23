import '../config/supabase_config.dart';
import '../models/entregador.dart';

/// Acesso a dados dos entregadores (Fase 2 do custo real por venda —
/// [[gestor_custo_real_venda]]). Isolamento por empresa garantido pelo RLS
/// (`entregadores_isolamento`).
class EntregadorRepository {
  Future<List<Entregador>> listar() async {
    final data =
        await supabase.from('entregadores').select().isFilter('deleted_at', null).order('nome', ascending: true);
    return (data as List).map((row) => Entregador.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  Future<Entregador> criar(Entregador entregador, {required String empresaId}) async {
    final inserido = await supabase
        .from('entregadores')
        .insert({...entregador.toSupabaseMap(), 'empresa_id': empresaId})
        .select()
        .single();
    return Entregador.fromSupabase(inserido);
  }

  Future<void> atualizar(Entregador entregador) async {
    if (entregador.id == null) {
      throw ArgumentError('Entregador sem id não pode ser atualizado');
    }
    await supabase.from('entregadores').update(entregador.toSupabaseMap()).eq('id', entregador.id!);
  }

  Future<void> excluir(String id) async {
    await supabase.from('entregadores').update({'deleted_at': DateTime.now().toIso8601String()}).eq('id', id);
  }
}
