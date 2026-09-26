import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/venda.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _hora = DateFormat('HH:mm');
final _diaHora = DateFormat('dd/MM HH:mm');

/// Texto pra repassar ao entregador (WhatsApp) — nome, endereço, o que
/// cobrar e até que horas sair. O trecho do pagamento vai em negrito do
/// WhatsApp (`*...*`), porque é o que não pode passar despercebido; o nome
/// do cliente também, pra achar rápido. Uma linha em branco entre cada
/// dado (pedido do usuário — lido no celular, no meio da rua).
String mensagemEntregador(Venda venda, {DateTime? agora}) {
  final momento = agora ?? DateTime.now();
  final cliente = venda.cliente;
  final numero = venda.numeroExibicaoMarketplace ?? venda.numeroSequencial?.toString();

  final linhas = <String>[
    if (numero != null) 'Pedido #$numero',
    'Cliente: *${cliente.nome.trim()}*',
    if (cliente.enderecoExibicao.isNotEmpty) 'Endereço: ${cliente.enderecoExibicao}',
    // Mesma regra do "abrir no mapa" da tela: coordenada exata (marcada no
    // mapa no cadastro) quando existe, senão o texto do endereço.
    if (cliente.latitude != null && cliente.longitude != null)
      'Mapa: https://www.google.com/maps/search/?api=1&query=${cliente.latitude},${cliente.longitude}'
    else if (cliente.enderecoCompleto.isNotEmpty)
      'Mapa: https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(cliente.enderecoCompleto)}',
    // Cliente marcou o ponto no mapa do site: o número digitado pode estar
    // impreciso (rua longa), o pino é a referência.
    if (cliente.pontoAjustadoCliente && cliente.latitude != null && cliente.longitude != null)
      '📍 *Ponto marcado pelo cliente no mapa — siga o link do mapa*',
    ..._linhasPagamento(venda),
  ];

  final horario = _linhaHorario(venda, momento);
  if (horario != null) linhas.add(horario);

  return linhas.join('\n\n');
}

List<String> _linhasPagamento(Venda venda) {
  if (venda.aguardandoPagamento) {
    return ['*Pagamento online ainda em confirmação — NÃO cobrar*'];
  }
  // `formaPagamentoEditavel` já é a regra de "ainda é cobrado na
  // entrega/retirada": false quando pago no Mercado Pago ou já pago pelo
  // iFood/99Food — reaproveitada em vez de repetir a condição aqui.
  if (!venda.formaPagamentoEditavel) return ['*JÁ PAGO — NÃO COBRAR*'];

  return [
    '*COBRAR NA ENTREGA: ${_moeda.format(venda.valorTotal)} (${venda.metodoPagamento})*',
    if (venda.troco > 0) '*Levar troco: ${_moeda.format(venda.troco)}*',
  ];
}

/// Horário máximo de saída = fim do prazo de entrega − tempo real de rota até
/// o cliente (Google Maps, calculado no checkout) — mesma conta da
/// notificação "Hora de sair!" (`notificar_pedidos_hora_saida_entrega`) e do
/// selo "Atenção" da Fila de Pedidos. Sem tempo de rota (ex: cliente do
/// iFood), mostra só o prazo de entrega.
String? _linhaHorario(Venda venda, DateTime agora) {
  final fim = venda.previsaoEntregaFim ?? venda.entregaPrevistaFim;
  if (fim == null) return null;

  // Econômica: a previsão guarda só o DIA (a hora repete a do pedido), então
  // hora de saída seria enganosa — mesmo cuidado da tela de detalhe.
  if (venda.modalidade == 'economica') return 'Entregar até ${DateFormat('dd/MM').format(fim)}';

  String formatar(DateTime d) =>
      DateUtils.isSameDay(d, agora) ? _hora.format(d) : _diaHora.format(d);

  final inicio = venda.previsaoEntregaInicio ?? venda.entregaPrevistaInicio;
  final agendado = venda.agendado || venda.agendadoManualmente;
  final prazo = agendado && inicio != null
      ? 'entregar entre ${formatar(inicio)} e ${formatar(fim)}'
      : 'entregar até ${formatar(fim)}';

  final rotaMin = venda.cliente.estimativaEntrega;
  if (rotaMin == null || rotaMin <= 0) return 'Prazo: $prazo';

  final saida = fim.subtract(Duration(minutes: rotaMin));
  final atrasado = saida.isBefore(agora) ? ' — JÁ PASSOU, sair agora' : '';
  return 'Sair até: ${formatar(saida)}$atrasado ($prazo, ~$rotaMin min de rota)';
}

/// Copia [mensagemEntregador] pra área de transferência e avisa na tela.
Future<void> copiarMensagemEntregador(BuildContext context, Venda venda) async {
  await Clipboard.setData(ClipboardData(text: mensagemEntregador(venda)));
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Dados da entrega copiados — é só colar pro entregador.')),
  );
}
