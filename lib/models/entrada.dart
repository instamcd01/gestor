import 'fornecedor.dart';

/// Item de uma nota fiscal de fornecedor, como veio do XML — `produtoId`
/// nulo significa que o código de barras (`eanNfe`) não bateu com nenhum
/// produto cadastrado, e o item fica pendente de resolução manual (ver
/// `EntradaRepository`, que só soma no estoque itens já casados).
class ItemEntrada {
  final String? id;
  final String? produtoId;
  final String eanNfe;
  final String descricaoNfe;
  final String? ncm;
  final double quantidade;
  final double custoUnitario;
  final double valorTotal;
  final String? numeroLote;
  final DateTime? dataFabricacao;
  final DateTime? dataValidade;

  ItemEntrada({
    this.id,
    this.produtoId,
    required this.eanNfe,
    required this.descricaoNfe,
    this.ncm,
    required this.quantidade,
    required this.custoUnitario,
    required this.valorTotal,
    this.numeroLote,
    this.dataFabricacao,
    this.dataValidade,
  });

  bool get casado => produtoId != null;

  /// `produtoId`/`dataValidade` aceitam `null` explícito via os `bool ...Definir`
  /// — sem isso não dava pra distinguir "não mudar" de "limpar o valor".
  /// `quantidade`/`custoUnitario`/`valorTotal` nunca são nulos, então não
  /// precisam desse truque — `?? this.campo` já resolve.
  ItemEntrada copyWith({
    String? produtoId,
    bool produtoIdDefinir = false,
    double? quantidade,
    double? custoUnitario,
    double? valorTotal,
    String? numeroLote,
    DateTime? dataFabricacao,
    DateTime? dataValidade,
    bool dataValidadeDefinir = false,
  }) {
    return ItemEntrada(
      id: id,
      produtoId: produtoIdDefinir ? produtoId : (produtoId ?? this.produtoId),
      eanNfe: eanNfe,
      descricaoNfe: descricaoNfe,
      ncm: ncm,
      quantidade: quantidade ?? this.quantidade,
      custoUnitario: custoUnitario ?? this.custoUnitario,
      valorTotal: valorTotal ?? this.valorTotal,
      numeroLote: numeroLote ?? this.numeroLote,
      dataFabricacao: dataFabricacao ?? this.dataFabricacao,
      dataValidade: dataValidadeDefinir ? dataValidade : (dataValidade ?? this.dataValidade),
    );
  }

  factory ItemEntrada.fromSupabase(Map<String, dynamic> row) {
    return ItemEntrada(
      id: row['id'] as String?,
      produtoId: row['produto_id'] as String?,
      eanNfe: row['ean_nfe']?.toString() ?? '',
      descricaoNfe: row['descricao_nfe']?.toString() ?? '',
      ncm: row['ncm']?.toString(),
      quantidade: (row['quantidade'] as num?)?.toDouble() ?? 0.0,
      custoUnitario: (row['custo_unitario'] as num?)?.toDouble() ?? 0.0,
      valorTotal: (row['valor_total'] as num?)?.toDouble() ?? 0.0,
      numeroLote: row['numero_lote']?.toString(),
      dataFabricacao: row['data_fabricacao'] != null ? DateTime.parse(row['data_fabricacao'].toString()) : null,
      dataValidade: row['data_validade'] != null ? DateTime.parse(row['data_validade'].toString()) : null,
    );
  }

  Map<String, dynamic> toSupabaseMap() {
    return {
      'produto_id': produtoId,
      'ean_nfe': eanNfe,
      'descricao_nfe': descricaoNfe,
      'ncm': ncm,
      'quantidade': quantidade,
      'custo_unitario': custoUnitario,
      'valor_total': valorTotal,
      'numero_lote': numeroLote,
      'data_fabricacao': dataFabricacao?.toIso8601String().split('T').first,
      'data_validade': dataValidade?.toIso8601String().split('T').first,
    };
  }
}

/// Uma parcela (duplicata/boleto) associada a uma entrada — usada só na
/// prévia de importação, não é persistida como tabela própria: cada
/// parcela vira uma `Despesa` normal (ver `EntradaRepository.criar`).
class ParcelaEntrada {
  final int numero;
  final double valor;
  final DateTime vencimento;
  /// Preenchido manualmente na prévia (a NF-e não traz isso) — vira
  /// `Despesa.codigoBarrasBoleto`. Mutável de propósito: a tela edita
  /// direto na mesma instância, sem precisar reconstruir a lista.
  String? codigoBarras;

  ParcelaEntrada({required this.numero, required this.valor, required this.vencimento, this.codigoBarras});
}

/// Entrada de estoque a partir de nota fiscal de um fornecedor (cabeçalho
/// da NF-e importada). Itens em `ItemEntrada`, boletos derivados viram
/// `Despesa`s — nenhum dos dois é persistido dentro deste model.
class Entrada {
  final String? id;
  final Fornecedor? fornecedor;
  final String? nfeChaveAcesso;
  final String? nfeNumero;
  final String? nfeSerie;
  final double? valorTotalProdutos;
  final double? valorTotalNota;
  final DateTime? dataEmissao;
  final DateTime dataEntrada;
  final String observacoes;
  final List<ItemEntrada> itens;
  final String? pedidoCompraId;

  Entrada({
    this.id,
    this.fornecedor,
    this.nfeChaveAcesso,
    this.nfeNumero,
    this.nfeSerie,
    this.valorTotalProdutos,
    this.valorTotalNota,
    this.dataEmissao,
    DateTime? dataEntrada,
    this.observacoes = '',
    this.itens = const [],
    this.pedidoCompraId,
  }) : dataEntrada = dataEntrada ?? DateTime.now();

  factory Entrada.fromSupabase(Map<String, dynamic> row) {
    final fornecedorRow = row['fornecedor'] as Map<String, dynamic>?;
    return Entrada(
      id: row['id'] as String?,
      fornecedor: fornecedorRow != null ? Fornecedor.fromSupabase(fornecedorRow) : null,
      nfeChaveAcesso: row['nfe_chave_acesso']?.toString(),
      nfeNumero: row['nfe_numero']?.toString(),
      nfeSerie: row['nfe_serie']?.toString(),
      valorTotalProdutos: (row['valor_total_produtos'] as num?)?.toDouble(),
      valorTotalNota: (row['valor_total_nota'] as num?)?.toDouble(),
      dataEmissao: row['data_emissao'] != null ? DateTime.parse(row['data_emissao'].toString()) : null,
      dataEntrada: DateTime.parse(row['data_entrada'].toString()),
      observacoes: row['observacoes']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toSupabaseMap({String? fornecedorId, String? pedidoCompraId}) {
    return {
      'fornecedor_id': fornecedorId ?? fornecedor?.id,
      'nfe_chave_acesso': nfeChaveAcesso,
      'nfe_numero': nfeNumero,
      'nfe_serie': nfeSerie,
      'valor_total_produtos': valorTotalProdutos,
      'valor_total_nota': valorTotalNota,
      'data_emissao': dataEmissao?.toIso8601String(),
      'data_entrada': dataEntrada.toIso8601String(),
      'observacoes': observacoes,
      'pedido_compra_id': pedidoCompraId ?? this.pedidoCompraId,
    };
  }
}
