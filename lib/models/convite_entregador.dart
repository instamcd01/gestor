class ConviteEntregador {
  final String id;
  final String codigo;
  final DateTime expiraEm;
  final DateTime? usadoEm;

  ConviteEntregador({
    required this.id,
    required this.codigo,
    required this.expiraEm,
    this.usadoEm,
  });

  factory ConviteEntregador.fromSupabase(Map<String, dynamic> row) {
    return ConviteEntregador(
      id: row['id'] as String,
      codigo: row['codigo'] as String,
      expiraEm: DateTime.parse(row['expira_em'].toString()),
      usadoEm: row['usado_em'] != null ? DateTime.tryParse(row['usado_em'].toString()) : null,
    );
  }
}
