import 'fornecedor.dart';

/// Um anexo do "espelho" (confirmação do fornecedor) — foto ou PDF enviado
/// na conferência. Guardado como array em `pedidos_compra.anexos_espelho`
/// (jsonb) porque um pedido grande costuma vir em mais de uma imagem.
class AnexoEspelho {
  final String url;
  final String tipo; // 'imagem' | 'pdf'
  final String nomeArquivo;
  final DateTime criadoEm;

  AnexoEspelho({
    required this.url,
    required this.tipo,
    required this.nomeArquivo,
    required this.criadoEm,
  });

  factory AnexoEspelho.fromJson(Map<String, dynamic> json) {
    return AnexoEspelho(
      url: json['url']?.toString() ?? '',
      tipo: json['tipo']?.toString() ?? 'imagem',
      nomeArquivo: json['nome_arquivo']?.toString() ?? '',
      criadoEm: DateTime.parse(json['criado_em'].toString()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'url': url,
      'tipo': tipo,
      'nome_arquivo': nomeArquivo,
      'criado_em': criadoEm.toIso8601String(),
    };
  }
}

/// origem de um item: veio do cálculo automático, foi adicionado à mão na
/// montagem, ou apareceu no espelho/recebimento sem ter sido pedido
/// (erro/extra do fornecedor).
enum OrigemItemPedidoCompra { sugestao, manual, conferencia }

OrigemItemPedidoCompra _origemFromString(String? valor) {
  switch (valor) {
    case 'sugestao':
      return OrigemItemPedidoCompra.sugestao;
    case 'conferencia':
      return OrigemItemPedidoCompra.conferencia;
    default:
      return OrigemItemPedidoCompra.manual;
  }
}

class ItemPedidoCompra {
  final String? id;
  final String produtoId;
  final String produtoNome;
  final String? produtoSubstitutoId;
  final String? produtoSubstitutoNome;
  final int? quantidadeSugerida;
  final int quantidadePedida;
  final int? quantidadeConfirmada;
  final int? quantidadeRecebida;
  final double custoUnitario;
  final double? custoConfirmado;
  final OrigemItemPedidoCompra origem;
  final String? observacao;

  ItemPedidoCompra({
    this.id,
    required this.produtoId,
    required this.produtoNome,
    this.produtoSubstitutoId,
    this.produtoSubstitutoNome,
    this.quantidadeSugerida,
    required this.quantidadePedida,
    this.quantidadeConfirmada,
    this.quantidadeRecebida,
    required this.custoUnitario,
    this.custoConfirmado,
    this.origem = OrigemItemPedidoCompra.manual,
    this.observacao,
  });

  double get subtotalPedido => quantidadePedida * custoUnitario;

  /// Verdadeiro quando o que o fornecedor confirmou/mandou não bate com o
  /// que foi pedido — pra mais, pra menos, ou produto trocado. Cobre
  /// qualquer tipo de erro do fornecedor, não só ruptura (quantidade a
  /// menos).
  bool get divergente {
    if (produtoSubstitutoId != null) return true;
    if (quantidadeConfirmada != null && quantidadeConfirmada != quantidadePedida) return true;
    return false;
  }

  ItemPedidoCompra copyWith({
    int? quantidadePedida,
    int? quantidadeConfirmada,
    bool quantidadeConfirmadaDefinir = false,
    int? quantidadeRecebida,
    double? custoConfirmado,
    String? produtoSubstitutoId,
    String? produtoSubstitutoNome,
    bool produtoSubstitutoDefinir = false,
    String? observacao,
  }) {
    return ItemPedidoCompra(
      id: id,
      produtoId: produtoId,
      produtoNome: produtoNome,
      produtoSubstitutoId: produtoSubstitutoDefinir ? produtoSubstitutoId : (produtoSubstitutoId ?? this.produtoSubstitutoId),
      produtoSubstitutoNome:
          produtoSubstitutoDefinir ? produtoSubstitutoNome : (produtoSubstitutoNome ?? this.produtoSubstitutoNome),
      quantidadeSugerida: quantidadeSugerida,
      quantidadePedida: quantidadePedida ?? this.quantidadePedida,
      quantidadeConfirmada: quantidadeConfirmadaDefinir ? quantidadeConfirmada : (quantidadeConfirmada ?? this.quantidadeConfirmada),
      quantidadeRecebida: quantidadeRecebida ?? this.quantidadeRecebida,
      custoUnitario: custoUnitario,
      custoConfirmado: custoConfirmado ?? this.custoConfirmado,
      origem: origem,
      observacao: observacao ?? this.observacao,
    );
  }

  factory ItemPedidoCompra.fromSupabase(Map<String, dynamic> row) {
    final produtoRow = row['produto'] as Map<String, dynamic>?;
    final substitutoRow = row['produto_substituto'] as Map<String, dynamic>?;
    return ItemPedidoCompra(
      id: row['id'] as String?,
      produtoId: row['produto_id'] as String,
      produtoNome: produtoRow?['nome']?.toString() ?? '',
      produtoSubstitutoId: row['produto_substituto_id'] as String?,
      produtoSubstitutoNome: substitutoRow?['nome']?.toString(),
      quantidadeSugerida: (row['quantidade_sugerida'] as num?)?.toInt(),
      quantidadePedida: (row['quantidade_pedida'] as num?)?.toInt() ?? 0,
      quantidadeConfirmada: (row['quantidade_confirmada'] as num?)?.toInt(),
      quantidadeRecebida: (row['quantidade_recebida'] as num?)?.toInt(),
      custoUnitario: (row['custo_unitario'] as num?)?.toDouble() ?? 0.0,
      custoConfirmado: (row['custo_confirmado'] as num?)?.toDouble(),
      origem: _origemFromString(row['origem']?.toString()),
      observacao: row['observacao']?.toString(),
    );
  }

  Map<String, dynamic> toSupabaseMap() {
    return {
      'produto_id': produtoId,
      'produto_substituto_id': produtoSubstitutoId,
      'quantidade_sugerida': quantidadeSugerida,
      'quantidade_pedida': quantidadePedida,
      'quantidade_confirmada': quantidadeConfirmada,
      'quantidade_recebida': quantidadeRecebida,
      'custo_unitario': custoUnitario,
      'custo_confirmado': custoConfirmado,
      'origem': origem.name,
      'observacao': observacao,
    };
  }
}

enum StatusPedidoCompra { rascunho, enviado, confirmado, recebido, cancelado }

StatusPedidoCompra statusPedidoCompraFromString(String valor) {
  return StatusPedidoCompra.values.firstWhere(
    (s) => s.name == valor,
    orElse: () => StatusPedidoCompra.rascunho,
  );
}

extension StatusPedidoCompraLabel on StatusPedidoCompra {
  String get label {
    switch (this) {
      case StatusPedidoCompra.rascunho:
        return 'Rascunho';
      case StatusPedidoCompra.enviado:
        return 'Enviado';
      case StatusPedidoCompra.confirmado:
        return 'Confirmado';
      case StatusPedidoCompra.recebido:
        return 'Recebido';
      case StatusPedidoCompra.cancelado:
        return 'Cancelado';
    }
  }
}

class PedidoCompra {
  final String? id;
  final Fornecedor fornecedor;
  final int? numeroSequencial;
  final StatusPedidoCompra status;
  final double valorTotal;
  final double? valorTotalConfirmado;
  final String? observacoes;
  final List<AnexoEspelho> anexosEspelho;
  final DateTime? dataEnvio;
  final DateTime? dataConfirmacao;
  final DateTime? dataPrevistaEntrega;
  final DateTime? dataRecebimento;
  final DateTime? createdAt;
  final List<ItemPedidoCompra> itens;

  PedidoCompra({
    this.id,
    required this.fornecedor,
    this.numeroSequencial,
    this.status = StatusPedidoCompra.rascunho,
    this.valorTotal = 0,
    this.valorTotalConfirmado,
    this.observacoes,
    this.anexosEspelho = const [],
    this.dataEnvio,
    this.dataConfirmacao,
    this.dataPrevistaEntrega,
    this.dataRecebimento,
    this.createdAt,
    this.itens = const [],
  });

  /// Verdadeiro quando o pedido tem pelo menos um item que não bate com o
  /// que foi confirmado/recebido — usado pra destacar o pedido na lista.
  bool get temDivergencia => itens.any((i) => i.divergente);

  factory PedidoCompra.fromSupabase(Map<String, dynamic> row) {
    final fornecedorRow = row['fornecedor'] as Map<String, dynamic>?;
    final itensRows = (row['itens_pedido_compra'] as List?) ?? [];
    final anexosRaw = (row['anexos_espelho'] as List?) ?? [];
    return PedidoCompra(
      id: row['id'] as String?,
      fornecedor: fornecedorRow != null ? Fornecedor.fromSupabase(fornecedorRow) : Fornecedor(nome: '—'),
      numeroSequencial: (row['numero_sequencial'] as num?)?.toInt(),
      status: statusPedidoCompraFromString(row['status']?.toString() ?? 'rascunho'),
      valorTotal: (row['valor_total'] as num?)?.toDouble() ?? 0.0,
      valorTotalConfirmado: (row['valor_total_confirmado'] as num?)?.toDouble(),
      observacoes: row['observacoes']?.toString(),
      anexosEspelho: anexosRaw.map((a) => AnexoEspelho.fromJson(a as Map<String, dynamic>)).toList(),
      dataEnvio: row['data_envio'] != null ? DateTime.parse(row['data_envio'].toString()) : null,
      dataConfirmacao: row['data_confirmacao'] != null ? DateTime.parse(row['data_confirmacao'].toString()) : null,
      dataPrevistaEntrega:
          row['data_prevista_entrega'] != null ? DateTime.parse(row['data_prevista_entrega'].toString()) : null,
      dataRecebimento: row['data_recebimento'] != null ? DateTime.parse(row['data_recebimento'].toString()) : null,
      createdAt: row['created_at'] != null ? DateTime.parse(row['created_at'].toString()) : null,
      itens: itensRows.map((i) => ItemPedidoCompra.fromSupabase(i as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toSupabaseMap() {
    return {
      'fornecedor_id': fornecedor.id,
      'status': status.name,
      'observacoes': observacoes,
      'anexos_espelho': anexosEspelho.map((a) => a.toJson()).toList(),
      'data_envio': dataEnvio?.toIso8601String(),
      'data_confirmacao': dataConfirmacao?.toIso8601String(),
      'data_prevista_entrega': dataPrevistaEntrega?.toIso8601String(),
      'data_recebimento': dataRecebimento?.toIso8601String(),
    };
  }
}

/// Uma linha da RPC `sugestoes_pedido_compra` — ainda não é um pedido, só
/// a matéria-prima pra montar um (ver `PedidoCompraRepository.buscarSugestoes`).
class SugestaoCompra {
  final String produtoId;
  final String produtoNome;
  final String fornecedorId;
  final String fornecedorNome;
  final int? prazoEntregaDias;
  final int estoqueAtual;
  final double vendaMediaDiaria;
  final int quantidadeSugerida;
  final double custoUnitario;

  SugestaoCompra({
    required this.produtoId,
    required this.produtoNome,
    required this.fornecedorId,
    required this.fornecedorNome,
    this.prazoEntregaDias,
    required this.estoqueAtual,
    required this.vendaMediaDiaria,
    required this.quantidadeSugerida,
    required this.custoUnitario,
  });

  factory SugestaoCompra.fromSupabase(Map<String, dynamic> row) {
    return SugestaoCompra(
      produtoId: row['produto_id'] as String,
      produtoNome: row['produto_nome']?.toString() ?? '',
      fornecedorId: row['fornecedor_id'] as String,
      fornecedorNome: row['fornecedor_nome']?.toString() ?? '',
      prazoEntregaDias: (row['prazo_entrega_dias'] as num?)?.toInt(),
      estoqueAtual: (row['estoque_atual'] as num?)?.toInt() ?? 0,
      vendaMediaDiaria: (row['venda_media_diaria'] as num?)?.toDouble() ?? 0.0,
      quantidadeSugerida: (row['quantidade_sugerida'] as num?)?.toInt() ?? 0,
      custoUnitario: (row['custo_unitario'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
