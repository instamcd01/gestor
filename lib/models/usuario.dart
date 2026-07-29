class Usuario {
  final String id;
  final String empresaId;
  final String? nome;
  final String? email;
  final String? telefone;
  final String papel; // 'dono', 'gerente' ou 'vendedor'
  final bool ativo;
  final DateTime? criadoEm;

  Usuario({
    required this.id,
    required this.empresaId,
    this.nome,
    this.email,
    this.telefone,
    required this.papel,
    required this.ativo,
    this.criadoEm,
  });

  bool get isDono => papel == 'dono';
  bool get isGerente => papel == 'gerente';
  bool get isVendedor => papel == 'vendedor';

  static const rotulosPapel = {
    'dono': 'Dono',
    'gerente': 'Gerente',
    'vendedor': 'Vendedor',
  };

  String get rotuloPapel => rotulosPapel[papel] ?? papel;

  factory Usuario.fromSupabase(Map<String, dynamic> row) {
    return Usuario(
      id: row['id'] as String,
      empresaId: row['empresa_id'] as String,
      nome: row['nome']?.toString(),
      email: row['email']?.toString(),
      telefone: row['telefone']?.toString(),
      papel: row['papel']?.toString() ?? 'funcionario',
      ativo: row['ativo'] as bool? ?? true,
      criadoEm: row['created_at'] != null ? DateTime.tryParse(row['created_at'].toString())?.toLocal() : null,
    );
  }
}
