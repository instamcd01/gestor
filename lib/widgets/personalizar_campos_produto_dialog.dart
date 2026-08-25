import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/produto.dart';
import '../providers/produto_provider.dart';
import '../repositories/valor_estruturado_repository.dart';
import '../utils/busca_utils.dart';

/// Os 9 campos que `CamposEstruturadosVariante` realmente renderiza (peso/
/// volume/fabricante entram na ordem do NOME gerado, mas moram na seção
/// "Logística e fornecedor" do formulário, não aqui) — universo fixo
/// oferecido pra ativar/desativar/reordenar por produto.
const List<String> camposPersonalizaveisProduto = [
  'tipo_produto',
  'nome_comercial',
  'dose',
  'composicao',
  'apresentacao',
  'especie',
  'fase',
  'porte',
  'sabor',
];

/// Ativa/desativa e reordena, só pra ESTE produto, quais campos do cadastro
/// estruturado aparecem — sobrepõe o padrão da categoria
/// (`categoria_campos_estruturados`) sem alterá-lo pros demais produtos.
/// Aberto a partir do botão "Personalizar campos deste produto" em
/// `CamposEstruturadosVariante`.
class PersonalizarCamposProdutoDialog extends StatefulWidget {
  final String? produtoAtualId;

  /// Campos ativos hoje pra este produto, já na ordem efetiva (vinda da
  /// personalização já salva, ou do padrão da categoria se ainda não
  /// personalizado) — ponto de partida pra edição.
  final List<String> ordemAtual;
  final ValueChanged<List<String>> onSalvar;
  final VoidCallback onRestaurarPadrao;

  const PersonalizarCamposProdutoDialog({
    super.key,
    required this.produtoAtualId,
    required this.ordemAtual,
    required this.onSalvar,
    required this.onRestaurarPadrao,
  });

  @override
  State<PersonalizarCamposProdutoDialog> createState() => _PersonalizarCamposProdutoDialogState();
}

class _PersonalizarCamposProdutoDialogState extends State<PersonalizarCamposProdutoDialog> {
  late List<String> _ordem;
  late Set<String> _ativos;

  @override
  void initState() {
    super.initState();
    _aplicarLista(widget.ordemAtual);
  }

  // Monta a lista completa dos 9 campos (universo fixo) na ordem recebida
  // primeiro, seguida dos que faltam (inativos) na ordem padrão — pra sempre
  // dar pra reativar/reordenar qualquer um dos 9, mesmo o que estava fora.
  void _aplicarLista(List<String> ativos) {
    _ordem = [
      for (final c in ativos) if (camposPersonalizaveisProduto.contains(c)) c,
      for (final c in camposPersonalizaveisProduto) if (!ativos.contains(c)) c,
    ];
    _ativos = {...ativos, 'nome_comercial'};
  }

  Future<void> _copiarDeOutroProduto() async {
    final candidatos = context
        .read<ProdutoProvider>()
        .produtos
        .where((p) => p.id != widget.produtoAtualId && p.camposEstruturadosPersonalizados != null)
        .toList();
    final escolhido = await showDialog<Produto>(
      context: context,
      builder: (_) => _BuscarProdutoComPersonalizacaoDialog(produtos: candidatos),
    );
    if (escolhido == null || !mounted) return;
    setState(() => _aplicarLista(escolhido.camposEstruturadosPersonalizados!));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Personalizar campos deste produto'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Arraste para reordenar. Desmarque o que não se aplica a este produto '
              'específico — não muda os outros produtos da mesma categoria.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.content_copy, size: 18),
                label: const Text('Copiar de outro produto'),
                onPressed: _copiarDeOutroProduto,
              ),
            ),
            const Divider(height: 1),
            SizedBox(
              height: 360,
              child: ReorderableListView(
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final campo = _ordem.removeAt(oldIndex);
                    _ordem.insert(newIndex, campo);
                  });
                },
                children: [
                  for (final campo in _ordem)
                    CheckboxListTile(
                      key: ValueKey(campo),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      title: Text(rotulosCamposEstruturados[campo] ?? campo),
                      subtitle: campo == 'nome_comercial' ? const Text('Sempre ativo') : null,
                      value: _ativos.contains(campo),
                      onChanged: campo == 'nome_comercial'
                          ? null
                          : (v) => setState(() {
                                if (v == true) {
                                  _ativos.add(campo);
                                } else {
                                  _ativos.remove(campo);
                                }
                              }),
                      secondary: const Icon(Icons.drag_handle),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onRestaurarPadrao();
            Navigator.pop(context);
          },
          child: const Text('Restaurar padrão da categoria'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            widget.onSalvar(_ordem.where(_ativos.contains).toList());
            Navigator.pop(context);
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

/// Busca simples pra escolher de qual produto copiar a personalização —
/// só lista produtos que já têm `camposEstruturadosPersonalizados` própria.
class _BuscarProdutoComPersonalizacaoDialog extends StatefulWidget {
  final List<Produto> produtos;

  const _BuscarProdutoComPersonalizacaoDialog({required this.produtos});

  @override
  State<_BuscarProdutoComPersonalizacaoDialog> createState() =>
      _BuscarProdutoComPersonalizacaoDialogState();
}

class _BuscarProdutoComPersonalizacaoDialogState extends State<_BuscarProdutoComPersonalizacaoDialog> {
  final _buscaController = TextEditingController();

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final busca = _buscaController.text;
    final resultados = (busca.isEmpty
            ? widget.produtos
            : widget.produtos.where((p) => contemTodasPalavras(p.nome, busca)))
        .take(30)
        .toList();

    return AlertDialog(
      title: const Text('Copiar personalização de qual produto?'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            TextField(
              controller: _buscaController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Buscar produto', prefixIcon: Icon(Icons.search)),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: resultados.isEmpty
                  ? const Center(child: Text('Nenhum produto com personalização própria encontrado.'))
                  : ListView.builder(
                      itemCount: resultados.length,
                      itemBuilder: (context, i) {
                        final p = resultados[i];
                        return ListTile(
                          title: Text(p.nome, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Text(p.categoria),
                          onTap: () => Navigator.pop(context, p),
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
}
