import 'package:supabase_flutter/supabase_flutter.dart';

/// Resumo agregado de nps/avaliação/reclamação de um período — 1 linha,
/// vem de `resumo_qualidade_ifood`.
class ResumoQualidadeIfood {
  final double? notaMedia;
  final int totalAvaliados;
  final int totalComReclamacao;
  final int totalPedidos;

  ResumoQualidadeIfood({
    required this.notaMedia,
    required this.totalAvaliados,
    required this.totalComReclamacao,
    required this.totalPedidos,
  });

  factory ResumoQualidadeIfood.vazio() =>
      ResumoQualidadeIfood(notaMedia: null, totalAvaliados: 0, totalComReclamacao: 0, totalPedidos: 0);

  factory ResumoQualidadeIfood.fromSupabase(Map<String, dynamic> row) => ResumoQualidadeIfood(
        notaMedia: (row['nota_media'] as num?)?.toDouble(),
        totalAvaliados: (row['total_avaliados'] as num).toInt(),
        totalComReclamacao: (row['total_com_reclamacao'] as num).toInt(),
        totalPedidos: (row['total_pedidos'] as num).toInt(),
      );
}

/// Um pedido com sinal de problema — nota baixa, reclamação ou chamado.
class PedidoQualidadeIfood {
  final String? numeroExibicao;
  final double? notaAvaliacao;
  final String? nps;
  final bool teveContato;
  final String? motivoContato;
  final int qtdChamados;
  final double valorTotal;
  final DateTime data;

  PedidoQualidadeIfood({
    required this.numeroExibicao,
    required this.notaAvaliacao,
    required this.nps,
    required this.teveContato,
    required this.motivoContato,
    required this.qtdChamados,
    required this.valorTotal,
    required this.data,
  });

  factory PedidoQualidadeIfood.fromSupabase(Map<String, dynamic> row) => PedidoQualidadeIfood(
        numeroExibicao: row['numero_exibicao']?.toString(),
        notaAvaliacao: (row['nota_avaliacao'] as num?)?.toDouble(),
        nps: row['nps']?.toString(),
        teveContato: row['teve_contato'] == true,
        motivoContato: row['motivo_contato']?.toString(),
        qtdChamados: (row['qtd_chamados_pedido_errado'] as num?)?.toInt() ?? 0,
        valorTotal: (row['valor_total'] as num?)?.toDouble() ?? 0,
        data: DateTime.parse(row['dt'] as String),
      );
}

/// Qualidade/atendimento no iFood — nps, nota de avaliação e reclamação por
/// pedido, capturados do relatório "Vendas e Pedidos" e nunca usados antes
/// (ver `registrar_qualidade_pedido_ifood` no banco).
class QualidadeIfoodRepository {
  final _supabase = Supabase.instance.client;

  Future<ResumoQualidadeIfood> buscarResumo({
    required String empresaId,
    required DateTime dataInicio,
    required DateTime dataFim,
  }) async {
    final data = await _supabase.rpc('resumo_qualidade_ifood', params: {
      'p_empresa_id': empresaId,
      'p_data_inicio': dataInicio.toIso8601String().split('T').first,
      'p_data_fim': dataFim.toIso8601String().split('T').first,
    });
    final linhas = data as List;
    if (linhas.isEmpty) return ResumoQualidadeIfood.vazio();
    return ResumoQualidadeIfood.fromSupabase(linhas.first as Map<String, dynamic>);
  }

  Future<List<PedidoQualidadeIfood>> buscarPedidosProblematicos({
    required String empresaId,
    required DateTime dataInicio,
    required DateTime dataFim,
  }) async {
    final data = await _supabase.rpc('listar_pedidos_qualidade_ifood', params: {
      'p_empresa_id': empresaId,
      'p_data_inicio': dataInicio.toIso8601String().split('T').first,
      'p_data_fim': dataFim.toIso8601String().split('T').first,
    });
    return (data as List).map((row) => PedidoQualidadeIfood.fromSupabase(row as Map<String, dynamic>)).toList();
  }
}
