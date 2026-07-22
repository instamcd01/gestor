class Usuario {
  final String id;
  final String empresaId;
  final String? nome;
  final String? email;
  final String papel; // 'dono' ou 'funcionario'
  final bool ativo;
  final DateTime? criadoEm;

  Usuario({
    required this.id,
    required this.empresaId,
    this.nome,
    this.email,
    required this.papel,
    required this.ativo,
    this.criadoEm,
  });

  bool get isDono => papel == 'dono';

  factory Usuario.fromSupabase(Map<String, dynamic> row) {
    return Usuario(
      id: row['id'] as String,
      empresaId: row['empresa_id'] as String,
      nome: row['nome']?.toString(),
      email: row['email']?.toString(),
      papel: row['papel']?.toString() ?? 'funcionario',
      ativo: row['ativo'] as bool? ?? true,
      criadoEm: row['created_at'] != null ? DateTime.tryParse(row['created_at'].toString())?.toLocal() : null,
    );
  }
}
