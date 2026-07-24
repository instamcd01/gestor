/// Uma pausa da loja num marketplace (ex: acabou o estoque, vai fechar
/// mais cedo), espelhando a Merchant Interruptions API da iFood.
class InterrupcaoMarketplace {
  final String id;
  final String motivo;
  final DateTime inicio;
  final DateTime fim;
  final String status;
  final String? erro;

  InterrupcaoMarketplace({
    required this.id,
    required this.motivo,
    required this.inicio,
    required this.fim,
    required this.status,
    this.erro,
  });

  bool get ativaOuPendente => status == 'ativa' || status == 'pendente';

  factory InterrupcaoMarketplace.fromSupabase(Map<String, dynamic> row) {
    return InterrupcaoMarketplace(
      id: row['id'] as String,
      motivo: row['motivo']?.toString() ?? '',
      inicio: DateTime.tryParse(row['inicio']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      fim: DateTime.tryParse(row['fim']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
      status: row['status']?.toString() ?? 'pendente',
      erro: row['erro']?.toString(),
    );
  }
}
