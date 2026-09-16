/// Um lançamento real de gasto com um veículo da loja (combustível,
/// manutenção, pneu, seguro ou outro) — junto com o km do odômetro quando
/// conhecido, pra virar histórico real e alimentar o cálculo de custo/km
/// (`calcular_custo_por_km_veiculo` no banco), em vez de estimativa
/// estática.
class DespesaVeiculo {
  final String? id;
  final String veiculoId;
  final DateTime data;
  final String tipo; // combustivel | manutencao | pneu | seguro | outro
  final double valor;
  final double? kmAtual;
  final String? observacao;

  DespesaVeiculo({
    this.id,
    required this.veiculoId,
    required this.data,
    required this.tipo,
    required this.valor,
    this.kmAtual,
    this.observacao,
  });

  factory DespesaVeiculo.fromSupabase(Map<String, dynamic> row) {
    return DespesaVeiculo(
      id: row['id'] as String?,
      veiculoId: row['veiculo_id'] as String,
      data: DateTime.parse(row['data'] as String),
      tipo: row['tipo'] as String,
      valor: (row['valor'] as num).toDouble(),
      kmAtual: (row['km_atual'] as num?)?.toDouble(),
      observacao: row['observacao'] as String?,
    );
  }

  Map<String, dynamic> toSupabaseMap() => {
        'veiculo_id': veiculoId,
        'data': data.toIso8601String().split('T').first,
        'tipo': tipo,
        'valor': valor,
        'km_atual': kmAtual,
        'observacao': observacao,
      };
}

const tiposDespesaVeiculo = <String>['combustivel', 'manutencao', 'pneu', 'seguro', 'outro'];

String rotuloTipoDespesaVeiculo(String tipo) => switch (tipo) {
      'combustivel' => 'Combustível',
      'manutencao' => 'Manutenção',
      'pneu' => 'Pneu',
      'seguro' => 'Seguro',
      _ => 'Outro',
    };
