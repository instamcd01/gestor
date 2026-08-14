class ItemCarrinhoCliente {
  final String produtoId;
  final String nome;
  final int quantidade;
  final double precoUnitario;
  final double subtotal;

  ItemCarrinhoCliente({
    required this.produtoId,
    required this.nome,
    required this.quantidade,
    required this.precoUnitario,
    required this.subtotal,
  });

  factory ItemCarrinhoCliente.fromJson(Map<String, dynamic> json) {
    return ItemCarrinhoCliente(
      produtoId: json['produto_id'] as String,
      nome: json['nome'] as String,
      quantidade: json['quantidade'] as int,
      precoUnitario: (json['preco_unitario'] as num).toDouble(),
      subtotal: (json['subtotal'] as num).toDouble(),
    );
  }
}

/// Carrinho compartilhado entre WhatsApp, site e app (tabela
/// `carrinho`/`carrinho_itens` no Supabase, por cliente). O app só lê e
/// altera essa mesma tabela — nunca duplica o carrinho.
class CarrinhoCliente {
  final List<ItemCarrinhoCliente> itens;
  final double valorTotal;
  final String? motivoUltimaOperacao;
  final List<ItemCarrinhoCliente>? itensCorrespondentes;

  CarrinhoCliente({
    required this.itens,
    required this.valorTotal,
    this.motivoUltimaOperacao,
    this.itensCorrespondentes,
  });

  bool get vazio => itens.isEmpty;

  factory CarrinhoCliente.fromJson(Map<String, dynamic> json) {
    final carrinhoJson = (json['carrinho'] ?? json) as Map<String, dynamic>;
    final itensJson = (carrinhoJson['itens'] as List?) ?? [];
    final correspondentesJson = json['itens_correspondentes'] as List?;
    return CarrinhoCliente(
      itens: itensJson
          .map((i) => ItemCarrinhoCliente.fromJson(i as Map<String, dynamic>))
          .toList(),
      valorTotal: (carrinhoJson['valor_total'] as num?)?.toDouble() ?? 0,
      motivoUltimaOperacao: json['motivo'] as String?,
      itensCorrespondentes: correspondentesJson
          ?.map((i) => ItemCarrinhoCliente.fromJson({
                'produto_id': i['produto_id'],
                'nome': i['nome'],
                'quantidade': 0,
                'preco_unitario': 0,
                'subtotal': 0,
              }))
          .toList(),
    );
  }
}
