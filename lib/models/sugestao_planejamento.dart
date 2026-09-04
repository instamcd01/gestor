/// Sugestão de recompra — cliente cujo tempo desde a última compra já
/// passou do intervalo médio dele (`clientes_devido_recompra`, ver
/// migration correspondente). `intervaloMedioDias` vem de
/// `clientes.intervalo_medio_recompra_dias`, calculado automaticamente
/// pelo banco a partir do histórico de pedidos do próprio cliente.
class SugestaoRecompra {
  final String clienteId;
  final String nome;
  final String telefone;
  final DateTime ultimaCompra;
  final double intervaloMedioDias;
  final double diasDesdeUltimaCompra;

  SugestaoRecompra({
    required this.clienteId,
    required this.nome,
    required this.telefone,
    required this.ultimaCompra,
    required this.intervaloMedioDias,
    required this.diasDesdeUltimaCompra,
  });

  factory SugestaoRecompra.fromSupabase(Map<String, dynamic> row) {
    return SugestaoRecompra(
      clienteId: row['cliente_id'] as String,
      nome: row['nome']?.toString() ?? '',
      telefone: row['telefone']?.toString() ?? '',
      ultimaCompra: DateTime.parse(row['ultima_compra'].toString()),
      intervaloMedioDias: (row['intervalo_medio_dias'] as num?)?.toDouble() ?? 0,
      diasDesdeUltimaCompra: (row['dias_desde_ultima_compra'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Contato de campanha de ativação que nunca ativou o cadastro e o envio
/// já foi há um tempo (`contatos_campanha_parados`). **Aproximação, não
/// precisão**: o schema não guarda "última resposta"/"última interação",
/// só `enviado_em` — "parado" aqui é só "não ativou + envio antigo".
class SugestaoContatoParado {
  final String contatoId;
  final String campanhaId;
  final String campanhaNome;
  final String telefone;
  final String nomeWhatsapp;
  final DateTime enviadoEm;
  final double diasParado;

  SugestaoContatoParado({
    required this.contatoId,
    required this.campanhaId,
    required this.campanhaNome,
    required this.telefone,
    required this.nomeWhatsapp,
    required this.enviadoEm,
    required this.diasParado,
  });

  factory SugestaoContatoParado.fromSupabase(Map<String, dynamic> row) {
    return SugestaoContatoParado(
      contatoId: row['contato_id'] as String,
      campanhaId: row['campanha_id'] as String,
      campanhaNome: row['campanha_nome']?.toString() ?? '',
      telefone: row['telefone']?.toString() ?? '',
      nomeWhatsapp: row['nome_whatsapp']?.toString() ?? '',
      enviadoEm: DateTime.parse(row['enviado_em'].toString()),
      diasParado: (row['dias_parado'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Post de conteúdo social pendente de aprovação (`posts_conteudo`,
/// status = 'pendente_aprovacao') — leitura simples (sem RPC própria).
/// A aprovação/publicação de verdade é feita na automação
/// `gestor-conteudo-social` (ainda não implantada — por isso esta seção
/// pode ficar sempre vazia até lá); aqui só vira lembrete de revisar.
class PostConteudoPendente {
  final String id;
  final String pilar;
  final String formato;
  final String? tema;
  final String canal;
  final DateTime criadoEm;

  PostConteudoPendente({
    required this.id,
    required this.pilar,
    required this.formato,
    this.tema,
    required this.canal,
    required this.criadoEm,
  });

  factory PostConteudoPendente.fromSupabase(Map<String, dynamic> row) {
    return PostConteudoPendente(
      id: row['id'] as String,
      pilar: row['pilar']?.toString() ?? '',
      formato: row['formato']?.toString() ?? '',
      tema: row['tema'] as String?,
      canal: row['canal']?.toString() ?? '',
      criadoEm: DateTime.parse(row['criado_em'].toString()),
    );
  }
}
