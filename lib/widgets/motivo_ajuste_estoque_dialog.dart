import 'package:flutter/material.dart';

import '../models/movimentacao_estoque.dart';

/// Pergunta o motivo de um ajuste manual de estoque — obrigatório, vai pro
/// histórico de movimentações (RPC `ajustar_estoque`). Retorna null se o
/// usuário cancelar.
Future<({String motivo, String? observacao})?> perguntarMotivoAjusteEstoque(
  BuildContext context, {
  required String nomeProduto,
  required int de,
  required int para,
}) {
  return showDialog<({String motivo, String? observacao})>(
    context: context,
    builder: (_) => _MotivoAjusteEstoqueDialog(nomeProduto: nomeProduto, de: de, para: para),
  );
}

class _MotivoAjusteEstoqueDialog extends StatefulWidget {
  final String nomeProduto;
  final int de;
  final int para;

  const _MotivoAjusteEstoqueDialog({required this.nomeProduto, required this.de, required this.para});

  @override
  State<_MotivoAjusteEstoqueDialog> createState() => _MotivoAjusteEstoqueDialogState();
}

class _MotivoAjusteEstoqueDialogState extends State<_MotivoAjusteEstoqueDialog> {
  String? _motivo;
  final _observacaoController = TextEditingController();

  @override
  void dispose() {
    _observacaoController.dispose();
    super.dispose();
  }

  bool get _podeConfirmar =>
      _motivo != null && (_motivo != 'outro' || _observacaoController.text.trim().isNotEmpty);

  @override
  Widget build(BuildContext context) {
    final diferenca = widget.para - widget.de;
    final motivos = motivosAjusteEstoque.entries.where((e) => e.key != 'importacao_planilha');

    return AlertDialog(
      title: const Text('Motivo do ajuste de estoque'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.nomeProduto, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('${widget.de} → ${widget.para} (${diferenca > 0 ? '+' : ''}$diferenca)'),
              const SizedBox(height: 12),
              RadioGroup<String>(
                groupValue: _motivo,
                onChanged: (v) => setState(() => _motivo = v),
                child: Column(
                  children: [
                    for (final m in motivos)
                      RadioListTile<String>(
                        value: m.key,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(m.value),
                      ),
                  ],
                ),
              ),
              TextField(
                controller: _observacaoController,
                decoration: InputDecoration(
                  labelText: _motivo == 'outro' ? 'Descreva o motivo' : 'Observação (opcional)',
                ),
                maxLines: 2,
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _podeConfirmar
              ? () => Navigator.pop(context, (
                    motivo: _motivo!,
                    observacao: _observacaoController.text.trim().isEmpty ? null : _observacaoController.text.trim(),
                  ))
              : null,
          child: const Text('Confirmar ajuste'),
        ),
      ],
    );
  }
}
