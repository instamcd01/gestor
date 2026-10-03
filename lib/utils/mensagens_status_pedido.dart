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
/// [nomeLoja] vem do branding (`BrandingProvider.nomeEmpresa`).
String? mensagemPadraoStatus(Venda venda, String status, {String? nomeLoja}) {
  final primeiroNome = venda.cliente.nome.trim().isEmpty ? '' : venda.cliente.nome.trim().split(' ').first;
  final saudacao = primeiroNome.isEmpty ? 'Oi!' : 'Oi, $primeiroNome!';
  final numero = venda.numeroSequencial != null ? ' #${venda.numeroSequencial}' : '';

  // Cada informação num bloco, separado por linha em branco — numa linha
  // só ficava tudo colado no WhatsApp (pedido do usuário 02/10).
  String blocos(List<String?> partes) =>
      partes.where((p) => p != null && p.trim().isNotEmpty).join('\n\n');

  switch (status) {
    // Estratégia (definida com o usuário 02/10): cada mensagem mostra que a
    // loja acompanha a jornada do pedido, com cuidado concreto e sem
    // prometer o que não dá pra cumprir (não há rastreio do entregador).
    // "Saiu pra entrega" fecha com gratidão pra preparar o clima da
    // pergunta de "Entregue" — cuja resposta abre o pedido de avaliação no
    // Google (que vai pra TODO cliente que responder, nunca só pros que
    // elogiaram: o Google proíbe "review gating").
    case StatusPedido.pendente:
      return blocos([
        '$saudacao Recebemos seu pedido$numero 🥰',
        '*${_previsaoParaPendente(venda)}*',
        'Já estou separando tudo com muito carinho.',
        'Agradecemos por escolher a ${_nomeLoja(nomeLoja)} ❤️',
      ]);

    case StatusPedido.preparando:
      // Não é ping de "começamos a preparar" — só existe pra avisar uma
      // alteração (item trocado/removido/em falta), decisão explícita do
      // usuário. Por isso o placeholder livre em vez de texto fixo.
      return blocos([
        '$saudacao Antes de enviar seu pedido$numero, preciso te avisar uma coisa:',
        '*[descreva aqui a alteração]*',
        'Preferi te consultar antes pra você decidir como prefere. Me responde aqui que eu ajusto na hora.',
      ]);

    case StatusPedido.pronto:
      if (!venda.retirada) return null; // só retirada, decisão do usuário
      return blocos([
        '$saudacao Seu pedido$numero já está *pronto pra retirada* 📦',
        'Separei e conferi tudo, já está te esperando aqui.',
        'Se quiser, me avisa quando estiver chegando que deixo tudo à mão pra você.',
      ]);

    case StatusPedido.saiuParaEntrega:
      return blocos([
        'Seu pedido$numero *saiu para entrega* 🛵',
        // Genérico de propósito: muitas vezes o entregador não liga, só
        // chega e buzina no portão (correção do usuário 02/10).
        'Fique atento para quando o entregador chegar!',
        _lembretePagamentoNaEntrega(venda),
        'Esperamos que seu pet aproveite! Obrigada pela confiança 🐾❤️',
      ]);

    case StatusPedido.entregue:
      return blocos([
        'Seu pedido chegou certinho? 🥰',
        '*Como foi sua experiência com a gente?* Sua opinião ajuda muito a gente a melhorar.',
        'Conte sempre com a gente! ❤️',
      ]);

    case StatusPedido.cancelado:
      final motivo = venda.motivoCancelamentoDescricao?.trim();
      final oi = 'Oi${primeiroNome.isEmpty ? '' : ', $primeiroNome'}';
      switch (venda.origemCancelamento) {
        case 'cliente':
          return blocos([
            '$oi! Cancelamento do pedido$numero feito, como você pediu.',
            'Quando precisar de qualquer coisa pro seu pet, estamos por aqui ❤️',
          ]);
        case 'sistema': // pagamento recusado/abandonado
          return blocos([
            '$oi. Seu pedido$numero *foi cancelado*.',
            motivo,
            'Se quiser, te ajudo a refazer agora mesmo, é só me responder aqui.',
          ]);
        default: // loja
          return blocos([
            '$oi. Precisei cancelar seu pedido$numero.',
            motivo,
            'Sinto muito pelo transtorno. Se quiser, já vejo uma alternativa pra você, é só me responder aqui.',
          ]);
      }

    default:
      return null;
  }
}

/// Pedido de avaliação no Google — enviado DEPOIS que o cliente responde a
/// mensagem de "Entregue" (texto aprovado pelo usuário 02/10). Vai pra todo
/// cliente que responder, não só pros que elogiaram: o Google proíbe pedir
/// avaliação de forma seletiva ("review gating").
String mensagemPedidoAvaliacaoGoogle(String link) => [
      'Ahh que bom! Fiquei muito feliz de ler isso 🥰\n'
          'Vou mostrar seu recado pro pessoal aqui, eles vão amar',
      'Consegue deixar esse carinho no Google também? É rapidinho 🙏🏼\n$link',
      'Muito obrigada! ❤️',
    ].join('\n\n');

String _nomeLoja(String? nome) => (nome == null || nome.trim().isEmpty || nome == 'Gestor') ? 'nossa loja' : nome.trim();

String _previsaoParaPendente(Venda venda) {
  if (venda.retirada) return 'Assim que estiver pronto, te aviso pra retirar';
  if (!temPrevisaoEntrega(venda)) return 'Já já te aviso com a previsão de entrega';
  return '${labelPrevisaoEntrega(venda)}: ${formatarPrevisaoEntrega(venda)}';
}

/// Só informa o valor e a forma de pagamento quando é cobrado NA entrega —
/// pedido já pago online (`pagoOnline`) não precisa. Tom informativo, sem
/// mandar o cliente fazer nada ("já separa...", "fica mais rápido pra
/// você" foram vetados pelo usuário 02/10). `venda.troco` já é o troco a
/// devolver (mesmo campo da aba Pagamento), não a nota que o cliente usa.
String? _lembretePagamentoNaEntrega(Venda venda) {
  if (venda.pagoOnline) return null;
  final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final valor = '*${moeda.format(venda.valorTotal)}*';

  switch (venda.metodoPagamento) {
    case 'Dinheiro':
      final troco = venda.troco > 0 ? ' (troco de *${moeda.format(venda.troco)}*)' : '';
      return 'Pagamento na entrega: $valor em dinheiro$troco.';
    case 'Cartão de Crédito':
      return 'Pagamento na entrega: $valor no cartão de crédito.';
    case 'Cartão de Débito':
      return 'Pagamento na entrega: $valor no cartão de débito.';
    case 'Pix':
      return 'Pagamento na entrega: $valor via Pix.';
    default:
      return null;
  }
}
