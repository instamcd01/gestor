class ConviteEmpresa {
  final String id;
  final String codigo;
  final String papel;
  final DateTime expiraEm;
  final DateTime? usadoEm;
  final DateTime criadoEm;

  ConviteEmpresa({
    required this.id,
    required this.codigo,
    required this.papel,
    required this.expiraEm,
    this.usadoEm,
    required this.criadoEm,
  });

  bool get expirado => usadoEm == null && expiraEm.isBefore(DateTime.now());
  bool get pendente => usadoEm == null && !expirado;

  factory ConviteEmpresa.fromSupabase(Map<String, dynamic> row) {
    return ConviteEmpresa(
      id: row['id'] as String,
      codigo: row['codigo']?.toString() ?? '',
      papel: row['papel']?.toString() ?? 'vendedor',
      expiraEm: DateTime.tryParse(row['expira_em'].toString())?.toLocal() ?? DateTime.now(),
      usadoEm: row['usado_em'] != null ? DateTime.tryParse(row['usado_em'].toString())?.toLocal() : null,
      criadoEm: DateTime.tryParse(row['created_at'].toString())?.toLocal() ?? DateTime.now(),
    );
  }
}
