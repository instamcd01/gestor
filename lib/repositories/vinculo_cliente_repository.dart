import '../config/supabase_config.dart';
import '../models/cliente.dart';
import '../models/vinculo_cliente.dart';

/// Acesso à fila de sugestões de vínculo entre cadastros — ver
/// `VinculoCliente` pro contexto completo.
class VinculoClienteRepository {
  Future<List<VinculoCliente>> listarPendentes() async {
    final data = await supabase
        .from('vinculos_cliente_pendentes')
        .select('''
          id, criterio, created_at,
          cliente_novo:clientes!vinculos_cliente_pendentes_cliente_novo_id_fkey(id, nome, telefone, canal_origem, total_pedidos, saldo, saldo_petcash),
          cliente_encontrado:clientes!vinculos_cliente_pendentes_cliente_encontrado_id_fkey(id, nome, telefone, canal_origem, total_pedidos, saldo, saldo_petcash)
        ''')
        .eq('status', 'pendente')
        .order('created_at', ascending: true);

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

  /// Vínculo escolhido pelo staff na ficha do cliente (sem sugestão
  /// automática). O banco decide qual fica como principal (quem tem login no
  /// site; empate = grupo com mais pedidos) e devolve o id dele.
  Future<String> vincularManual(String clienteA, String clienteB) async {
    final principal = await supabase.rpc(
      'vincular_clientes_manual',
      params: {'p_cliente_a': clienteA, 'p_cliente_b': clienteB},
    );
    return principal as String;
  }

  /// Solta um cadastro vinculado do principal — os dois voltam a contar só
  /// os próprios pedidos.
  Future<void> desvincular(String clienteVinculadoId) async {
    await supabase.rpc('desvincular_cliente', params: {'p_cliente_id': clienteVinculadoId});
  }

  /// Todos os cadastros da mesma pessoa (inclui o próprio), principal primeiro.
  Future<List<Cliente>> listarGrupo(String clienteId) async {
    final grupo = await supabase.rpc('listar_grupo_pessoa', params: {'p_cliente_id': clienteId});
    final ids = (grupo as List).map((r) => r['id'] as String).toList();
    if (ids.length <= 1) return [];

    final data = await supabase.from('clientes').select('*, pets(*)').inFilter('id', ids);
    final clientes = (data as List).map((row) => Cliente.fromSupabase(row as Map<String, dynamic>)).toList();
    clientes.sort((a, b) => (a.pessoaId == null ? 0 : 1).compareTo(b.pessoaId == null ? 0 : 1));
    return clientes;
  }
}
