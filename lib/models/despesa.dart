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
  /// true só na instância ATUAL/mais recente de uma série recorrente (ex:
  /// mensalidade do iFood) — `gerar_despesas_recorrentes()` (pg_cron diário)
  /// gera a próxima ocorrência automaticamente quando o mês vira, copiando
  /// descrição/categoria/valor, e desliga essa flag na antiga.
  final bool recorrente;
  final int? recorrenciaDia; // dia do mês (1-28) em que a próxima ocorrência nasce

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
    this.recorrente = false,
    this.recorrenciaDia,
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
      recorrente: row['recorrente'] as bool? ?? false,
      recorrenciaDia: (row['recorrencia_dia'] as num?)?.toInt(),
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
      'recorrente': recorrente,
      'recorrencia_dia': recorrenciaDia,
    };
  }
}
