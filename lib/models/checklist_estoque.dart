/// Checklist mensal de estoque (`checklists_estoque`): contagem física +
/// validade de cada produto. Fica aberto até concluir — dá pra conferir em
/// vários dias. Só um aberto por vez (índice único no banco).
class ChecklistEstoque {
  final String id;

  /// 'YYYY-MM'.
  final String referencia;
  final DateTime iniciadoEm;
  final DateTime? concluidoEm;

  const ChecklistEstoque({
    required this.id,
    required this.referencia,
    required this.iniciadoEm,
    this.concluidoEm,
  });

  bool get aberto => concluidoEm == null;

  static const _meses = [
    'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
    'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
  ];

  /// 'Outubro/2026'.
  String get titulo => tituloDe(referencia);

  static String tituloDe(String referencia) {
    final partes = referencia.split('-');
    final mes = int.tryParse(partes.length == 2 ? partes[1] : '');
    if (mes == null || mes < 1 || mes > 12) return referencia;
    return '${_meses[mes - 1]}/${partes[0]}';
  }

  static String referenciaDe(DateTime data) => '${data.year}-${data.month.toString().padLeft(2, '0')}';

  factory ChecklistEstoque.fromSupabase(Map<String, dynamic> row) => ChecklistEstoque(
        id: row['id'] as String,
        referencia: row['referencia'] as String,
        iniciadoEm: DateTime.parse(row['iniciado_em'] as String).toLocal(),
        concluidoEm: row['concluido_em'] != null ? DateTime.parse(row['concluido_em'] as String).toLocal() : null,
      );
}

/// Um produto conferido no checklist. [quantidadeSistema] é o saldo que o
/// sistema tinha na 1ª conferência — a diferença pra [quantidadeContada] é
/// a falta/sobra do mês.
class ChecklistItem {
  final String produtoId;
  final int quantidadeSistema;
  final int quantidadeContada;
  final double custoUnitario;
  final DateTime? validade;
  final DateTime conferidoEm;

  const ChecklistItem({
    required this.produtoId,
    required this.quantidadeSistema,
    required this.quantidadeContada,
    required this.custoUnitario,
    required this.validade,
    required this.conferidoEm,
  });

  int get diferenca => quantidadeContada - quantidadeSistema;
  double get diferencaValor => diferenca * custoUnitario;

  factory ChecklistItem.fromSupabase(Map<String, dynamic> row) => ChecklistItem(
        produtoId: row['produto_id'] as String,
        quantidadeSistema: (row['quantidade_sistema'] as num).toInt(),
        quantidadeContada: (row['quantidade_contada'] as num).toInt(),
        custoUnitario: (row['custo_unitario'] as num?)?.toDouble() ?? 0,
        validade: row['validade'] != null ? DateTime.parse(row['validade'] as String) : null,
        conferidoEm: DateTime.parse(row['conferido_em'] as String).toLocal(),
      );
}
