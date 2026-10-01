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
          maxLines: 6,
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
  final uri = Uri.parse(linkWhatsAppComTexto(numero, controller.text));
  if (await canLaunchUrl(uri)) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
