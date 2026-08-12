import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/produto.dart';
import '../models/sugestao_variante.dart';
import '../providers/produto_provider.dart';
import '../utils/variante_label_utils.dart';

/// Diálogo de revisão das sugestões automáticas de agrupamento de variante
/// pra um produto — um produto pode ter mais de uma pendente (ex: 3+
/// variantes da mesma linha), então passa por elas uma de cada vez ("X de
/// N"), sem fechar até acabar. Compara os dois produtos lado a lado e deixa
/// o rótulo de cada um editável antes de aprovar. Nada é publicado sem essa
/// confirmação manual (ver seção 4 da spec de variantes).
class DialogoRevisaoVariante extends StatefulWidget {
  final Produto produto;
  final List<SugestaoVariante> sugestoes;

  const DialogoRevisaoVariante({super.key, required this.produto, required this.sugestoes});

  @override
  State<DialogoRevisaoVariante> createState() => _DialogoRevisaoVarianteState();
}

class _DialogoRevisaoVarianteState extends State<DialogoRevisaoVariante> {
  late List<SugestaoVariante> _restantes;
  late TextEditingController _labelProdutoController;
  late TextEditingController _labelCandidatoController;
  Produto? _candidato;
  bool _processando = false;

  @override
  void initState() {
    super.initState();
    _restantes = List.of(widget.sugestoes);
    _prepararAtual();
  }

  void _prepararAtual() {
    final atual = _restantes.first;
    _candidato = context.read<ProdutoProvider>().getProdutoPorId(atual.produtoCandidatoId);
    _labelProdutoController = TextEditingController(text: atual.varianteLabelSugerido);
    _labelCandidatoController = TextEditingController(
      text: _candidato != null ? labelPadraoVariante(_candidato!, atual.tipoVariacao) : '',
    );
  }

  @override
  void dispose() {
    _labelProdutoController.dispose();
    _labelCandidatoController.dispose();
    super.dispose();
  }

  void _avancar() {
    _restantes.removeAt(0);
    if (_restantes.isEmpty) {
      Navigator.pop(context);
      return;
    }
    _labelProdutoController.dispose();
    _labelCandidatoController.dispose();
    setState(() {
      _prepararAtual();
      _processando = false;
    });
  }

  Future<void> _aprovar() async {
    final atual = _restantes.first;
    setState(() => _processando = true);
    try {
      await context.read<ProdutoProvider>().aprovarSugestaoVariante(
            sugestao: atual,
            tipoVariacao: atual.tipoVariacao,
            varianteLabelProduto: _labelProdutoController.text,
            varianteLabelCandidato: _labelCandidatoController.text,
          );
      if (mounted) _avancar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao aprovar sugestão: $e')));
        setState(() => _processando = false);
      }
    }
  }

  Future<void> _rejeitar() async {
    final atual = _restantes.first;
    setState(() => _processando = true);
    try {
      await context.read<ProdutoProvider>().rejeitarSugestaoVariante(atual.id);
      if (mounted) _avancar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao rejeitar sugestão: $e')));
        setState(() => _processando = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final atual = _restantes.first;
    final candidato = _candidato;
    final origemTexto = atual.origem == 'estruturado'
        ? 'Detectado por campos estruturados iguais (alta confiança)'
        : 'Detectado por semelhança de nome — confira com atenção';

    return AlertDialog(
      title: Text(
        widget.sugestoes.length > 1
            ? 'Sugestão de variante (${widget.sugestoes.length - _restantes.length + 1} de ${widget.sugestoes.length})'
            : 'Sugestão de variante',
      ),
      content: candidato == null
          ? const Text('Produto candidato não encontrado.')
          : SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Eixo detectado: ${atual.tipoVariacao}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(origemTexto, style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 16),
                  Text(widget.produto.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
                  TextField(
                    controller: _labelProdutoController,
                    decoration: const InputDecoration(labelText: 'Opção deste produto'),
                  ),
                  const SizedBox(height: 16),
                  Text(candidato.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
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
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('Fechar')),
              TextButton(onPressed: _rejeitar, child: const Text('Rejeitar')),
              FilledButton(onPressed: candidato == null ? null : _aprovar, child: const Text('Aprovar')),
            ],
    );
  }
}
