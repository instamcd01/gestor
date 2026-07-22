import '../config/supabase_config.dart';
import '../models/movimentacao_saldo.dart';

/// Extrato de crédito/débito do saldo do cliente. Todo crédito/débito passa
/// pela função `registrar_movimentacao_saldo` no banco — ela grava o novo
/// saldo em `clientes` e a movimentação em `movimentacoes_saldo` na mesma
/// transação, então o extrato nunca fica incompleto ou fora de sincronia.
class SaldoRepository {
  Future<List<MovimentacaoSaldo>> listarPorCliente(String clienteId) async {
    final data = await supabase
        .from('movimentacoes_saldo')
        .select()
        .eq('cliente_id', clienteId)
        .order('created_at', ascending: false);

    return (data as List)
        .map((row) => MovimentacaoSaldo.fromSupabase(row as Map<String, dynamic>))
        .toList();
  }

  /// Retorna o novo saldo do cliente após a movimentação.
  Future<double> registrarMovimentacao({
    required String clienteId,
    required String tipo,
    required double valor,
    String? motivo,
    String? pedidoId,
  }) async {
    final novoSaldo = await supabase.rpc('registrar_movimentacao_saldo', params: {
      'p_cliente_id': clienteId,
      'p_tipo': tipo,
      'p_valor': valor,
      'p_motivo': motivo,
      'p_pedido_id': pedidoId,
    });
    return (novoSaldo as num).toDouble();
  }
}
