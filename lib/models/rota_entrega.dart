class StatusRota {
  static const planejada = 'planejada';
  static const emAndamento = 'em_andamento';
  static const concluida = 'concluida';
}

/// Uma rota de entrega do dia — agrupa vários pedidos pra um entregador
/// despachar de uma vez (Fase 2 do custo real por venda, ver
/// [[gestor_custo_real_venda]]). O custo de entrega de cada pedido dentro
/// dela só é calculado de verdade quando a rota é finalizada (RPC
/// `finalizar_rota_entrega`), porque os modos "salário"/"por rota"
/// dependem de saber quantos pedidos/quantos km entraram na rota inteira.
class RotaEntrega {
  final String id;
  final String entregadorId;
  final String entregadorNome;
  final String? entregadorCustoModo;
  final DateTime dataRota;
  final String status;
  final double? kmTotal;
  final double? kmEstimado;
  final DateTime? finalizadaEm;

  RotaEntrega({
    required this.id,
    required this.entregadorId,
    required this.entregadorNome,
    this.entregadorCustoModo,
    required this.dataRota,
    required this.status,
    this.kmTotal,
    this.kmEstimado,
    this.finalizadaEm,
  });

  bool get planejada => status == StatusRota.planejada;
  bool get emAndamento => status == StatusRota.emAndamento;
  bool get concluida => status == StatusRota.concluida;

  /// modos que precisam do km total percorrido, pedido na finalização.
  bool get precisaDeKmTotal => entregadorCustoModo == 'rota';

  factory RotaEntrega.fromSupabase(Map<String, dynamic> row) {
    final entregadorRow = row['entregador'] as Map<String, dynamic>?;
    return RotaEntrega(
      id: row['id'] as String,
      entregadorId: row['entregador_id'] as String,
      entregadorNome: entregadorRow?['nome']?.toString() ?? '?',
      entregadorCustoModo: entregadorRow?['custo_modo']?.toString(),
      dataRota: DateTime.parse(row['data_rota'].toString()),
      status: row['status']?.toString() ?? StatusRota.planejada,
      kmTotal: (row['km_total'] as num?)?.toDouble(),
      kmEstimado: (row['km_estimado'] as num?)?.toDouble(),
      finalizadaEm: row['finalizada_em'] != null ? DateTime.tryParse(row['finalizada_em'].toString()) : null,
    );
  }
}

/// Um pedido dentro de uma rota — só a referência + posição + custo já
/// alocado (quando a rota já foi finalizada). Os dados de exibição (nome
/// do cliente, endereço, status) vêm do `HistoricoVendasProvider`, já
/// carregado — não duplicamos essa consulta aqui.
class RotaPedidoItem {
  final String pedidoId;
  final int ordem;
  final double? custoAlocado;

  RotaPedidoItem({required this.pedidoId, required this.ordem, this.custoAlocado});

  factory RotaPedidoItem.fromSupabase(Map<String, dynamic> row) {
    return RotaPedidoItem(
      pedidoId: row['pedido_id'] as String,
      ordem: (row['ordem'] as num?)?.toInt() ?? 0,
      custoAlocado: (row['custo_alocado'] as num?)?.toDouble(),
    );
  }
}
