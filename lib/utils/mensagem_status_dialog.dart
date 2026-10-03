import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/supabase_config.dart';
import '../models/venda.dart';
import '../providers/auth_provider.dart';
import 'mensagens_status_pedido.dart';
import 'telefone_utils.dart';

/// Diálogo de "Mensagem pro cliente" reaproveitado onde quer que apareça o
/// botão de WhatsApp por status (AppBar de `venda_detalhes_screen.dart` e
/// cada card de `fila_pedidos_screen.dart`) — sempre abre pra revisar/editar
/// antes (é onde a etapa "Preparando" preenche o texto livre da alteração,
/// ver `mensagens_status_pedido.dart`), e quem manda de verdade aperta
/// enviar no próprio WhatsApp — não passa pela Cloud API, então funciona
/// mesmo com o número ainda em modo de teste.
///
/// Em pedido ENTREGUE pergunta antes qual mensagem: a de experiência (a
/// padrão da etapa) ou o pedido de avaliação no Google, que vai depois que o
/// cliente responde a primeira.
Future<void> enviarMensagemStatusWhatsApp(BuildContext context, Venda venda, String mensagemPadrao) async {
  var mensagem = mensagemPadrao;
  var ehPedidoAvaliacao = false;

  if (venda.status == StatusPedido.entregue) {
    final escolha = await _escolherMensagemEntregue(context, venda);
    if (escolha == null || !context.mounted) return;
    if (escolha == _MensagemEntregue.avaliacao) {
      final link = await _linkAvaliacaoGoogle(context.read<AuthProvider>().empresaId);
      if (!context.mounted) return;
      if (link == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link de avaliação do Google não cadastrado na empresa.')),
        );
        return;
      }
      mensagem = mensagemPedidoAvaliacaoGoogle(link);
      ehPedidoAvaliacao = true;
    }
  }

  final controller = TextEditingController(text: mensagem);
  final confirmou = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ehPedidoAvaliacao ? 'Pedir avaliação no Google' : 'Mensagem pro cliente'),
      content: SizedBox(
        width: double.maxFinite,
        child: TextField(
          controller: controller,
          // A mensagem vem em blocos separados por linha em branco — com 6
          // linhas o final ficava escondido na revisão.
          minLines: 6,
          maxLines: 14,
          autofocus: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: 'Revise ou edite antes de enviar',
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton.icon(
          onPressed: () => Navigator.pop(ctx, true),
          icon: const Icon(Icons.chat_bubble_outline),
          label: const Text('Abrir WhatsApp'),
        ),
      ],
    ),
  );
  if (confirmou != true || !context.mounted) return;

  final numero = venda.cliente.celular.isNotEmpty ? venda.cliente.celular : (venda.cliente.telefoneKyte ?? '');
  if (normalizarTelefoneBr(numero).isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Esse cliente não tem telefone cadastrado.')),
    );
    return;
  }
  // `wa.me` passa por um resolvedor de link que troca emoji fora do plano
  // básico (🥰🛵📦🙏, todos usados nestas mensagens) por "?" — mesmo bug
  // já contornado em `campanha_detalhe_screen.dart`. `whatsapp://send` abre o
  // app direto; `wa.me` só se o WhatsApp não estiver instalado.
  final texto = Uri.encodeComponent(controller.text);
  final telefone = telefoneParaLinkWhatsApp(numero);
  final uriApp = Uri.parse('whatsapp://send?phone=$telefone&text=$texto');
  final uriWeb = Uri.parse(linkWhatsAppComTexto(numero, controller.text));
  var abriu = false;
  if (await canLaunchUrl(uriApp)) {
    abriu = await launchUrl(uriApp, mode: LaunchMode.externalApplication);
  } else if (await canLaunchUrl(uriWeb)) {
    abriu = await launchUrl(uriWeb, mode: LaunchMode.externalApplication);
  } else if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível abrir o WhatsApp.')));
  }
  if (abriu && ehPedidoAvaliacao) await _registrarPedidoAvaliacao(venda);
}

enum _MensagemEntregue { experiencia, avaliacao }

Future<_MensagemEntregue?> _escolherMensagemEntregue(BuildContext context, Venda venda) async {
  final anterior = await _ultimoPedidoAvaliacao(venda);
  if (!context.mounted) return null;
  final formato = DateFormat('dd/MM/yy');
  return showModalBottomSheet<_MensagemEntregue>(
    context: context,
    useSafeArea: true,
    builder: (ctx) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ListTile(title: Text('Qual mensagem enviar?', style: TextStyle(fontWeight: FontWeight.w600))),
        ListTile(
          leading: const Text('1', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          title: const Text('Perguntar sobre a experiência'),
          subtitle: const Text('Primeiro: "Seu pedido chegou certinho? Como foi sua experiência?"'),
          onTap: () => Navigator.pop(ctx, _MensagemEntregue.experiencia),
        ),
        ListTile(
          leading: const Text('2', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          title: const Text('Pedir avaliação no Google'),
          subtitle: Text(
            'Depois que o cliente responder — pra todo cliente que responder, não só quem elogiou '
            '(o Google proíbe pedir de forma seletiva).'
            '${anterior != null ? '\nJá pedida pra este cliente em ${formato.format(anterior)}.' : ''}',
          ),
          onTap: () => Navigator.pop(ctx, _MensagemEntregue.avaliacao),
        ),
        const SizedBox(height: 8),
      ],
    ),
  );
}

Future<String?> _linkAvaliacaoGoogle(String? empresaId) async {
  if (empresaId == null) return null;
  try {
    final data =
        await supabase.from('empresas').select('link_avaliacao_google').eq('id', empresaId).maybeSingle();
    final link = (data?['link_avaliacao_google'] as String?)?.trim();
    return link == null || link.isEmpty ? null : link;
  } catch (e) {
    debugPrint('Erro ao ler link de avaliação do Google: $e');
    return null;
  }
}

/// Último pedido de avaliação feito pra este cliente (qualquer pedido).
Future<DateTime?> _ultimoPedidoAvaliacao(Venda venda) async {
  final clienteId = venda.cliente.idCliente;
  if (clienteId == null) return null;
  try {
    final data = await supabase
        .from('avaliacoes_google_pedidas')
        .select('enviado_em')
        .eq('cliente_id', clienteId)
        .order('enviado_em', ascending: false)
        .limit(1)
        .maybeSingle();
    return data == null ? null : DateTime.parse(data['enviado_em'] as String).toLocal();
  } catch (e) {
    debugPrint('Erro ao ler pedidos de avaliação anteriores: $e');
    return null;
  }
}

Future<void> _registrarPedidoAvaliacao(Venda venda) async {
  if (venda.idVenda == null) return;
  try {
    await supabase.from('avaliacoes_google_pedidas').insert({
      'pedido_id': venda.idVenda,
      'cliente_id': venda.cliente.idCliente,
    });
  } catch (e) {
    debugPrint('Erro ao registrar pedido de avaliação: $e');
  }
}
