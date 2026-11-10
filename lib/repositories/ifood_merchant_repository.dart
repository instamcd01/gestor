import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';

/// Resposta de uma chamada à API do iFood feita pela Edge Function
/// `ifood-merchant` (as credenciais ficam no servidor).
class RespostaIfood {
  final bool ok;
  final int status;
  final dynamic dados;
  final String? erro;
  final int? itensEnviados;
  /// Quantas tentativas a Edge Function fez (backoff no 429/5xx).
  final int? tentativas;
  /// O token foi renovado no meio (o iFood respondeu 401 na 1ª tentativa).
  final bool tokenRenovado;
  /// Cenário 429: quantas requisições até o iFood limitar.
  final int? requisicoes;
  final DateTime em;

  RespostaIfood({
    required this.ok,
    required this.status,
    this.dados,
    this.erro,
    this.itensEnviados,
    this.tentativas,
    this.tokenRenovado = false,
    this.requisicoes,
  }) : em = DateTime.now();

  /// errorCode(s) da resposta, nos vários formatos de erro do iFood
  /// ({errors:[{errorCode}]}, {code}, {error}).
  String? get codigoErro {
    final d = dados;
    if (d is Map) {
      final erros = d['errors'];
      if (erros is List && erros.isNotEmpty) {
        final cods = erros.whereType<Map>().map((e) => (e['errorCode'] ?? e['error'] ?? '').toString()).where((c) => c.isNotEmpty).toSet();
        if (cods.isNotEmpty) return cods.join(', ');
      }
      if (d['code'] is String) return d['code'] as String;
    }
    return null;
  }

  /// Mensagem de erro legível, seja qual for o formato.
  String? get mensagemErro {
    final d = dados;
    if (d is Map) {
      final erros = d['errors'];
      if (erros is List && erros.isNotEmpty) {
        return erros.whereType<Map>().map((e) => (e['errorMessage'] ?? e['error'] ?? '').toString()).where((m) => m.isNotEmpty).join(' · ');
      }
      if (d['message'] != null) return d['message'].toString();
      if (d['error'] != null) return d['error'].toString();
    } else if (d is String && d.isNotEmpty) {
      return d;
    }
    return erro;
  }

  factory RespostaIfood.fromMap(Map<String, dynamic> m) => RespostaIfood(
        ok: m['ok'] == true,
        status: (m['status'] as num?)?.toInt() ?? 0,
        dados: m['dados'],
        erro: m['erro']?.toString(),
        itensEnviados: (m['itens_enviados'] as num?)?.toInt(),
        tentativas: (m['tentativas'] as num?)?.toInt(),
        tokenRenovado: m['token_renovado'] == true,
        requisicoes: (m['requisicoes'] as num?)?.toInt(),
      );
}

/// Um turno de funcionamento no iFood (vários por dia).
class TurnoIfood {
  final String dia; // segunda..domingo
  final String inicio; // HH:mm
  final String fim; // HH:mm

  const TurnoIfood(this.dia, this.inicio, this.fim);

  Map<String, String> toMap() => {'dia': dia, 'inicio': inicio, 'fim': fim};
}

class IfoodMerchantRepository {
  Future<RespostaIfood> _chamar(String acao, [Map<String, dynamic> extra = const {}]) async {
    try {
      final r = await supabase.functions.invoke('ifood-merchant', body: {'acao': acao, ...extra});
      return RespostaIfood.fromMap(Map<String, dynamic>.from(r.data as Map));
    } on FunctionException catch (e) {
      final det = e.details;
      if (det is Map) return RespostaIfood.fromMap(Map<String, dynamic>.from(det));
      return RespostaIfood(ok: false, status: e.status, erro: det?.toString() ?? 'Erro ${e.status}');
    }
  }

  Future<RespostaIfood> listarLojas() => _chamar('listar_lojas');
  Future<RespostaIfood> detalheLoja(String merchantId) => _chamar('detalhe_loja', {'merchant_id': merchantId});
  Future<RespostaIfood> statusLoja(String merchantId) => _chamar('status_loja', {'merchant_id': merchantId});
  Future<RespostaIfood> listarPausas() => _chamar('listar_pausas');
  Future<RespostaIfood> consultarHorarios() => _chamar('consultar_horarios');
  Future<RespostaIfood> salvarHorarios(List<TurnoIfood> turnos) =>
      _chamar('salvar_horarios', {'turnos': turnos.map((t) => t.toMap()).toList()});
  /// [marketplacePedidoId] = marketplace_pedidos.id
  Future<RespostaIfood> consultarPedido(String marketplacePedidoId) =>
      _chamar('consultar_pedido', {'marketplace_pedido_id': marketplacePedidoId});
  Future<RespostaIfood> cargaCompleta() => _chamar('carga_completa');

  // ── Promotion v2.0 ────────────────────────────────────────────────────
  /// [payload] = {"promotions": {promotionName, percentageDiscounts: [...], ...}}.
  /// [corpoBruto] envia o texto como está (cenário "JSON malformado").
  /// [merchantId] só pros cenários de merchant inexistente / de outra loja.
  Future<RespostaIfood> promoCriar(Map<String, dynamic>? payload,
          {String? corpoBruto, String? merchantId, bool homologacao = false}) =>
      _chamar('promo_criar', {
        if (payload != null) 'payload': payload,
        if (corpoBruto != null) 'corpo_bruto': corpoBruto,
        if (merchantId != null) 'merchant_id': merchantId,
        'homologacao': homologacao,
      });
  Future<RespostaIfood> promoConsultar(String promotionId, {String? merchantId, bool simularTokenExpirado = false}) =>
      _chamar('promo_consultar', {
        'promotion_id': promotionId,
        if (merchantId != null) 'merchant_id': merchantId,
        'simular_token_expirado': simularTokenExpirado,
      });
  Future<RespostaIfood> promoListar({Object? page, Object? size, String? status, String? startDate, String? endDate}) =>
      _chamar('promo_listar', {
        if (page != null) 'page': page,
        if (size != null) 'size': size,
        if (status != null) 'status': status,
        if (startDate != null) 'startDate': startDate,
        if (endDate != null) 'endDate': endDate,
      });
  Future<RespostaIfood> promoEditar(String promotionId, Map<String, dynamic> payload) =>
      _chamar('promo_editar', {'promotion_id': promotionId, 'payload': payload});
  /// [itens] vazio = encerra a promoção inteira (fica INACTIVE).
  Future<RespostaIfood> promoRemoverItens(String promotionId, [List<Map<String, dynamic>> itens = const []]) =>
      _chamar('promo_remover_itens', {'promotion_id': promotionId, 'items': itens});
  Future<RespostaIfood> promoItens(String promotionId) => _chamar('promo_itens', {'promotion_id': promotionId});
  Future<RespostaIfood> promoPedidos(String promotionId, {String? startDate, String? endDate}) =>
      _chamar('promo_pedidos', {'promotion_id': promotionId, if (startDate != null) 'startDate': startDate, if (endDate != null) 'endDate': endDate});
  Future<RespostaIfood> promoTeste429() => _chamar('promo_teste_429');
}
