/// Veículo próprio da loja (moto/carro) usado pra entrega — cada um com
/// seu próprio histórico de despesas (`DespesaVeiculo`) e custo/km real
/// calculado a partir dele. Pode ser usado por mais de um entregador em
/// dias/turnos diferentes — não é exclusivo de um entregador só.
class Veiculo {
  final String? id;
  String nome;
  String tipo;
  bool ativo;

  Veiculo({this.id, required this.nome, this.tipo = 'moto', this.ativo = true});

  factory Veiculo.fromSupabase(Map<String, dynamic> row) {
    return Veiculo(
      id: row['id'] as String?,
      nome: row['nome'] as String,
      tipo: row['tipo'] as String? ?? 'moto',
      ativo: row['ativo'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toSupabaseMap() => {'nome': nome, 'tipo': tipo, 'ativo': ativo};
}
