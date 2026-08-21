import 'package:flutter/material.dart';

import '../utils/busca_utils.dart';

/// Campo de texto com sugestão dos valores já usados nesse campo (vocabulário
/// curado em `valores_estruturados_variante`, ver `ValorEstruturadoRepository`)
/// — tocar no campo já mostra a lista (não precisa digitar nada pra ver as
/// opções), filtra conforme digita (mesma normalização de acento/maiúscula da
/// busca de produtos), e digitar algo que não está na lista continua
/// funcionando normalmente (não exige escolher uma opção existente).
/// Extraído de `campos_estruturados_variante.dart` pra ser reaproveitado
/// também em `vincular_variante_dialog.dart`.
class CampoComSugestao extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? helperText;
  final List<String> sugestoes;

  const CampoComSugestao({
    super.key,
    required this.controller,
    required this.label,
    this.helperText,
    required this.sugestoes,
  });

  @override
  State<CampoComSugestao> createState() => _CampoComSugestaoState();
}

class _CampoComSugestaoState extends State<CampoComSugestao> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (value) {
        if (value.text.isEmpty) return widget.sugestoes;
        return widget.sugestoes.where((s) => contemTodasPalavras(s, value.text));
      },
      fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: textEditingController,
          focusNode: focusNode,
          decoration: InputDecoration(labelText: widget.label, helperText: widget.helperText),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final lista = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220, maxWidth: 320),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: lista.length,
                itemBuilder: (context, index) {
                  final opcao = lista[index];
                  return ListTile(
                    dense: true,
                    title: Text(opcao),
                    onTap: () => onSelected(opcao),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
