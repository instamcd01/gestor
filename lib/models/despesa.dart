import 'fornecedor.dart';

class StatusDespesa {
  static const pendente = 'pendente';
  static const pago = 'pago';
  static const cancelado = 'cancelado';
}

const categoriasDespesaSugeridas = [
  'Aluguel',
  'Fornecedores',
  'Salários',
  'Impostos',
  'Utilidades',
  'Marketing',
  'Manutenção',
  'Outros',
];

class Despesa {
  final String? id;
  final Fornecedor? fornecedor;
  final String descricao;
  final String categoria;
  final double valor;
  final DateTime dataVencimento;
  final DateTime? dataPagamento;
  final DateTime? dataCancelamento;
  final String status; // ver StatusDespesa — "atrasado" é derivado, não gravado
  final String? metodoPagamento;
  final String observacoes;
  /// Código de barras/linha digitável do boleto — não vem da NF-e (o XML
  /// não traz isso, só o banco gera depois de registrado), preenchido
  /// manualmente pra facilitar identificar/pagar depois.
  final String? codigoBarrasBoleto;

  Despesa({
    this.id,
    this.fornecedor,
    required this.descricao,
    this.categoria = 'Outros',
    required this.valor,
    required this.dataVencimento,
    this.dataPagamento,
    this.dataCancelamento,
    this.status = StatusDespesa.pendente,
    this.metodoPagamento,
    this.observacoes = '',
    this.codigoBarrasBoleto,
  });

  bool get paga => status == StatusDespesa.pago;
  bool get cancelada => status == StatusDespesa.cancelado;
  bool get atrasada => status == StatusDespesa.pendente && dataVencimento.isBefore(DateTime.now());

  factory Despesa.fromSupabase(Map<String, dynamic> row) {
    final fornecedorRow = row['fornecedor'] as Map<String, dynamic>?;
    return Despesa(
      id: row['id'] as String?,
      fornecedor: fornecedorRow != null ? Fornecedor.fromSupabase(fornecedorRow) : null,
      descricao: row['descricao']?.toString() ?? '',
      categoria: row['categoria']?.toString() ?? 'Outros',
      valor: (row['valor'] as num?)?.toDouble() ?? 0.0,
      dataVencimento: DateTime.parse(row['data_vencimento'].toString()),
      dataPagamento: row['data_pagamento'] != null ? DateTime.parse(row['data_pagamento'].toString()) : null,
      dataCancelamento: row['data_cancelamento'] != null ? DateTime.parse(row['data_cancelamento'].toString()) : null,
      status: row['status']?.toString() ?? StatusDespesa.pendente,
      metodoPagamento: row['metodo_pagamento']?.toString(),
      observacoes: row['observacoes']?.toString() ?? '',
      codigoBarrasBoleto: row['codigo_barras_boleto']?.toString(),
    );
  }

  Map<String, dynamic> toSupabaseMap({String? fornecedorId}) {
    return {
      'fornecedor_id': fornecedorId ?? fornecedor?.id,
      'descricao': descricao,
      'categoria': categoria,
      'valor': valor,
      'data_vencimento': dataVencimento.toIso8601String().split('T').first,
      'data_pagamento': dataPagamento?.toIso8601String().split('T').first,
      'data_cancelamento': dataCancelamento?.toIso8601String(),
      'status': status,
      'metodo_pagamento': metodoPagamento,
      'observacoes': observacoes,
      'codigo_barras_boleto': codigoBarrasBoleto,
    };
  }
}
