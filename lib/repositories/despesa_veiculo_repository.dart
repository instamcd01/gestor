import '../config/supabase_config.dart';
import '../models/despesa_veiculo.dart';

class DespesaVeiculoRepository {
  Future<List<DespesaVeiculo>> listarPorVeiculo(String veiculoId) async {
    final data = await supabase
        .from('despesas_veiculo')
        .select()
        .eq('veiculo_id', veiculoId)
        .order('data', ascending: false);
    return (data as List).map((row) => DespesaVeiculo.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  Future<void> criar(DespesaVeiculo despesa, {required String empresaId}) async {
    await supabase.from('despesas_veiculo').insert({...despesa.toSupabaseMap(), 'empresa_id': empresaId});
  }

  Future<void> remover(String id) async {
    await supabase.from('despesas_veiculo').delete().eq('id', id);
  }

  /// Custo/km real do veículo no período — `null` quando ainda não há pelo
  /// menos 2 leituras de km no período (dado insuficiente pra calcular).
  Future<double?> calcularCustoPorKm(String veiculoId, {required DateTime desde, required DateTime ate}) async {
    final resultado = await supabase.rpc('calcular_custo_por_km_veiculo', params: {
      'p_veiculo_id': veiculoId,
      'p_desde': desde.toIso8601String().split('T').first,
      'p_ate': ate.toIso8601String().split('T').first,
    });
    return (resultado as num?)?.toDouble();
  }
}
