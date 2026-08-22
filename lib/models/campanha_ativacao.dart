class CampanhaAtivacao {
  final String id;
  final String nome;
  final String? descricao;
  final DateTime criadoEm;
  final DateTime? arquivadaEm;

  bool get arquivada => arquivadaEm != null;

  CampanhaAtivacao({
    required this.id,
    required this.nome,
    this.descricao,
    required this.criadoEm,
    this.arquivadaEm,
  });

  factory CampanhaAtivacao.fromSupabase(Map<String, dynamic> row) {
    return CampanhaAtivacao(
      id: row['id'] as String,
      nome: row['nome'] as String,
      descricao: row['descricao'] as String?,
      criadoEm: DateTime.parse(row['criado_em'] as String),
      arquivadaEm: row['deleted_at'] != null ? DateTime.parse(row['deleted_at'] as String) : null,
    );
  }
}

class MetricasCampanha {
  final int totalContatos;
  final int ativados;
  final int comPedido;
  final int recompraram;
  final double valorTotal;
  final double ticketMedio;
  final int carrinhoAbandonado;
  final int favoritosSemCompra;
  final int pedidosSite;
  final int pedidosWhatsapp;

  MetricasCampanha({
    required this.totalContatos,
    required this.ativados,
    required this.comPedido,
    required this.recompraram,
    required this.valorTotal,
    required this.ticketMedio,
    required this.carrinhoAbandonado,
    required this.favoritosSemCompra,
    required this.pedidosSite,
    required this.pedidosWhatsapp,
  });

  factory MetricasCampanha.fromSupabase(Map<String, dynamic> row) {
    return MetricasCampanha(
      totalContatos: (row['total_contatos'] as num?)?.toInt() ?? 0,
      ativados: (row['ativados'] as num?)?.toInt() ?? 0,
      comPedido: (row['com_pedido'] as num?)?.toInt() ?? 0,
      recompraram: (row['recompraram'] as num?)?.toInt() ?? 0,
      valorTotal: (row['valor_total'] as num?)?.toDouble() ?? 0,
      ticketMedio: (row['ticket_medio'] as num?)?.toDouble() ?? 0,
      carrinhoAbandonado: (row['carrinho_abandonado'] as num?)?.toInt() ?? 0,
      favoritosSemCompra: (row['favoritos_sem_compra'] as num?)?.toInt() ?? 0,
      pedidosSite: (row['pedidos_site'] as num?)?.toInt() ?? 0,
      pedidosWhatsapp: (row['pedidos_whatsapp'] as num?)?.toInt() ?? 0,
    );
  }
}

class ContatoCampanha {
  final String contatoId;
  final String telefone;
  final String? nomeWhatsapp;
  final String? origem;
  final DateTime? enviadoEm;
  final String? clienteId;
  final String? nomeCliente;
  final bool ativou;
  final int qtdPedidos;
  final double valorGasto;

  ContatoCampanha({
    required this.contatoId,
    required this.telefone,
    this.nomeWhatsapp,
    this.origem,
    this.enviadoEm,
    this.clienteId,
    this.nomeCliente,
    required this.ativou,
    required this.qtdPedidos,
    required this.valorGasto,
  });

  factory ContatoCampanha.fromSupabase(Map<String, dynamic> row) {
    return ContatoCampanha(
      contatoId: row['contato_id'] as String,
      telefone: row['telefone'] as String,
      nomeWhatsapp: row['nome_whatsapp'] as String?,
      origem: row['origem'] as String?,
      enviadoEm: row['enviado_em'] != null ? DateTime.parse(row['enviado_em'] as String) : null,
      clienteId: row['cliente_id'] as String?,
      nomeCliente: row['nome_cliente'] as String?,
      ativou: row['ativou'] as bool? ?? false,
      qtdPedidos: (row['qtd_pedidos'] as num?)?.toInt() ?? 0,
      valorGasto: (row['valor_gasto'] as num?)?.toDouble() ?? 0,
    );
  }
}
