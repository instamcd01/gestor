class TipoPeriodoMeta {
  static const dia = 'dia';
  static const semana = 'semana';
  static const mes = 'mes';
}

/// Meta financeira de um período (dia/semana/mês) — comparada ao realizado
/// (soma de `pedidos.valor_total` com `status = 'entregue'`, calculada no
/// repository, não guardada aqui).
class MetaFinanceira {
  final String? id;
  final String periodoTipo; // ver TipoPeriodoMeta
  final DateTime periodoInicio;
  final double valorMeta;

  MetaFinanceira({
    this.id,
    required this.periodoTipo,
    required this.periodoInicio,
    required this.valorMeta,
  });

  factory MetaFinanceira.fromSupabase(Map<String, dynamic> row) {
    return MetaFinanceira(
      id: row['id'] as String?,
      periodoTipo: row['periodo_tipo']?.toString() ?? TipoPeriodoMeta.dia,
      periodoInicio: DateTime.parse(row['periodo_inicio'].toString()),
      valorMeta: (row['valor_meta'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toSupabaseMap() {
    return {
      'periodo_tipo': periodoTipo,
      'periodo_inicio': periodoInicio.toIso8601String().split('T').first,
      'valor_meta': valorMeta,
    };
  }
}
