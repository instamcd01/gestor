class Fornecedor {
  final String? id;
  final String nome;
  final String telefone;
  final String cnpjCpf;
  final String email;
  final String observacoes;
  final bool ativo;
  /// Multiplicador aplicado ao custo unitário vindo da NF-e desse
  /// fornecedor antes de gravar/comparar — alguns fornecedores faturam a
  /// nota com valor diferente do custo real de aquisição. 1.0 = sem ajuste.
  double fatorCusto;

  Fornecedor({
    this.id,
    required this.nome,
    this.telefone = '',
    this.cnpjCpf = '',
    this.email = '',
    this.observacoes = '',
    this.ativo = true,
    this.fatorCusto = 1.0,
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
      fatorCusto: (row['fator_custo'] as num?)?.toDouble() ?? 1.0,
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
      'fator_custo': fatorCusto,
    };
  }
}
