import '../config/supabase_config.dart';
import '../models/item_carrinho_cliente.dart';

/// Acesso ao MESMO carrinho que o agente de WhatsApp e o site usam
/// (tabela `carrinho`/`carrinho_itens`, por cliente). As RPCs
/// `consultar_carrinho_app`/`alterar_carrinho_app` resolvem a empresa
/// sozinhas a partir do usuário autenticado — nunca passe empresa_id
/// daqui.
class CarrinhoClienteRepository {
  Future<CarrinhoCliente> consultar(String clienteId) async {
    final data = await supabase.rpc('consultar_carrinho_app', params: {
      'p_cliente_id': clienteId,
    });
    return CarrinhoCliente.fromJson({'carrinho': data as Map<String, dynamic>});
  }

  Future<CarrinhoCliente> removerItem(
    String clienteId, {
    String? produtoId,
    String? produtoBusca,
  }) async {
    final data = await supabase.rpc('alterar_carrinho_app', params: {
      'p_cliente_id': clienteId,
      'p_operacao': 'remover',
      'p_produto_id': produtoId,
      'p_produto_busca': produtoBusca,
    });
    return CarrinhoCliente.fromJson(data as Map<String, dynamic>);
  }

  Future<CarrinhoCliente> alterarQuantidade(
    String clienteId, {
    String? produtoId,
    String? produtoBusca,
    required int quantidade,
  }) async {
    final data = await supabase.rpc('alterar_carrinho_app', params: {
      'p_cliente_id': clienteId,
      'p_operacao': 'alterar_quantidade',
      'p_produto_id': produtoId,
      'p_produto_busca': produtoBusca,
      'p_quantidade': quantidade,
    });
    return CarrinhoCliente.fromJson(data as Map<String, dynamic>);
  }
}
