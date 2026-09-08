import 'package:supabase_flutter/supabase_flutter.dart';

/// Um produto no ranking de ruptura — qtos eventos de "indisponível"/
/// "desistência" ele teve no período e quanto de venda isso representou.
class RankingRupturaItem {
  final String? produtoId;
  final String produtoNome;
  final int qtdEventos;
  final double valorPerdido;

  RankingRupturaItem({
    required this.produtoId,
    required this.produtoNome,
    required this.qtdEventos,
    required this.valorPerdido,
  });

  factory RankingRupturaItem.fromSupabase(Map<String, dynamic> row) => RankingRupturaItem(
        produtoId: row['produto_id']?.toString(),
        produtoNome: row['produto_nome']?.toString() ?? 'Produto não identificado',
        qtdEventos: (row['qtd_eventos'] as num).toInt(),
        valorPerdido: (row['valor_perdido'] as num).toDouble(),
      );
}

/// Ruptura de estoque no iFood — captura o campo `indisponivel`/`desistencia`
/// do relatório "Itens por pedido", que antes era só descartado na
/// reconciliação (ver `registrar_ruptura_relatorio_ifood` no banco).
class RupturaIfoodRepository {
  final _supabase = Supabase.instance.client;

  Future<List<RankingRupturaItem>> buscarRanking({
    required String empresaId,
    required DateTime dataInicio,
    required DateTime dataFim,
  }) async {
    final data = await _supabase.rpc('ranking_ruptura_ifood', params: {
      'p_empresa_id': empresaId,
      'p_data_inicio': dataInicio.toIso8601String().split('T').first,
      'p_data_fim': dataFim.toIso8601String().split('T').first,
    });
    return (data as List).map((row) => RankingRupturaItem.fromSupabase(row as Map<String, dynamic>)).toList();
  }
}
