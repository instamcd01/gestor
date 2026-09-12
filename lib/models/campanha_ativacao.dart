class CampanhaAtivacao {
  final String id;
  final String nome;
  final String? descricao;
  final DateTime criadoEm;
  final DateTime? arquivadaEm;

  /// Corpo da mensagem salvo pelo usuário como padrão dessa campanha (sem a
  /// saudação "Oi, Nome!" — essa parte continua gerada por contato). Null
  /// quando ninguém salvou nada ainda, e a tela cai de volta pra sugestão
  /// padrão por perfil (vip/inativo/genérico) que já existia antes.
  final String? mensagemPadrao;

  /// Quem gerou essa campanha automaticamente (`carrinho_abandonado`,
  /// `prontos_recompra`, etc) — null pra campanha criada manualmente pelo
  /// usuário. Usado pra escolher a sugestão de mensagem certa por tipo.
  final String? origemSistema;

  bool get arquivada => arquivadaEm != null;

  CampanhaAtivacao({
    required this.id,
    required this.nome,
    this.descricao,
    required this.criadoEm,
    this.arquivadaEm,
    this.mensagemPadrao,
    this.origemSistema,
  });

  factory CampanhaAtivacao.fromSupabase(Map<String, dynamic> row) {
    return CampanhaAtivacao(
      id: row['id'] as String,
      nome: row['nome'] as String,
      descricao: row['descricao'] as String?,
      criadoEm: DateTime.parse(row['criado_em'] as String),
      arquivadaEm: row['deleted_at'] != null ? DateTime.parse(row['deleted_at'] as String) : null,
      mensagemPadrao: row['mensagem_padrao'] as String?,
      origemSistema: row['origem_sistema'] as String?,
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
  final double? valorReferencia;
  final String? perfil;
  final String? mensagemPersonalizada;

  /// Produtos vencidos desse contato (campanha "Prontos pra recompra") — só
  /// os nomes, pra montar a mensagem. Os dias/ciclo de cada um ficam em
  /// [mensagemPersonalizada] (referência interna, não vai na mensagem).
  final List<String> produtosPendentes;
  final String? clienteId;
  final String? nomeCliente;
  final bool ativou;
  final int qtdPedidos;
  final double valorGasto;
  final bool temCarrinhoAbandonado;
  final bool temFavoritoSemCompra;

  bool get enviado => enviadoEm != null;

  ContatoCampanha({
    required this.contatoId,
    required this.telefone,
    this.nomeWhatsapp,
    this.origem,
    this.enviadoEm,
    this.valorReferencia,
    this.perfil,
    this.mensagemPersonalizada,
    this.produtosPendentes = const [],
    this.clienteId,
    this.nomeCliente,
    required this.ativou,
    required this.qtdPedidos,
    required this.valorGasto,
    this.temCarrinhoAbandonado = false,
    this.temFavoritoSemCompra = false,
  });

  ContatoCampanha copyWith({DateTime? enviadoEm, bool limparEnviadoEm = false}) {
    return ContatoCampanha(
      contatoId: contatoId,
      telefone: telefone,
      nomeWhatsapp: nomeWhatsapp,
      origem: origem,
      enviadoEm: limparEnviadoEm ? null : (enviadoEm ?? this.enviadoEm),
      valorReferencia: valorReferencia,
      perfil: perfil,
      mensagemPersonalizada: mensagemPersonalizada,
      produtosPendentes: produtosPendentes,
      clienteId: clienteId,
      nomeCliente: nomeCliente,
      ativou: ativou,
      qtdPedidos: qtdPedidos,
      valorGasto: valorGasto,
      temCarrinhoAbandonado: temCarrinhoAbandonado,
      temFavoritoSemCompra: temFavoritoSemCompra,
    );
  }

  factory ContatoCampanha.fromSupabase(Map<String, dynamic> row) {
    return ContatoCampanha(
      contatoId: row['contato_id'] as String,
      telefone: row['telefone'] as String,
      nomeWhatsapp: row['nome_whatsapp'] as String?,
      origem: row['origem'] as String?,
      enviadoEm: row['enviado_em'] != null ? DateTime.parse(row['enviado_em'] as String) : null,
      valorReferencia: (row['valor_referencia'] as num?)?.toDouble(),
      perfil: row['perfil'] as String?,
      mensagemPersonalizada: row['mensagem_personalizada'] as String?,
      produtosPendentes: (row['produtos_pendentes'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? const [],
      clienteId: row['cliente_id'] as String?,
      nomeCliente: row['nome_cliente'] as String?,
      ativou: row['ativou'] as bool? ?? false,
      qtdPedidos: (row['qtd_pedidos'] as num?)?.toInt() ?? 0,
      valorGasto: (row['valor_gasto'] as num?)?.toDouble() ?? 0,
      temCarrinhoAbandonado: row['tem_carrinho_abandonado'] as bool? ?? false,
      temFavoritoSemCompra: row['tem_favorito_sem_compra'] as bool? ?? false,
    );
  }
}
