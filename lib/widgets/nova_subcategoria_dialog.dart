import 'package:flutter/material.dart';

import '../config/supabase_config.dart';
import '../repositories/subcategoria_repository.dart';

/// Caixinha "Nova subcategoria em [categoriaNome]" usada no cadastro e na
/// edição de produto. Devolve o nome da subcategoria criada (ou da já
/// existente com o mesmo nome) pra ser selecionada no produto, ou null
/// se cancelar.
Future<String?> mostrarNovaSubcategoriaDialog(
  BuildContext context, {
  required String categoriaNome,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NovaSubcategoriaDialog(categoriaNome: categoriaNome),
  );
}

class _NovaSubcategoriaDialog extends StatefulWidget {
  final String categoriaNome;

  const _NovaSubcategoriaDialog({required this.categoriaNome});

  @override
  State<_NovaSubcategoriaDialog> createState() => _NovaSubcategoriaDialogState();
}

class _NovaSubcategoriaDialogState extends State<_NovaSubcategoriaDialog> {
  final _controller = TextEditingController();
  bool _salvando = false;
  String? _erro;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final nome = _controller.text.trim();
    if (nome.isEmpty) {
      setState(() => _erro = 'Digite o nome');
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      final categoria =
          await supabase.from('categorias').select('id').eq('nome', widget.categoriaNome).maybeSingle();
      if (categoria == null) throw StateError('Categoria "${widget.categoriaNome}" não encontrada');
      final salvo = await SubcategoriaRepository().criarOuObter(
        categoriaId: categoria['id'] as String,
        nome: nome,
      );
      if (mounted) Navigator.pop(context, salvo);
    } catch (e) {
      debugPrint('Erro ao criar subcategoria: $e');
      if (mounted) {
        setState(() {
          _salvando = false;
          _erro = 'Não foi possível salvar. Tente de novo.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Nova subcategoria em ${widget.categoriaNome}'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        enabled: !_salvando,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: 'Nome', errorText: _erro),
        onSubmitted: (_) => _salvar(),
      ),
      actions: [
        TextButton(
          onPressed: _salvando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _salvando ? null : _salvar,
          child: _salvando
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Salvar'),
        ),
      ],
    );
  }
}
