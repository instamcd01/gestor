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
  final DateTime em;

  RespostaIfood({required this.ok, required this.status, this.dados, this.erro, this.itensEnviados})
      : em = DateTime.now();

  factory RespostaIfood.fromMap(Map<String, dynamic> m) => RespostaIfood(
        ok: m['ok'] == true,
        status: (m['status'] as num?)?.toInt() ?? 0,
        dados: m['dados'],
        erro: m['erro']?.toString(),
        itensEnviados: (m['itens_enviados'] as num?)?.toInt(),
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
}
