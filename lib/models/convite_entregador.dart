class ConviteEntregador {
  final String id;
  final String codigo;
  final String entregadorId;
  final String? entregadorNome; // preenchido só quando a query traz o join com entregadores
  final DateTime expiraEm;
  final DateTime? usadoEm;

  ConviteEntregador({
    required this.id,
    required this.codigo,
    required this.entregadorId,
    this.entregadorNome,
    required this.expiraEm,
    this.usadoEm,
  });

  factory ConviteEntregador.fromSupabase(Map<String, dynamic> row) {
    return ConviteEntregador(
      id: row['id'] as String,
      codigo: row['codigo'] as String,
      entregadorId: row['entregador_id'] as String,
      entregadorNome: (row['entregador'] as Map<String, dynamic>?)?['nome']?.toString(),
      expiraEm: DateTime.parse(row['expira_em'].toString()),
      usadoEm: row['usado_em'] != null ? DateTime.tryParse(row['usado_em'].toString()) : null,
    );
  }
}
