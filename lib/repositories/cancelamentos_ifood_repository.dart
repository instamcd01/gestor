import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Resumo agregado de cancelamentos de um período — 1 linha, vem de
/// `resumo_cancelamentos_ifood`.
class ResumoCancelamentosIfood {
  final int totalCancelamentos;
  final double valorTotalPerdido;
  final String? motivoMaisComum;

  ResumoCancelamentosIfood({
    required this.totalCancelamentos,
    required this.valorTotalPerdido,
    required this.motivoMaisComum,
  });

  factory ResumoCancelamentosIfood.vazio() =>
      ResumoCancelamentosIfood(totalCancelamentos: 0, valorTotalPerdido: 0, motivoMaisComum: null);

  factory ResumoCancelamentosIfood.fromSupabase(Map<String, dynamic> row) => ResumoCancelamentosIfood(
        totalCancelamentos: (row['total_cancelamentos'] as num).toInt(),
        valorTotalPerdido: (row['valor_total_perdido'] as num?)?.toDouble() ?? 0,
        motivoMaisComum: row['motivo_mais_comum']?.toString(),
      );
}

/// Um pedido cancelado — motivo, origem e valor, direto do relatório
/// "Vendas e Pedidos" (campos que antes eram só descartados).
class CancelamentoIfood {
  final String? codigoExibicao;
  final double valorPedido;
  final String? motivoCancelamento;
  final String? origemCancelamento;
  final String? estagioCancelamento;
  final DateTime? dtPedido;
  final DateTime? dtCancelamento;

  CancelamentoIfood({
    required this.codigoExibicao,
    required this.valorPedido,
    required this.motivoCancelamento,
    required this.origemCancelamento,
    required this.estagioCancelamento,
    required this.dtPedido,
    required this.dtCancelamento,
  });

  factory CancelamentoIfood.fromSupabase(Map<String, dynamic> row) => CancelamentoIfood(
        codigoExibicao: row['codigo_exibicao']?.toString(),
        valorPedido: (row['valor_pedido'] as num?)?.toDouble() ?? 0,
        motivoCancelamento: row['motivo_cancelamento']?.toString(),
        origemCancelamento: row['origem_cancelamento']?.toString(),
        estagioCancelamento: row['estagio_cancelamento']?.toString(),
        dtPedido: row['dt_pedido'] != null ? DateTime.parse(row['dt_pedido'] as String) : null,
        dtCancelamento: row['dt_cancelamento'] != null ? DateTime.parse(row['dt_cancelamento'] as String) : null,
      );
}

/// Cancelamentos no iFood — motivo real (loja, cliente ou iFood) de cada
/// pedido cancelado, capturado do relatório "Vendas e Pedidos" e antes
/// descartado sem deixar rastro (ver `registrar_cancelamento_pedido_ifood`
/// no banco).
class CancelamentosIfoodRepository {
  final _supabase = Supabase.instance.client;

  static const _urlWebhookConsultar = 'https://n8n.lukz.com.br/webhook/merchant-consultar';

  // Fixo — mesmo id usado em todos os workflows n8n do iFood (ver
  // `empresa_marketplace_config.marketplace_id`). Não é dado sensível, só
  // a FK que identifica o marketplace nas tabelas.
  static const _marketplaceIdIfood = 'd4811153-e210-47b0-b910-ee0440914f60';

  /// Motivos de cancelamento válidos PARA ESSE PEDIDO específico, direto da
  /// API do iFood (`GET /order/v1.0/orders/{id}/cancellationReasons`) — a
  /// doc deles é explícita: tratar como string livre, nunca validar contra
  /// uma lista fixa no app, porque a iFood pode adicionar/mudar códigos.
  /// Lança exceção se a chamada falhar — quem chama decide o fallback.
  Future<List<({String codigo, String descricao})>> buscarMotivosDisponiveis({
    required String empresaId,
    required String marketplacePedidoId,
  }) async {
    final resposta = await http
        .post(
          Uri.parse(_urlWebhookConsultar),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'empresa_id': empresaId,
            'marketplace_id': _marketplaceIdIfood,
            'tipo_consulta': 'motivos_cancelamento',
            'marketplace_pedido_id': marketplacePedidoId,
          }),
        )
        .timeout(const Duration(seconds: 15));

    if (resposta.statusCode != 200) {
      throw Exception('iFood respondeu ${resposta.statusCode} ao consultar motivos de cancelamento.');
    }
    final corpo = jsonDecode(resposta.body) as Map<String, dynamic>;
    final motivos = corpo['reasons'] as List?;
    if (motivos == null || motivos.isEmpty) {
      throw Exception('iFood não retornou motivos de cancelamento para esse pedido.');
    }
    return motivos
        .map((m) => (
              codigo: (m as Map<String, dynamic>)['code'].toString(),
              descricao: (m['description'] ?? '').toString(),
            ))
        .toList();
  }

  Future<ResumoCancelamentosIfood> buscarResumo({
    required String empresaId,
    required DateTime dataInicio,
    required DateTime dataFim,
  }) async {
    final data = await _supabase.rpc('resumo_cancelamentos_ifood', params: {
      'p_empresa_id': empresaId,
      'p_data_inicio': dataInicio.toIso8601String().split('T').first,
      'p_data_fim': dataFim.toIso8601String().split('T').first,
    });
    final linhas = data as List;
    if (linhas.isEmpty) return ResumoCancelamentosIfood.vazio();
    return ResumoCancelamentosIfood.fromSupabase(linhas.first as Map<String, dynamic>);
  }

  Future<List<CancelamentoIfood>> buscarLista({
    required String empresaId,
    required DateTime dataInicio,
    required DateTime dataFim,
  }) async {
    final data = await _supabase.rpc('listar_cancelamentos_ifood', params: {
      'p_empresa_id': empresaId,
      'p_data_inicio': dataInicio.toIso8601String().split('T').first,
      'p_data_fim': dataFim.toIso8601String().split('T').first,
    });
    return (data as List).map((row) => CancelamentoIfood.fromSupabase(row as Map<String, dynamic>)).toList();
  }
}
