/// Sugestão de vínculo entre 2 cadastros de `clientes` que bateram por
/// CPF/CNPJ (documento digitado, sem prova de posse — por isso nunca
/// mescla sozinho, sempre passa por aqui) — ver
/// `detectar_vinculo_por_documento` e plano "Identidade de Cliente
/// Cross-Canal". Só staff (dono/gerente) vê esta tela; o cliente nunca
/// sabe que essa fila existe.
class VinculoCliente {
  final String id;
  final String criterio; // 'cpf' | 'cnpj'
  final DateTime criadoEm;

  final String clienteNovoId;
  final String nomeNovo;
  final String telefoneNovo;
  final String? canalNovo;

  final String clienteEncontradoId;
  final String nomeEncontrado;
  final String telefoneEncontrado;
  final String? canalEncontrado;
  final int totalPedidosEncontrado;
  final double saldoEncontrado;
  final double saldoPetCashEncontrado;

  VinculoCliente({
    required this.id,
    required this.criterio,
    required this.criadoEm,
    required this.clienteNovoId,
    required this.nomeNovo,
    required this.telefoneNovo,
    this.canalNovo,
    required this.clienteEncontradoId,
    required this.nomeEncontrado,
    required this.telefoneEncontrado,
    this.canalEncontrado,
    required this.totalPedidosEncontrado,
    required this.saldoEncontrado,
    required this.saldoPetCashEncontrado,
  });

  factory VinculoCliente.fromSupabase(Map<String, dynamic> row) {
    final novo = row['cliente_novo'] as Map<String, dynamic>;
    final encontrado = row['cliente_encontrado'] as Map<String, dynamic>;

    return VinculoCliente(
      id: row['id'] as String,
      criterio: row['criterio'] as String,
      criadoEm: DateTime.parse(row['created_at'] as String),
      clienteNovoId: novo['id'] as String,
      nomeNovo: novo['nome']?.toString() ?? '',
      telefoneNovo: novo['telefone']?.toString() ?? '',
      canalNovo: novo['canal_origem']?.toString(),
      clienteEncontradoId: encontrado['id'] as String,
      nomeEncontrado: encontrado['nome']?.toString() ?? '',
      telefoneEncontrado: encontrado['telefone']?.toString() ?? '',
      canalEncontrado: encontrado['canal_origem']?.toString(),
      totalPedidosEncontrado: (encontrado['total_pedidos'] as num?)?.toInt() ?? 0,
      saldoEncontrado: (encontrado['saldo'] as num?)?.toDouble() ?? 0.0,
      saldoPetCashEncontrado: (encontrado['saldo_petcash'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
