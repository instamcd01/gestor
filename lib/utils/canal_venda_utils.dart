import 'package:flutter/material.dart';

/// Rótulo/ícone de exibição pra `pedidos.canal_venda` — usado em toda tela
/// que mostra de onde veio um pedido (Fila de Pedidos, detalhe da venda,
/// estatísticas). Único lugar que sabe os valores reais gravados no banco
/// (`loja_fisica`/`site_proprio`/`whatsapp`/`ifood`/`99food`) — antes
/// existiam 2 cópias idênticas desse switch (uma em cada tela), e nenhuma
/// delas reconhecia `'site_proprio'`/`'99food'` (caíam no mesmo `default`
/// de "Loja Física" que uma venda de balcão de verdade, escondendo de onde
/// o pedido realmente veio — bug real reportado pelo usuário 12/08).
String rotuloCanalVenda(String canal) {
  switch (canal) {
    case 'whatsapp':
      return 'WhatsApp';
    case 'ifood':
      return 'iFood';
    case '99food':
      return '99Food';
    case 'site':
    case 'site_proprio':
      return 'Site';
    default:
      return 'Loja Física';
  }
}

IconData iconeCanalVenda(String canal) {
  switch (canal) {
    case 'whatsapp':
      return Icons.chat;
    case 'ifood':
      return Icons.delivery_dining;
    case '99food':
      return Icons.two_wheeler;
    case 'site':
    case 'site_proprio':
      return Icons.language;
    default:
      return Icons.storefront;
  }
}
