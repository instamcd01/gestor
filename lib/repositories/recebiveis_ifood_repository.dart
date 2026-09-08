import 'package:supabase_flutter/supabase_flutter.dart';

/// Resumo de caixa do período — quanto ainda vai cair e quanto já caiu.
/// Vem de `resumo_recebiveis_ifood`.
class ResumoRecebiveisIfood {
  final double totalAReceber;
  final double totalRecebido;

  ResumoRecebiveisIfood({required this.totalAReceber, required this.totalRecebido});

  factory ResumoRecebiveisIfood.vazio() => ResumoRecebiveisIfood(totalAReceber: 0, totalRecebido: 0);

  factory ResumoRecebiveisIfood.fromSupabase(Map<String, dynamic> row) => ResumoRecebiveisIfood(
        totalAReceber: (row['total_a_receber'] as num?)?.toDouble() ?? 0,
        totalRecebido: (row['total_recebido'] as num?)?.toDouble() ?? 0,
      );
}

/// Um lote de repasse do iFood (mesmo `titulo` agrupa várias linhas do
/// Extrato Financeiro) — vem de `listar_repasses_ifood`.
class RepasseIfood {
  final String? titulo;
  final DateTime? dataEsperada;
  final DateTime? dataEfetivada;
  final double valor;
  final String? transferenciaBancaria;
  final int qtdLancamentos;

  RepasseIfood({
    required this.titulo,
    required this.dataEsperada,
    required this.dataEfetivada,
    required this.valor,
    required this.transferenciaBancaria,
    required this.qtdLancamentos,
  });

  bool get jaCaiu => dataEfetivada != null;

  factory RepasseIfood.fromSupabase(Map<String, dynamic> row) => RepasseIfood(
        titulo: row['titulo']?.toString(),
        dataEsperada: row['data_pagamento_esperado'] != null ? DateTime.parse(row['data_pagamento_esperado'] as String) : null,
        dataEfetivada: row['data_pagamento_efetivado'] != null ? DateTime.parse(row['data_pagamento_efetivado'] as String) : null,
        valor: (row['valor_total_do_repasse'] as num?)?.toDouble() ?? 0,
        transferenciaBancaria: row['transferencia_bancaria']?.toString(),
        qtdLancamentos: (row['qtd_lancamentos'] as num?)?.toInt() ?? 0,
      );
}

/// Comparação, por pedido, entre o valor estimado na Fase B (checkout) e o
/// valor líquido real do Extrato Financeiro — só existe quando o pedido
/// aparece nos dois relatórios (o extrato libera 3-4 semanas depois).
class ComparacaoFinanceiraIfood {
  final String? codigoExibicao;
  final double valorTotalEstimado;
  final double taxasEstimadas;
  final double incentivoIfoodEstimado;
  final double valorLiquidoReal;
  final double diferenca;
  final DateTime? dtPedido;

  ComparacaoFinanceiraIfood({
    required this.codigoExibicao,
    required this.valorTotalEstimado,
    required this.taxasEstimadas,
    required this.incentivoIfoodEstimado,
    required this.valorLiquidoReal,
    required this.diferenca,
    required this.dtPedido,
  });

  factory ComparacaoFinanceiraIfood.fromSupabase(Map<String, dynamic> row) => ComparacaoFinanceiraIfood(
        codigoExibicao: row['codigo_exibicao']?.toString(),
        valorTotalEstimado: (row['valor_total_estimado'] as num?)?.toDouble() ?? 0,
        taxasEstimadas: (row['taxas_estimadas'] as num?)?.toDouble() ?? 0,
        incentivoIfoodEstimado: (row['incentivo_ifood_estimado'] as num?)?.toDouble() ?? 0,
        valorLiquidoReal: (row['valor_liquido_real'] as num?)?.toDouble() ?? 0,
        diferenca: (row['diferenca'] as num?)?.toDouble() ?? 0,
        dtPedido: row['dt_pedido'] != null ? DateTime.parse(row['dt_pedido'] as String) : null,
      );
}

/// Extrato Financeiro real do iFood — só relatório que nunca tinha sido lido
/// por automação, libera 3-4 semanas depois do pedido. Captura bruta em
/// `marketplace_lancamentos_financeiros` via `registrar_lancamentos_financeiros_ifood`,
/// sem sobrescrever nada em `pedidos`/`marketplace_pedidos` ainda — só
/// dashboard de caixa (recebíveis) e comparação lado a lado com o estimado.
class RecebiveisIfoodRepository {
  final _supabase = Supabase.instance.client;

  Future<ResumoRecebiveisIfood> buscarResumo({
    required String empresaId,
    required DateTime dataInicio,
    required DateTime dataFim,
  }) async {
    final data = await _supabase.rpc('resumo_recebiveis_ifood', params: {
      'p_empresa_id': empresaId,
      'p_data_inicio': dataInicio.toIso8601String().split('T').first,
      'p_data_fim': dataFim.toIso8601String().split('T').first,
    });
    final linhas = data as List;
    if (linhas.isEmpty) return ResumoRecebiveisIfood.vazio();
    return ResumoRecebiveisIfood.fromSupabase(linhas.first as Map<String, dynamic>);
  }

  Future<List<RepasseIfood>> buscarRepasses({
    required String empresaId,
    required DateTime dataInicio,
    required DateTime dataFim,
  }) async {
    final data = await _supabase.rpc('listar_repasses_ifood', params: {
      'p_empresa_id': empresaId,
      'p_data_inicio': dataInicio.toIso8601String().split('T').first,
      'p_data_fim': dataFim.toIso8601String().split('T').first,
    });
    return (data as List).map((row) => RepasseIfood.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  Future<List<ComparacaoFinanceiraIfood>> buscarComparacao({
    required String empresaId,
    required DateTime dataInicio,
    required DateTime dataFim,
  }) async {
    final data = await _supabase.rpc('comparar_financeiro_pedido_ifood', params: {
      'p_empresa_id': empresaId,
      'p_data_inicio': dataInicio.toIso8601String().split('T').first,
      'p_data_fim': dataFim.toIso8601String().split('T').first,
    });
    return (data as List).map((row) => ComparacaoFinanceiraIfood.fromSupabase(row as Map<String, dynamic>)).toList();
  }
}
