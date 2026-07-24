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
  });

  bool get pendente => status == 'pendente';
  bool get expirada => prazoExpiracao != null && prazoExpiracao!.isBefore(DateTime.now()) && pendente;
  bool get temAlternativas => alternativas.isNotEmpty;

  factory DisputaMarketplace.fromSupabase(Map<String, dynamic> row) {
    final marketplaceRow = row['marketplaces'] as Map<String, dynamic>?;
    final alternativasRaw = row['alternativas'];
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
    );
  }
}
