import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/venda.dart';
import 'telefone_utils.dart';

/// Diálogo de "Mensagem pro cliente" reaproveitado onde quer que apareça o
/// botão de WhatsApp por status (AppBar de `venda_detalhes_screen.dart` e
/// cada card de `fila_pedidos_screen.dart`) — sempre abre pra revisar/editar
/// antes (é onde a etapa "Preparando" preenche o texto livre da alteração,
/// ver `mensagens_status_pedido.dart`), e quem manda de verdade aperta
/// enviar no próprio WhatsApp — não passa pela Cloud API, então funciona
/// mesmo com o número ainda em modo de teste.
Future<void> enviarMensagemStatusWhatsApp(BuildContext context, Venda venda, String mensagemPadrao) async {
  final controller = TextEditingController(text: mensagemPadrao);
  final confirmou = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Mensagem pro cliente'),
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
  if (await canLaunchUrl(uriApp)) {
    await launchUrl(uriApp, mode: LaunchMode.externalApplication);
  } else if (await canLaunchUrl(uriWeb)) {
    await launchUrl(uriWeb, mode: LaunchMode.externalApplication);
  } else if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível abrir o WhatsApp.')));
  }
}
