class MovimentacaoSaldo {
  final String id;
  final String tipo; // 'credito' ou 'debito'
  final double valor;
  final String? motivo;
  final String? pedidoId;
  final double? saldoApos;
  final DateTime criadoEm;

  MovimentacaoSaldo({
    required this.id,
    required this.tipo,
    required this.valor,
    this.motivo,
    this.pedidoId,
    this.saldoApos,
    required this.criadoEm,
  });

  bool get isCredito => tipo == 'credito';

  factory MovimentacaoSaldo.fromSupabase(Map<String, dynamic> row) {
    return MovimentacaoSaldo(
      id: row['id'] as String,
      tipo: row['tipo']?.toString() ?? 'credito',
      valor: (row['valor'] as num?)?.toDouble() ?? 0.0,
      motivo: row['motivo']?.toString(),
      pedidoId: row['pedido_id'] as String?,
      saldoApos: (row['saldo_apos'] as num?)?.toDouble(),
      criadoEm: DateTime.tryParse(row['created_at'].toString())?.toLocal() ?? DateTime.now(),
    );
  }
}
