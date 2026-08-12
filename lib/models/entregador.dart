/// Modos de custo de entrega própria por entregador (Fase 2 do custo real
/// por venda — ver [[gestor_custo_real_venda]]). Cada entregador tem o seu,
/// já que o arranjo pode variar pessoa a pessoa (diarista pago por entrega,
/// funcionário fixo, etc.).
class ModoCustoEntregador {
  static const fixo = 'fixo';
  static const km = 'km';
  static const salarioMensal = 'salario_mensal';
  static const salarioDiaria = 'salario_diaria';
  static const rota = 'rota';
}

class Entregador {
  final String? id;
  final String nome;
  final String? telefone;
  final String? documento;
  final String? tipoVeiculo;
  final String? placaVeiculo;
  final bool ativo;
  final bool veiculoDaLoja;
  final String? custoModo; // ver ModoCustoEntregador
  final double? custoPorEntrega; // modo fixo
  final double? custoPorKm; // modo km e modo rota
  final double? custoPorParadaRota; // só modo rota
  final double? custoSalarioMensal;
  final double? custoSalarioDiaria;

  Entregador({
    this.id,
    required this.nome,
    this.telefone,
    this.documento,
    this.tipoVeiculo,
    this.placaVeiculo,
    this.ativo = true,
    this.veiculoDaLoja = false,
    this.custoModo,
    this.custoPorEntrega,
    this.custoPorKm,
    this.custoPorParadaRota,
    this.custoSalarioMensal,
    this.custoSalarioDiaria,
  });

  factory Entregador.fromSupabase(Map<String, dynamic> row) {
    return Entregador(
      id: row['id'] as String?,
      nome: row['nome']?.toString() ?? '',
      telefone: row['telefone']?.toString(),
      documento: row['documento']?.toString(),
      tipoVeiculo: row['tipo_veiculo']?.toString(),
      placaVeiculo: row['placa_veiculo']?.toString(),
      ativo: row['ativo'] as bool? ?? true,
      veiculoDaLoja: row['veiculo_da_loja'] as bool? ?? false,
      custoModo: row['custo_modo']?.toString(),
      custoPorEntrega: (row['custo_por_entrega'] as num?)?.toDouble(),
      custoPorKm: (row['custo_por_km'] as num?)?.toDouble(),
      custoPorParadaRota: (row['custo_por_parada_rota'] as num?)?.toDouble(),
      custoSalarioMensal: (row['custo_salario_mensal'] as num?)?.toDouble(),
      custoSalarioDiaria: (row['custo_salario_diaria'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toSupabaseMap() {
    return {
      'nome': nome,
      'telefone': telefone,
      'documento': documento,
      'tipo_veiculo': tipoVeiculo,
      'placa_veiculo': placaVeiculo,
      'ativo': ativo,
      'veiculo_da_loja': veiculoDaLoja,
      'custo_modo': custoModo,
      'custo_por_entrega': custoPorEntrega,
      'custo_por_km': custoPorKm,
      'custo_por_parada_rota': custoPorParadaRota,
      'custo_salario_mensal': custoSalarioMensal,
      'custo_salario_diaria': custoSalarioDiaria,
    };
  }
}
