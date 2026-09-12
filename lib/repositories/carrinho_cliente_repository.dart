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

  /// Substitui por completo o carrinho ativo de um cliente pelo que está
  /// montado no app (staff "salvando" um orçamento em andamento pra
  /// atender outro cliente em paralelo) — mesma tabela compartilhada com
  /// WhatsApp/site. [itens] é `[{'produto_id': ..., 'quantidade': ...}]`;
  /// preço e limite de estoque são sempre recalculados pela RPC a partir
  /// do catálogo atual, nunca confia no que o app mandou.
  Future<CarrinhoCliente> salvarComoStaff(String clienteId, List<Map<String, dynamic>> itens) async {
    final data = await supabase.rpc('salvar_carrinho_staff', params: {
      'p_cliente_id': clienteId,
      'p_itens': itens,
    });
    return CarrinhoCliente.fromJson({'carrinho': data as Map<String, dynamic>});
  }

  /// Todo carrinho ativo/não vazio de hoje — alimenta "Carrinhos do dia"
  /// em `VendasScreen`.
  Future<List<CarrinhoAtivoResumo>> listarAtivosHoje() async {
    final data = await supabase.rpc('listar_carrinhos_ativos_staff');
    return (data as List).map((row) => CarrinhoAtivoResumo.fromJson(row as Map<String, dynamic>)).toList();
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

  /// "Comprar novamente": soma os itens de um pedido antigo ao carrinho
  /// ATIVO do cliente (preço sempre o atual da loja) — não substitui o que
  /// já está no carrinho. Item indisponível/descontinuado não trava o
  /// resto, só aparece marcado em [RepetirPedidoResultado.indisponiveis].
  Future<RepetirPedidoResultado> repetirPedido(String pedidoId) async {
    final data = await supabase.rpc('repetir_pedido_app', params: {'p_pedido_id': pedidoId});
    return RepetirPedidoResultado.fromJson(data as Map<String, dynamic>);
  }
}
