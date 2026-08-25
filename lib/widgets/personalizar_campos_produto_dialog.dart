import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/supabase_config.dart';
import '../models/produto.dart';
import '../providers/auth_provider.dart';
import '../providers/produto_provider.dart';
import '../repositories/valor_estruturado_repository.dart';
import '../utils/busca_utils.dart';

/// Ativa/desativa e reordena, só pra ESTE produto, quais dos 12 campos
/// entram no NOME gerado automaticamente (`compor_nome_produto`) e em que
/// ordem — sobrepõe o padrão da categoria (`categoria_campos_estruturados`)
/// sem alterá-lo pros demais produtos. **Não tem nenhuma relação com o
/// formulário de cadastro** (o que aparece pra digitar continua decidido
/// só pela categoria) — decisão explícita do usuário pra manter as duas
/// coisas independentes. Aberto a partir do botão "Personalizar ordem do
/// nome deste produto" em `CamposEstruturadosVariante`.
class PersonalizarCamposProdutoDialog extends StatefulWidget {
  final String? produtoAtualId;

  /// Campos ativos hoje pra este produto, já na ordem efetiva (vinda da
  /// personalização já salva, ou do padrão da categoria se ainda não
  /// personalizado) — ponto de partida pra edição.
  final List<String> ordemAtual;

  // Valores atuais dos 12 campos (o que está digitado agora nos
  // controllers, ainda que não salvo) — só pra montar a prévia real do
  // nome, mesmo padrão de `estrutura_nome_produto_screen.dart` mas com
  // dado real deste produto em vez de exemplo genérico.
  final String categoria;
  final String? tipoProduto;
  final String? nomeComercial;
  final String? dose;
  final String? composicao;
  final String? apresentacao;
  final String? especie;
  final String? fase;
  final String? porte;
  final String? sabor;
  final double? peso;
  final double? volume;
  final String? fabricante;

  final ValueChanged<List<String>> onSalvar;
  final VoidCallback onRestaurarPadrao;

  const PersonalizarCamposProdutoDialog({
    super.key,
    required this.produtoAtualId,
    required this.ordemAtual,
    required this.categoria,
    required this.tipoProduto,
    required this.nomeComercial,
    required this.dose,
    required this.composicao,
    required this.apresentacao,
    required this.especie,
    required this.fase,
    required this.porte,
    required this.sabor,
    required this.peso,
    required this.volume,
    required this.fabricante,
    required this.onSalvar,
    required this.onRestaurarPadrao,
  });

  @override
  State<PersonalizarCamposProdutoDialog> createState() => _PersonalizarCamposProdutoDialogState();
}

class _PersonalizarCamposProdutoDialogState extends State<PersonalizarCamposProdutoDialog> {
  late List<String> _ordem;
  late Set<String> _ativos;
  String? _preview;

  @override
  void initState() {
    super.initState();
    _aplicarLista(widget.ordemAtual);
    _atualizarPreview();
  }

  // Monta a lista completa dos 12 campos (universo fixo, mesmo de
  // `compor_nome_produto`) na ordem recebida primeiro, seguida dos que
  // faltam (inativos) na ordem padrão — pra sempre dar pra reativar/
  // reordenar qualquer um dos 12, mesmo o que estava fora.
  void _aplicarLista(List<String> ativos) {
    _ordem = [
      for (final c in ativos) if (ordemPadraoCamposEstruturados.contains(c)) c,
      for (final c in ordemPadraoCamposEstruturados) if (!ativos.contains(c)) c,
    ];
    _ativos = {...ativos, 'nome_comercial'};
  }

  Future<void> _atualizarPreview() async {
    try {
      final empresaId = context.read<AuthProvider>().empresaId;
      final resultado = await supabase.rpc('compor_nome_produto', params: {
        'p_categoria': widget.categoria,
        'p_nome_comercial': widget.nomeComercial,
        'p_tipo_produto': widget.tipoProduto,
        'p_dose': widget.dose,
        'p_composicao': widget.composicao,
        'p_apresentacao': widget.apresentacao,
        'p_especie': widget.especie,
        'p_fase': widget.fase,
        'p_porte': widget.porte,
        'p_sabor': widget.sabor,
        // Peso e volume são mutuamente exclusivos na formatação real (peso
        // tem prioridade) — mesma regra de `compor_nome_produto`.
        'p_peso': widget.peso,
        'p_volume': widget.peso == null ? widget.volume : null,
        'p_fabricante': widget.fabricante,
        'p_ordem_campos': _ordem.where(_ativos.contains).toList(),
        'p_empresa_id': empresaId,
      });
      if (!mounted) return;
      setState(() => _preview = resultado as String?);
    } catch (e) {
      debugPrint('Erro ao pré-visualizar nome personalizado: $e');
    }
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
    _atualizarPreview();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Personalizar ordem do nome deste produto'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _preview?.isNotEmpty == true ? _preview! : '(preencha ao menos um campo)',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Prévia com os dados reais deste produto. Não muda quais campos aparecem '
              'no formulário de cadastro — só a ordem/presença deles no nome gerado.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
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
              height: 340,
              child: ReorderableListView(
                onReorder: (oldIndex, newIndex) {
                  setState(() {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final campo = _ordem.removeAt(oldIndex);
                    _ordem.insert(newIndex, campo);
                  });
                  _atualizarPreview();
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
                                _atualizarPreview();
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
