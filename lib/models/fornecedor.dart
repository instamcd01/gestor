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

  /// Dias entre o envio do pedido de compra e a mercadoria chegar — usado
  /// no cálculo de sugestão de compra (RPC `sugestoes_pedido_compra`) pra
  /// saber com quanta antecedência repor. `null` = ainda não cadastrado,
  /// tratado como 0 dias na sugestão (conservador: sugere pra já).
  int? prazoEntregaDias;

  /// Valor mínimo em R$ que o fornecedor exige por pedido — usado na tela
  /// de Sugestão de Compra pra avisar se o pedido montado não bateu o
  /// mínimo. `null` = sem mínimo cadastrado/conhecido.
  double? valorMinimoPedido;

  Fornecedor({
    this.id,
    required this.nome,
    this.telefone = '',
    this.cnpjCpf = '',
    this.email = '',
    this.observacoes = '',
    this.ativo = true,
    this.fatorCusto = 1.0,
    this.prazoEntregaDias,
    this.valorMinimoPedido,
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
      prazoEntregaDias: (row['prazo_entrega_dias'] as num?)?.toInt(),
      valorMinimoPedido: (row['valor_minimo_pedido'] as num?)?.toDouble(),
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
      'prazo_entrega_dias': prazoEntregaDias,
      'valor_minimo_pedido': valorMinimoPedido,
    };
  }
}
