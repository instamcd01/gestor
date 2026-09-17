/// Uma contestação/negociação de cancelamento vinda da iFood (Handshake
/// Platform, evento HANDSHAKE_DISPUTE), capturada em `marketplace_disputas`.
/// Aceitar ou rejeitar é sempre uma decisão manual da loja — a própria
/// iFood recomenda explicitamente não automatizar essa decisão.
class DisputaMarketplace {
  final String id;
  final String pedidoId;
  final String marketplaceNome;
  final String? tipo;
  final String? mensagem;
  final DateTime? prazoExpiracao;
  final String status;
  final String? motivoResposta;
  final String? erroResposta;
  final DateTime createdAt;
  final List<dynamic> alternativas;
  final String? acao;
  final String? handshakeType;
  final String? timeoutAction;
  final List<String> acceptReasons;
  final List<dynamic> itensContestados;

  DisputaMarketplace({
    required this.id,
    required this.pedidoId,
    required this.marketplaceNome,
    this.tipo,
    this.mensagem,
    this.prazoExpiracao,
    required this.status,
    this.motivoResposta,
    this.erroResposta,
    required this.createdAt,
    this.alternativas = const [],
    this.acao,
    this.handshakeType,
    this.timeoutAction,
    this.acceptReasons = const [],
    this.itensContestados = const [],
  });

  bool get pendente => status == 'pendente';
  bool get expirada => prazoExpiracao != null && prazoExpiracao!.isBefore(DateTime.now()) && pendente;
  bool get temAlternativas => alternativas.isNotEmpty;

  factory DisputaMarketplace.fromSupabase(Map<String, dynamic> row) {
    final marketplaceRow = row['marketplaces'] as Map<String, dynamic>?;
    final alternativasRaw = row['alternativas'];
    final acceptReasonsRaw = row['accept_reasons'];
    final itensRaw = row['itens_contestados'];
    return DisputaMarketplace(
      id: row['id'] as String,
      pedidoId: row['pedido_id'] as String,
      marketplaceNome: marketplaceRow?['nome']?.toString() ?? 'Marketplace',
      tipo: row['tipo']?.toString(),
      mensagem: row['mensagem']?.toString(),
      prazoExpiracao: DateTime.tryParse(row['prazo_expiracao']?.toString() ?? '')?.toLocal(),
      status: row['status']?.toString() ?? 'pendente',
      motivoResposta: row['motivo_resposta']?.toString(),
      erroResposta: row['erro_resposta']?.toString(),
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      alternativas: alternativasRaw is List ? alternativasRaw : const [],
      acao: row['acao']?.toString(),
      handshakeType: row['handshake_type']?.toString(),
      timeoutAction: row['timeout_action']?.toString(),
      acceptReasons: acceptReasonsRaw is List ? acceptReasonsRaw.map((e) => e.toString()).toList() : const [],
      itensContestados: itensRaw is List ? itensRaw : const [],
    );
  }
}
