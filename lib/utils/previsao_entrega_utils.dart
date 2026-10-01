import 'package:intl/intl.dart';

import '../models/venda.dart';

/// Extraído de `VendaDetalhesScreen` pra ser reaproveitado também na geração
/// de mensagem de status (`mensagens_status_pedido.dart`) — mesma lógica,
/// um lugar só.
///
/// Pedidos iFood usam agendado/entregaPrevista*; pedido com checkout do app
/// (loja física/WhatsApp/site) usa agendadoManualmente/previsaoEntrega* —
/// ver comentário no model Venda.
DateTime? previsaoInicio(Venda venda) => venda.previsaoEntregaInicio ?? venda.entregaPrevistaInicio;
DateTime? previsaoFim(Venda venda) => venda.previsaoEntregaFim ?? venda.entregaPrevistaFim;
bool ehAgendado(Venda venda) => venda.agendado || venda.agendadoManualmente;

bool temPrevisaoEntrega(Venda venda) => previsaoFim(venda) != null;

String labelPrevisaoEntrega(Venda venda) {
  if (ehAgendado(venda)) return venda.retirada ? 'Retirada agendada' : 'Entrega agendada';
  if (venda.modalidade == 'economica') return 'Entrega econômica';
  return 'Previsão de entrega';
}

String formatarPrevisaoEntrega(Venda venda) {
  final formato = DateFormat('dd/MM HH:mm');
  final fim = previsaoFim(venda)!;
  if (ehAgendado(venda)) {
    final inicio = previsaoInicio(venda);
    return inicio != null ? '${formato.format(inicio)} - ${formato.format(fim)}' : '~${formato.format(fim)}';
  }
  // previsaoEntregaFim aqui guarda a mesma hora-do-dia do pedido (só a DATA
  // já pula dias fechados — ver `finalizar_pedido_site`) — mostrar a hora
  // seria enganoso.
  if (venda.modalidade == 'economica') return 'Até ${DateFormat('dd/MM').format(fim)}';
  return '~${formato.format(fim)}';
}
