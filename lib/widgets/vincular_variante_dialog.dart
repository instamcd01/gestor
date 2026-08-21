import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/produto.dart';
import '../providers/produto_provider.dart';
import '../utils/busca_utils.dart';
import '../utils/variante_label_utils.dart';

const List<String> _tiposVariacao = ['peso', 'volume', 'dose', 'sabor', 'apresentacao', 'outro'];

/// Vincula manualmente dois produtos como variantes um do outro — pra
/// quando o produto não aparece nas sugestões automáticas (ver
/// `sugestoes_variante`, que só detecta por campos estruturados iguais ou
/// semelhança de nome). Dois passos: escolher o outro produto, depois
/// definir o eixo e o rótulo de cada lado — mesmos campos de
/// `DialogoRevisaoVariante`, só que sem uma sugestão pronta por trás.
class VincularVarianteDialog extends StatefulWidget {
  final Produto produto;

  const VincularVarianteDialog({super.key, required this.produto});

  @override
  State<VincularVarianteDialog> createState() => _VincularVarianteDialogState();
}

class _VincularVarianteDialogState extends State<VincularVarianteDialog> {
  Produto? _candidato;
  final _buscaController = TextEditingController();
  late TextEditingController _labelProdutoController;
  late TextEditingController _labelCandidatoController;
  String _tipoVariacao = 'peso';
  bool _processando = false;

  @override
  void initState() {
    super.initState();
    _labelProdutoController = TextEditingController(text: widget.produto.varianteLabel ?? '');
    _labelCandidatoController = TextEditingController();
  }

  @override
  void dispose() {
    _buscaController.dispose();
    _labelProdutoController.dispose();
    _labelCandidatoController.dispose();
    super.dispose();
  }

  void _selecionarCandidato(Produto p) {
    setState(() {
      _candidato = p;
      _labelCandidatoController.text = labelPadraoVariante(p, _tipoVariacao);
    });
  }

  Future<void> _vincular() async {
    final candidato = _candidato;
    if (candidato == null) return;
    setState(() => _processando = true);
    try {
      await context.read<ProdutoProvider>().vincularVarianteManualmente(
            produtoId: widget.produto.id!,
            produtoCandidatoId: candidato.id!,
            tipoVariacao: _tipoVariacao,
            varianteLabelProduto: _labelProdutoController.text,
            varianteLabelCandidato: _labelCandidatoController.text,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível vincular: $e')),
        );
        setState(() => _processando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidato = _candidato;

    if (candidato == null) {
      final todos = context.watch<ProdutoProvider>().produtos;
      final busca = _buscaController.text;
      final resultados = (busca.isEmpty
              ? todos
              : todos.where((p) => contemTodasPalavras(p.nome, busca)))
          .where((p) => p.id != widget.produto.id)
          .take(30)
          .toList();

      return AlertDialog(
        title: const Text('Vincular a outro produto'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: Column(
            children: [
              TextField(
                controller: _buscaController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Buscar produto',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: resultados.isEmpty
                    ? const Center(child: Text('Nenhum produto encontrado.'))
                    : ListView.builder(
                        itemCount: resultados.length,
                        itemBuilder: (context, i) {
                          final p = resultados[i];
                          return ListTile(
                            title: Text(p.nome, maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text('R\$ ${p.preco.toStringAsFixed(2)}'),
                            onTap: () => _selecionarCandidato(p),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Vincular a outro produto'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _tipoVariacao,
              decoration: const InputDecoration(labelText: 'Eixo da variação'),
              items: [
                for (final tipo in _tiposVariacao)
                  DropdownMenuItem(value: tipo, child: Text(rotuloTipoVariacao(tipo))),
              ],
              onChanged: (v) => setState(() {
                _tipoVariacao = v!;
                if (_labelCandidatoController.text.isEmpty) {
                  _labelCandidatoController.text = labelPadraoVariante(candidato, _tipoVariacao);
                }
              }),
            ),
            const SizedBox(height: 16),
            Text(widget.produto.nome, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
            TextField(
              controller: _labelProdutoController,
              decoration: const InputDecoration(labelText: 'Opção deste produto'),
            ),
            const SizedBox(height: 16),
            Text(candidato.nome, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
            TextField(
              controller: _labelCandidatoController,
              decoration: const InputDecoration(labelText: 'Opção do outro produto'),
            ),
          ],
        ),
      ),
      actions: _processando
          ? [const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator())]
          : [
              TextButton(onPressed: () => setState(() => _candidato = null), child: const Text('Voltar')),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
              FilledButton(onPressed: _vincular, child: const Text('Vincular')),
            ],
    );
  }
}
