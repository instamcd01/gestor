import 'package:flutter/material.dart';

/// Agrupa campos de formulário relacionados sob um rótulo, num card —
/// usado nos formulários de produto (cadastro/edição) pra substituir a
/// "lista plana" de 20 campos soltos por seções escaneáveis. Repita esse
/// padrão em outros formulários grandes em vez de inventar outro jeito
/// de agrupar campos.
class FormSection extends StatelessWidget {
  final String titulo;
  final List<Widget> children;

  const FormSection({super.key, required this.titulo, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Text(
            titulo,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _comEspacamento(children),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _comEspacamento(List<Widget> items) {
    final resultado = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) resultado.add(const SizedBox(height: 16));
      resultado.add(items[i]);
    }
    return resultado;
  }
}
