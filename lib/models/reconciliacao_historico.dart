/// Tipos de evento registrados em `marketplace_reconciliacao_historico`.
class TipoReconciliacaoHistorico {
  static const estoque = 'estoque';
  static const financeiro = 'financeiro';
  static const catalogoExportado = 'catalogo_exportado';
}

/// Um registro de auditoria permanente de reconciliação/exportação por
/// marketplace — diferente de `notificacoes` (caixa de entrada, o usuário
/// pode limpar), isso fica pra sempre.
class ReconciliacaoHistorico {
  final String id;
  final String marketplaceId;
  final String tipo;
  final DateTime? periodoAte;
  final Map<String, dynamic> detalhes;
  final String mensagem;
  final DateTime executadoEm;

  ReconciliacaoHistorico({
    required this.id,
    required this.marketplaceId,
    required this.tipo,
    this.periodoAte,
    required this.detalhes,
    required this.mensagem,
    required this.executadoEm,
  });

  factory ReconciliacaoHistorico.fromSupabase(Map<String, dynamic> row) {
    return ReconciliacaoHistorico(
      id: row['id'] as String,
      marketplaceId: row['marketplace_id'] as String,
      tipo: row['tipo'] as String,
      periodoAte: row['periodo_ate'] != null ? DateTime.parse(row['periodo_ate'] as String) : null,
      detalhes: (row['detalhes'] as Map<String, dynamic>?) ?? const {},
      mensagem: row['mensagem'] as String,
      executadoEm: DateTime.parse(row['executado_em'] as String),
    );
  }
}
