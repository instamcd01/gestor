import '../config/supabase_config.dart';
import '../models/veiculo.dart';

class VeiculoRepository {
  Future<List<Veiculo>> listar({bool apenasAtivos = false}) async {
    var query = supabase.from('veiculos').select();
    if (apenasAtivos) query = query.eq('ativo', true);
    final data = await query.order('nome');
    return (data as List).map((row) => Veiculo.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  Future<Veiculo> criar(Veiculo veiculo, {required String empresaId}) async {
    final row = await supabase
        .from('veiculos')
        .insert({...veiculo.toSupabaseMap(), 'empresa_id': empresaId})
        .select()
        .single();
    return Veiculo.fromSupabase(row);
  }

  Future<void> atualizar(Veiculo veiculo) async {
    await supabase.from('veiculos').update(veiculo.toSupabaseMap()).eq('id', veiculo.id!);
  }
}
