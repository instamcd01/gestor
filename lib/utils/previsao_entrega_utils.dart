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

/// Faixa completa ("02/10 de 15:00 às 15:30") sempre que houver início —
/// mostrar só o fim ("~15:30") fazia o cliente achar que ia demorar
/// (pedido do usuário 02/10). Sem início, cai pro "~fim".
String formatarPrevisaoEntrega(Venda venda) {
  final dia = DateFormat('dd/MM');
  final hora = DateFormat('HH:mm');
  final fim = previsaoFim(venda)!;
  // previsaoEntregaFim aqui guarda a mesma hora-do-dia do pedido (só a DATA
  // já pula dias fechados — ver `finalizar_pedido_site`) — mostrar a hora
  // seria enganoso.
  if (!ehAgendado(venda) && venda.modalidade == 'economica') return 'Até ${dia.format(fim)}';
  final inicio = previsaoInicio(venda);
  if (inicio == null || !inicio.isBefore(fim)) return '~${dia.format(fim)} ${hora.format(fim)}';
  final mesmoDia = inicio.year == fim.year && inicio.month == fim.month && inicio.day == fim.day;
  return mesmoDia
      ? '${dia.format(fim)} de ${hora.format(inicio)} às ${hora.format(fim)}'
      : '${dia.format(inicio)} ${hora.format(inicio)} às ${dia.format(fim)} ${hora.format(fim)}';
}
