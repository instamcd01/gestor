import '../config/supabase_config.dart';
import '../models/fornecedor.dart';

class FornecedorRepository {
  Future<List<Fornecedor>> listar() async {
    final data = await supabase
        .from('fornecedores')
        .select()
        .isFilter('deleted_at', null)
        .order('nome');

    return (data as List).map((row) => Fornecedor.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  Future<Fornecedor> criar(Fornecedor fornecedor, {required String empresaId}) async {
    final row = await supabase
        .from('fornecedores')
        .insert({...fornecedor.toSupabaseMap(), 'empresa_id': empresaId})
        .select()
        .single();
    return Fornecedor.fromSupabase(row);
  }

  Future<void> atualizar(Fornecedor fornecedor) async {
    if (fornecedor.id == null) {
      throw ArgumentError('Fornecedor sem id não pode ser atualizado');
    }
    await supabase.from('fornecedores').update(fornecedor.toSupabaseMap()).eq('id', fornecedor.id!);
  }

  /// Exclusão lógica — preserva histórico (despesas antigas continuam
  /// referenciando o fornecedor).
  Future<void> excluir(String fornecedorId) async {
    await supabase
        .from('fornecedores')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', fornecedorId);
  }
}
