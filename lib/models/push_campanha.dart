class PushCampanha {
  final String id;
  final String titulo;
  final String mensagem;
  final String? link;
  final String status;
  final int totalDestinatarios;
  final int totalEnviados;
  final int totalFalhas;
  final DateTime criadoEm;

  PushCampanha({
    required this.id,
    required this.titulo,
    required this.mensagem,
    this.link,
    required this.status,
    required this.totalDestinatarios,
    required this.totalEnviados,
    required this.totalFalhas,
    required this.criadoEm,
  });

  factory PushCampanha.fromSupabase(Map<String, dynamic> row) {
    return PushCampanha(
      id: row['id'] as String,
      titulo: row['titulo'] as String,
      mensagem: row['mensagem'] as String,
      link: row['link'] as String?,
      status: row['status'] as String,
      totalDestinatarios: (row['total_destinatarios'] as num?)?.toInt() ?? 0,
      totalEnviados: (row['total_enviados'] as num?)?.toInt() ?? 0,
      totalFalhas: (row['total_falhas'] as num?)?.toInt() ?? 0,
      criadoEm: DateTime.parse(row['criado_em'] as String),
    );
  }
}
