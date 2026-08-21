class SugestaoProdutoCliente {
  final String id;
  final String termoBuscado;
  final String? mensagem;
  final String? contato;
  final String status; // pendente | avaliado | comprado
  final DateTime createdAt;
  final DateTime? avaliadoEm;
  final String? clienteNome;
  final String? clienteTelefone;

  const SugestaoProdutoCliente({
    required this.id,
    required this.termoBuscado,
    this.mensagem,
    this.contato,
    required this.status,
    required this.createdAt,
    this.avaliadoEm,
    this.clienteNome,
    this.clienteTelefone,
  });

  bool get pendente => status == 'pendente';

  factory SugestaoProdutoCliente.fromSupabase(Map<String, dynamic> row) {
    final cliente = row['clientes'] as Map<String, dynamic>?;
    return SugestaoProdutoCliente(
      id: row['id'] as String,
      termoBuscado: row['termo_buscado'] as String,
      mensagem: row['mensagem'] as String?,
      contato: row['contato'] as String?,
      status: row['status'] as String? ?? 'pendente',
      createdAt: DateTime.parse(row['created_at'] as String),
      avaliadoEm: row['avaliado_em'] != null ? DateTime.parse(row['avaliado_em'] as String) : null,
      clienteNome: cliente?['nome'] as String?,
      clienteTelefone: cliente?['telefone'] as String?,
    );
  }
}
