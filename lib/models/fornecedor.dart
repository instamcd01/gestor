class Fornecedor {
  final String? id;
  final String nome;
  final String telefone;
  final String cnpjCpf;
  final String email;
  final String observacoes;
  final bool ativo;

  Fornecedor({
    this.id,
    required this.nome,
    this.telefone = '',
    this.cnpjCpf = '',
    this.email = '',
    this.observacoes = '',
    this.ativo = true,
  });

  factory Fornecedor.fromSupabase(Map<String, dynamic> row) {
    return Fornecedor(
      id: row['id'] as String?,
      nome: row['nome']?.toString() ?? '',
      telefone: row['telefone']?.toString() ?? '',
      cnpjCpf: row['cnpj_cpf']?.toString() ?? '',
      email: row['email']?.toString() ?? '',
      observacoes: row['observacoes']?.toString() ?? '',
      ativo: row['ativo'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toSupabaseMap() {
    return {
      'nome': nome,
      'telefone': telefone,
      'cnpj_cpf': cnpjCpf,
      'email': email,
      'observacoes': observacoes,
      'ativo': ativo,
    };
  }
}
