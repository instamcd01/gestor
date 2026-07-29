import '../config/supabase_config.dart';
import '../models/despesa.dart';

class DespesaRepository {
  static const _selectComFornecedor = '*, fornecedor:fornecedores(*)';

  Future<List<Despesa>> listar() async {
    final data = await supabase
        .from('despesas')
        .select(_selectComFornecedor)
        .isFilter('deleted_at', null)
        .order('data_vencimento', ascending: false);

    return (data as List).map((row) => Despesa.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  Future<Despesa> criar(Despesa despesa, {required String empresaId, String? criadoPor, String? fornecedorId}) async {
    final row = await supabase
        .from('despesas')
        .insert({
          ...despesa.toSupabaseMap(fornecedorId: fornecedorId),
          'empresa_id': empresaId,
          'criado_por': criadoPor,
        })
        .select(_selectComFornecedor)
        .single();
    return Despesa.fromSupabase(row);
  }

  Future<void> atualizar(Despesa despesa) async {
    if (despesa.id == null) {
      throw ArgumentError('Despesa sem id não pode ser atualizada');
    }
    await supabase.from('despesas').update(despesa.toSupabaseMap()).eq('id', despesa.id!);
  }

  Future<void> marcarComoPaga(String despesaId, {required String metodoPagamento, DateTime? dataPagamento}) async {
    await supabase.from('despesas').update({
      'status': StatusDespesa.pago,
      'metodo_pagamento': metodoPagamento,
      'data_pagamento': (dataPagamento ?? DateTime.now()).toIso8601String().split('T').first,
    }).eq('id', despesaId);
  }

  Future<void> cancelar(String despesaId) async {
    await supabase.from('despesas').update({
      'status': StatusDespesa.cancelado,
      'data_cancelamento': DateTime.now().toIso8601String(),
    }).eq('id', despesaId);
  }

  Future<void> excluir(String despesaId) async {
    await supabase
        .from('despesas')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', despesaId);
  }
}
