import 'package:intl/intl.dart';

import '../models/venda.dart';
import 'previsao_entrega_utils.dart';

/// Texto padrão da mensagem manual de status por WhatsApp — decisão do
/// usuário (19/09): só estas 5 etapas têm botão de envio (Pendente,
/// Preparando [só quando há alteração no pedido], Pronto [só retirada],
/// Saiu para entrega, Entregue, Cancelado); Aguardando pagamento e
/// Aguardando conciliação ficam de fora.
///
/// Devolve `null` quando o status não tem mensagem (não mostra o botão).
/// `*destaque*` é a sintaxe de negrito do próprio WhatsApp (um asterisco só
/// de cada lado) — o texto já sai pronto pra colar, mas quem manda sempre
/// revisa/edita antes de abrir o WhatsApp (por isso o placeholder livre na
/// mensagem de Preparando).
String? mensagemPadraoStatus(Venda venda, String status) {
  final primeiroNome = venda.cliente.nome.trim().isEmpty ? '' : venda.cliente.nome.trim().split(' ').first;
  final saudacao = primeiroNome.isEmpty ? 'Oi!' : 'Oi, $primeiroNome!';
  final numero = venda.numeroSequencial != null ? ' #${venda.numeroSequencial}' : '';

  // Cada informação num bloco, separado por linha em branco — numa linha
  // só ficava tudo colado no WhatsApp (pedido do usuário 02/10).
  String blocos(List<String?> partes) =>
      partes.where((p) => p != null && p.trim().isNotEmpty).join('\n\n');

  switch (status) {
    case StatusPedido.pendente:
      return blocos([
        '$saudacao Recebemos seu pedido$numero 🥰',
        '*${_previsaoParaPendente(venda)}*',
        'Já estamos cuidando de tudo por aqui!',
      ]);

    case StatusPedido.preparando:
      // Não é ping de "começamos a preparar" — só existe pra avisar uma
      // alteração (item trocado/removido/em falta), decisão explícita do
      // usuário. Por isso o placeholder livre em vez de texto fixo.
      return blocos([
        '$saudacao Um aviso rapidinho sobre seu pedido$numero:',
        '*[descreva aqui a alteração]*',
        'Qualquer dúvida, pode chamar a gente.',
      ]);

    case StatusPedido.pronto:
      if (!venda.retirada) return null; // só retirada, decisão do usuário
      return blocos([
        'Seu pedido$numero já está *pronto pra retirada*! 📦',
        'Te esperamos por aqui!',
      ]);

    case StatusPedido.saiuParaEntrega:
      return blocos([
        'Seu pedido$numero *saiu para entrega*! 🛵',
        'Fica de olho no celular: o entregador pode ligar ou tocar a campainha a qualquer momento.',
        _lembretePagamentoNaEntrega(venda),
      ]);

    case StatusPedido.entregue:
      return blocos([
        '$saudacao Seu pedido chegou certinho aí? 🥰',
        '*Como foi sua experiência?* Conta pra gente!',
        'Muito obrigada pela preferência.',
      ]);

    case StatusPedido.cancelado:
      final motivo = venda.motivoCancelamentoDescricao?.trim();
      return blocos([
        'Oi${primeiroNome.isEmpty ? '' : ', $primeiroNome'}, seu pedido$numero *foi cancelado*.',
        motivo,
        'Qualquer dúvida, estamos por aqui pra ajudar 🙏',
      ]);

    default:
      return null;
  }
}

String _previsaoParaPendente(Venda venda) {
  if (venda.retirada) return 'Assim que estiver pronto, te aviso pra retirar';
  if (!temPrevisaoEntrega(venda)) return 'Já já te aviso com a previsão de entrega';
  return '${labelPrevisaoEntrega(venda)}: ${formatarPrevisaoEntrega(venda)}';
}

/// Só faz sentido lembrar de separar dinheiro/cartão quando o pagamento é
/// cobrado NA entrega — pedido já pago online (`pagoOnline`) não precisa
/// disso. `venda.troco` já é o valor de troco a devolver (mesmo campo
/// mostrado na aba Pagamento como "Troco"), não o valor da nota que o
/// cliente vai usar pra pagar.
String? _lembretePagamentoNaEntrega(Venda venda) {
  if (venda.pagoOnline) return null;
  final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  switch (venda.metodoPagamento) {
    case 'Dinheiro':
      final trocoTexto = venda.troco > 0 ? ' — vamos te devolver *${moeda.format(venda.troco)}* de troco' : '';
      return 'Já separa *${moeda.format(venda.valorTotal)}*$trocoTexto. Fica mais rápido pra você também.';
    case 'Cartão de Crédito':
    case 'Cartão de Débito':
      return 'Já deixa o cartão à mão — fica mais rápido pra você também.';
    case 'Pix':
      return 'Já deixa o Pix pronto pra escanear — fica mais rápido pra você também.';
    default:
      return null;
  }
}
