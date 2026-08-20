/// Um produto real dentro de um kit, com a quantidade que ele entra no
/// combo. `preco`/`custo` são copiados do produto componente no momento de
/// listar/editar — usados pra calcular o preço cheio do kit e o rateio do
/// preço fechado entre os componentes na hora da venda.
class ComponenteKit {
  final String produtoId;
  final String nome;
  final double preco;
  final double custo;
  final int quantidade;

  const ComponenteKit({
    required this.produtoId,
    required this.nome,
    required this.preco,
    required this.custo,
    required this.quantidade,
  });
}

/// Um kit (combo de produtos reais vendido por preço fechado). É uma linha
/// normal da tabela `produtos` (`eh_kit = true`) — nunca tem linha própria
/// em `estoque`; a disponibilidade vem sempre do estoque real dos
/// componentes (`estoque_disponivel_kit` no banco).
class KitProduto {
  final String? id;
  String nome;
  String descricao;
  String categoria;
  double preco;
  double? precoPromocional;
  String imagemUrl;
  String? imagemUrlSecundaria;
  bool ativo;
  bool exibirNoCatalogo;
  bool destacar;

  /// Quantos kits dá pra montar agora, calculado via `estoque_disponivel_kit`
  /// — nunca persistido, só preenchido ao listar/carregar.
  final int estoqueDisponivel;

  List<ComponenteKit> componentes;

  KitProduto({
    this.id,
    required this.nome,
    this.descricao = '',
    required this.categoria,
    required this.preco,
    this.precoPromocional,
    this.imagemUrl = '',
    this.imagemUrlSecundaria,
    this.ativo = true,
    this.exibirNoCatalogo = true,
    this.destacar = false,
    this.estoqueDisponivel = 0,
    List<ComponenteKit>? componentes,
  }) : componentes = componentes ?? [];

  /// Soma dos preços normais dos componentes × quantidade de cada um —
  /// "preço cheio" pra comparar com o preço fechado do kit e mostrar a
  /// economia (cadastro no app e riscado no site, via `preco_cheio_kit`
  /// na view do catálogo, que usa exatamente essa mesma conta).
  double get precoCheioCalculado =>
      componentes.fold(0.0, (soma, c) => soma + c.preco * c.quantidade);

  factory KitProduto.fromSupabase(Map<String, dynamic> row, {List<ComponenteKit> componentes = const []}) {
    return KitProduto(
      id: row['id'] as String?,
      nome: row['nome']?.toString() ?? '',
      descricao: row['descricao']?.toString() ?? '',
      categoria: row['categoria']?.toString() ?? '',
      preco: (row['preco'] as num?)?.toDouble() ?? 0.0,
      precoPromocional: (row['preco_promocional'] as num?)?.toDouble(),
      imagemUrl: row['imagem_url']?.toString() ?? '',
      imagemUrlSecundaria: row['imagem_url_secundaria']?.toString(),
      ativo: row['ativo'] as bool? ?? true,
      exibirNoCatalogo: row['exibir_no_catalogo'] as bool? ?? true,
      destacar: row['destaque'] as bool? ?? false,
      componentes: componentes,
    );
  }

  /// Cópia com `estoqueDisponivel` preenchido — usado pelo repository
  /// depois de chamar `estoque_disponivel_kit` (campo é `final`).
  KitProduto comEstoqueDisponivel(int estoque) {
    return KitProduto(
      id: id,
      nome: nome,
      descricao: descricao,
      categoria: categoria,
      preco: preco,
      precoPromocional: precoPromocional,
      imagemUrl: imagemUrl,
      imagemUrlSecundaria: imagemUrlSecundaria,
      ativo: ativo,
      exibirNoCatalogo: exibirNoCatalogo,
      destacar: destacar,
      estoqueDisponivel: estoque,
      componentes: componentes,
    );
  }

  /// Payload pra INSERT/UPDATE em `produtos` — `eh_kit`/`empresa_id` são
  /// adicionados pelo repository, não aqui (mesmo padrão de `empresa_id`
  /// em `Produto.toSupabaseMap`/`ProdutoRepository.criar`).
  Map<String, dynamic> toSupabaseMap() {
    return {
      'nome': nome,
      'descricao': descricao,
      'categoria': categoria,
      'preco': preco,
      'preco_promocional': precoPromocional,
      'imagem_url': imagemUrl,
      'imagem_url_secundaria': imagemUrlSecundaria,
      'ativo': ativo,
      'exibir_no_catalogo': exibirNoCatalogo,
      'destaque': destacar,
    };
  }
}
