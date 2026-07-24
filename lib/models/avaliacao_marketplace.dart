/// Uma avaliação de cliente vinda de um marketplace (iFood), sincronizada
/// periodicamente em `marketplace_pedidos.avaliacao_*` pelo workflow
/// "iFood - Avaliações Sync". A resposta da loja mora no mesmo registro —
/// escrevê-la dispara o envio automático pra iFood via trigger no banco.
class AvaliacaoMarketplace {
  final String marketplacePedidoId;
  final String pedidoId;
  final String marketplaceNome;
  final double nota;
  final String? comentario;
  final String? idExterno;
  final String? respostaLoja;
  final DateTime? respondidaEm;
  final DateTime dataPedido;

  AvaliacaoMarketplace({
    required this.marketplacePedidoId,
    required this.pedidoId,
    required this.marketplaceNome,
    required this.nota,
    this.comentario,
    this.idExterno,
    this.respostaLoja,
    this.respondidaEm,
    required this.dataPedido,
  });

  bool get respondida => respondidaEm != null;
  bool get podeResponder => idExterno != null && !respondida;

  factory AvaliacaoMarketplace.fromSupabase(Map<String, dynamic> row) {
    final marketplaceRow = row['marketplaces'] as Map<String, dynamic>?;
    return AvaliacaoMarketplace(
      marketplacePedidoId: row['id'] as String,
      pedidoId: row['pedido_id'] as String,
      marketplaceNome: marketplaceRow?['nome']?.toString() ?? 'Marketplace',
      nota: (row['avaliacao_marketplace'] as num?)?.toDouble() ?? 0.0,
      comentario: row['avaliacao_comentario']?.toString(),
      idExterno: row['avaliacao_id_externo']?.toString(),
      respostaLoja: row['avaliacao_resposta_loja']?.toString(),
      respondidaEm: DateTime.tryParse(row['avaliacao_respondida_em']?.toString() ?? ''),
      dataPedido: DateTime.tryParse(row['created_at']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
    );
  }
}
