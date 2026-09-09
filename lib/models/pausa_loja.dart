/// Uma pausa da loja (imediata ou agendada pro futuro) — afeta site,
/// WhatsApp e as integrações de marketplace (iFood/99Food) de uma vez só.
/// status: agendada -> ativa -> finalizada, ou cancelada em qualquer ponto
/// antes de 'finalizada' (o pg_cron `processar-pausas-loja` cuida das
/// transições automáticas).
class PausaLoja {
  final String id;
  final String? motivo;
  final DateTime inicio;
  final DateTime fim;
  final String status;

  PausaLoja({
    required this.id,
    this.motivo,
    required this.inicio,
    required this.fim,
    required this.status,
  });

  bool get ativa => status == 'ativa';
  bool get agendada => status == 'agendada';

  factory PausaLoja.fromSupabase(Map<String, dynamic> row) {
    return PausaLoja(
      id: row['id'] as String,
      motivo: row['motivo']?.toString(),
      inicio: DateTime.parse(row['inicio'] as String).toLocal(),
      fim: DateTime.parse(row['fim'] as String).toLocal(),
      status: row['status']?.toString() ?? 'agendada',
    );
  }
}
