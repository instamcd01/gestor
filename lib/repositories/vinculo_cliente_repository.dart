import '../config/supabase_config.dart';
import '../models/vinculo_cliente.dart';

/// Acesso à fila de sugestões de vínculo entre cadastros — ver
/// `VinculoCliente` pro contexto completo.
class VinculoClienteRepository {
  Future<List<VinculoCliente>> listarPendentes() async {
    final data = await supabase
        .from('vinculos_cliente_pendentes')
        .select('''
          id, criterio, created_at,
          cliente_novo:clientes!vinculos_cliente_pendentes_cliente_novo_id_fkey(id, nome, telefone, canal_origem),
          cliente_encontrado:clientes!vinculos_cliente_pendentes_cliente_encontrado_id_fkey(id, nome, telefone, canal_origem, total_pedidos, saldo, saldo_petcash)
        ''')
        .eq('status', 'pendente')
        .order('created_at');

    return (data as List)
        .map((row) => VinculoCliente.fromSupabase(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> aprovar(String vinculoId) async {
    await supabase.rpc('vincular_clientes', params: {'p_vinculo_id': vinculoId});
  }

  Future<void> rejeitar(String vinculoId) async {
    await supabase.rpc('rejeitar_vinculo', params: {'p_vinculo_id': vinculoId});
  }
}
