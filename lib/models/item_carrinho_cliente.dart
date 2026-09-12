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
  final DateTime? criadoEm;
  final DateTime? atualizadoEm;

  CarrinhoCliente({
    required this.itens,
    required this.valorTotal,
    this.motivoUltimaOperacao,
    this.itensCorrespondentes,
    this.criadoEm,
    this.atualizadoEm,
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
      criadoEm: carrinhoJson['criado_em'] != null ? DateTime.parse(carrinhoJson['criado_em'] as String) : null,
      atualizadoEm:
          carrinhoJson['atualizado_em'] != null ? DateTime.parse(carrinhoJson['atualizado_em'] as String) : null,
    );
  }
}

/// Resultado de repetir UM item de um pedido antigo no carrinho atual
/// (`repetir_pedido_app`/`repetir_pedido_whatsapp`) — [autorizado] = false
/// quando o produto não pôde entrar (indisponível, descontinuado etc);
/// [motivo] traz o porquê pra mostrar ao usuário, nunca trava os outros itens.
class ItemRepetidoResultado {
  final String produtoNome;
  final bool autorizado;
  final String? motivo;

  ItemRepetidoResultado({required this.produtoNome, required this.autorizado, this.motivo});

  factory ItemRepetidoResultado.fromJson(Map<String, dynamic> json) {
    return ItemRepetidoResultado(
      produtoNome: json['produto_nome']?.toString() ?? '',
      autorizado: json['autorizado'] as bool? ?? false,
      motivo: json['motivo'] as String?,
    );
  }
}

/// Resultado completo de "Comprar novamente" — os itens do pedido antigo
/// (um a um, com o que deu certo/errado) mais o carrinho já atualizado.
class RepetirPedidoResultado {
  final List<ItemRepetidoResultado> itens;
  final CarrinhoCliente carrinho;

  RepetirPedidoResultado({required this.itens, required this.carrinho});

  int get qtdAdicionados => itens.where((i) => i.autorizado).length;
  List<ItemRepetidoResultado> get indisponiveis => itens.where((i) => !i.autorizado).toList();

  factory RepetirPedidoResultado.fromJson(Map<String, dynamic> json) {
    final itensJson = (json['itens'] as List?) ?? [];
    return RepetirPedidoResultado(
      itens: itensJson.map((i) => ItemRepetidoResultado.fromJson(i as Map<String, dynamic>)).toList(),
      carrinho: CarrinhoCliente.fromJson(json),
    );
  }
}

/// Linha da lista "Carrinhos do dia" (`VendasScreen`) — resumo de todo
/// carrinho ativo/não vazio de hoje, sem precisar carregar os itens de
/// cada um só pra listar (isso só acontece quando o usuário abre um).
class CarrinhoAtivoResumo {
  final String clienteId;
  final String clienteNome;
  final int quantidadeItens;
  final double valorTotal;
  final DateTime atualizadoEm;

  CarrinhoAtivoResumo({
    required this.clienteId,
    required this.clienteNome,
    required this.quantidadeItens,
    required this.valorTotal,
    required this.atualizadoEm,
  });

  factory CarrinhoAtivoResumo.fromJson(Map<String, dynamic> json) {
    return CarrinhoAtivoResumo(
      clienteId: json['cliente_id'] as String,
      clienteNome: json['cliente_nome']?.toString() ?? '',
      quantidadeItens: (json['quantidade_itens'] as num?)?.toInt() ?? 0,
      valorTotal: (json['valor_total'] as num?)?.toDouble() ?? 0,
      atualizadoEm: DateTime.parse(json['atualizado_em'] as String),
    );
  }
}
