/// Representa um produto do catálogo, já considerando o estoque agregado
/// (somado entre depósitos) vindo da tabela `estoque` do Supabase.
class Produto {
  final String? id;
  String nome;
  double preco;
  double? precoPromocional;
  String descricao;
  String categoria;
  String? subcategoria;
  String? sku;
  double? peso;
  double? volume;
  bool ativo;
  int estoqueAtual;
  int estoqueMinimo;
  String imagemUrl;
  String? imagemUrlSecundaria;
  String codigoBarras;
  double custo;
  bool destacar;
  bool exibirNoCatalogo;
  double? precoIfood;
  String? validade;
  String? markup;
  String? lucro;
  String? empresa;
  double? precoConcorrencia;

  /// Fabricante/laboratório real do produto — distinto de `empresa` (mapeado
  /// pra coluna `marca`, que neste banco historicamente guarda o
  /// fornecedor/distribuidor, não o fabricante; ver memória "Padrão de nome
  /// de produto" do projeto). Campo estruturado, preenchido manualmente —
  /// usado como fonte confiável pra organizar imagens de produto por
  /// fabricante no Storage, em vez de tentar extrair do texto do nome.
  String? fabricante;

  // Campos novos do schema multi-tenant/estoque
  final String? estoqueId;
  final String? unidadeMedida;
  final bool permiteFracionamento;

  /// Custo mudou (ex: importação de NF-e) e o preço de venda ainda não foi
  /// revisado — gerenciado pelas triggers do banco (`sinalizar_revisar_preco`),
  /// nunca enviado em `toSupabaseMap` pra não sobrescrever por engano com um
  /// valor desatualizado (ver `ProdutoRepository.marcarPrecoRevisado`).
  bool revisarPreco;

  Produto({
    this.id,
    required this.nome,
    required this.preco,
    this.precoPromocional,
    required this.descricao,
    required this.categoria,
    this.subcategoria,
    this.sku,
    this.peso,
    this.volume,
    this.ativo = true,
    required this.estoqueAtual,
    required this.estoqueMinimo,
    required this.imagemUrl,
    this.imagemUrlSecundaria,
    required this.codigoBarras,
    required this.custo,
    this.destacar = false,
    this.exibirNoCatalogo = true,
    this.precoIfood,
    this.validade,
    this.markup,
    this.lucro,
    this.empresa,
    this.precoConcorrencia,
    this.fabricante,
    this.estoqueId,
    this.unidadeMedida = 'un',
    this.permiteFracionamento = false,
    this.revisarPreco = false,
  });

  /// Monta o Produto a partir de uma linha do Supabase.
  /// Espera o formato retornado por `.select('*, estoque(id, quantidade_atual, quantidade_minima)')`.
  factory Produto.fromSupabase(Map<String, dynamic> row) {
    final estoqueRows = (row['estoque'] as List?) ?? [];
    final totalEstoque = estoqueRows.fold<int>(
      0,
      (soma, e) => soma + ((e['quantidade_atual'] as num?)?.toInt() ?? 0),
    );
    final estoqueMinimo = estoqueRows.isNotEmpty
        ? ((estoqueRows.first['quantidade_minima'] as num?)?.toInt() ?? 0)
        : 0;
    final estoqueId = estoqueRows.isNotEmpty ? estoqueRows.first['id'] as String? : null;

    final preco = (row['preco'] as num?)?.toDouble() ?? 0.0;
    final custo = (row['custo'] as num?)?.toDouble() ?? 0.0;
    final margem = (row['margem'] as num?)?.toDouble();

    return Produto(
      id: row['id'] as String?,
      nome: row['nome']?.toString() ?? '',
      preco: preco,
      descricao: row['descricao']?.toString() ?? '',
      categoria: row['categoria']?.toString() ?? '',
      subcategoria: row['subcategoria']?.toString(),
      sku: row['sku']?.toString(),
      peso: (row['peso'] as num?)?.toDouble(),
      volume: (row['volume'] as num?)?.toDouble(),
      ativo: row['ativo'] as bool? ?? true,
      estoqueAtual: totalEstoque,
      estoqueMinimo: estoqueMinimo,
      imagemUrl: row['imagem_url']?.toString() ?? '',
      imagemUrlSecundaria: row['imagem_url_secundaria']?.toString(),
      codigoBarras: row['codigo_barras']?.toString() ?? '',
      custo: custo,
      destacar: row['destaque'] as bool? ?? false,
      exibirNoCatalogo: row['exibir_no_catalogo'] as bool? ?? true,
      empresa: row['marca']?.toString(),
      fabricante: row['fabricante']?.toString(),
      estoqueId: estoqueId,
      unidadeMedida: row['unidade_medida']?.toString() ?? 'un',
      permiteFracionamento: row['permite_fracionamento'] as bool? ?? false,
      precoPromocional: (row['preco_promocional'] as num?)?.toDouble(),
      precoIfood: (row['preco_ifood'] as num?)?.toDouble(),
      precoConcorrencia: (row['preco_concorrencia'] as num?)?.toDouble(),
      validade: row['validade']?.toString(),
      revisarPreco: row['revisar_preco'] as bool? ?? false,
      // Derivados (não são colunas próprias no banco, calculados aqui pra
      // manter compatibilidade com as telas que já exibem markup/lucro).
      markup: margem != null ? '${margem.toStringAsFixed(1)}%' : null,
      lucro: (preco - custo).toStringAsFixed(2),
    );
  }

  /// Payload pra INSERT/UPDATE na tabela `produtos` (não inclui estoque).
  Map<String, dynamic> toSupabaseMap() {
    return {
      'nome': nome,
      'descricao': descricao,
      'categoria': categoria,
      'subcategoria': subcategoria,
      'sku': sku,
      'peso': peso,
      'volume': volume,
      'ativo': ativo,
      'marca': empresa,
      'fabricante': fabricante,
      'preco': preco,
      'custo': custo,
      'destaque': destacar,
      'exibir_no_catalogo': exibirNoCatalogo,
      'imagem_url': imagemUrl,
      'imagem_url_secundaria': imagemUrlSecundaria,
      'codigo_barras': codigoBarras,
      'unidade_medida': unidadeMedida,
      'permite_fracionamento': permiteFracionamento,
      'preco_promocional': precoPromocional,
      'preco_ifood': precoIfood,
      'preco_concorrencia': precoConcorrencia,
      'validade': validade,
    };
  }
}
