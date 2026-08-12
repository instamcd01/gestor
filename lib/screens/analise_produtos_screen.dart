import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/produto.dart';
import '../models/sugestao_variante.dart';
import '../providers/produto_provider.dart';
import '../utils/busca_utils.dart';
import '../utils/produto_validators.dart';
import '../widgets/dialogo_revisao_variante.dart';
import 'adicionar_imagens_lote_screen.dart';
import 'sugestoes_variante_rejeitadas_screen.dart';

/// Tela única de análise/ajuste de produtos em massa — reúne os filtros que
/// antes viviam espalhados em produtos_screen.dart (sugestão de variante,
/// revisar preço) mais dois novos (sem imagem, ciclo de recompra), cada um
/// numa aba com seleção múltipla e ação em massa. Objetivo: o usuário
/// resolve "N produtos precisam disso" de uma vez, em vez de abrir produto
/// por produto.
class AnaliseProdutosScreen extends StatefulWidget {
  const AnaliseProdutosScreen({super.key});

  @override
  State<AnaliseProdutosScreen> createState() => _AnaliseProdutosScreenState();
}

class _AnaliseProdutosScreenState extends State<AnaliseProdutosScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final produtoProvider = context.watch<ProdutoProvider>();
    final semImagem = produtoProvider.produtos.where((p) => p.imagemUrl.isEmpty).length;
    final comSugestao = produtoProvider.totalProdutosComSugestaoVariante;
    final revisarPreco = produtoProvider.produtos.where((p) => p.revisarPreco).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Análise de produtos'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(text: 'Sem imagem ($semImagem)'),
            Tab(text: 'Variantes ($comSugestao)'),
            Tab(text: 'Revisar preço ($revisarPreco)'),
            const Tab(text: 'Ciclo de recompra'),
            const Tab(text: 'Catálogo'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _AbaSemImagem(),
          _AbaVariantes(),
          _AbaRevisarPreco(),
          _AbaCicloRecompra(),
          _AbaCatalogo(),
        ],
      ),
    );
  }
}

/// Barra fixa no rodapé com o resumo da seleção + botões de ação — mesmo
/// padrão usado em rotas_entrega_screen.dart/sugestao_compra_screen.dart
/// pra seleção em massa.
class _BarraSelecao extends StatelessWidget {
  final int quantidade;
  final List<Widget> acoes;

  const _BarraSelecao({required this.quantidade, required this.acoes});

  @override
  Widget build(BuildContext context) {
    if (quantidade == 0) return const SizedBox.shrink();
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, -2))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('$quantidade selecionado(s)', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: acoes),
          ],
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------
/// Aba 1: Sem imagem
/// ---------------------------------------------------------------------
class _AbaSemImagem extends StatefulWidget {
  const _AbaSemImagem();

  @override
  State<_AbaSemImagem> createState() => _AbaSemImagemState();
}

class _AbaSemImagemState extends State<_AbaSemImagem> {
  final Set<String> _selecionados = {};
  String _busca = '';

  @override
  Widget build(BuildContext context) {
    final produtoProvider = context.watch<ProdutoProvider>();
    final lista = produtoProvider.produtos
        .where((p) => p.imagemUrl.isEmpty)
        .where((p) => contemTodasPalavras(p.nome, _busca))
        .toList();
    final idsValidos = lista.map((p) => p.id).whereType<String>().toSet();
    _selecionados.removeWhere((id) => !idsValidos.contains(id));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            decoration: const InputDecoration(hintText: 'Buscar por nome', prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => _busca = v),
          ),
        ),
        if (lista.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => setState(() => _selecionados.addAll(idsValidos)),
                  child: const Text('Selecionar todos'),
                ),
                if (_selecionados.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(_selecionados.clear),
                    child: const Text('Limpar seleção'),
                  ),
              ],
            ),
          ),
        Expanded(
          child: lista.isEmpty
              ? const Center(child: Text('Nenhum produto sem imagem 🎉'))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: lista.length,
                  itemBuilder: (context, index) {
                    final produto = lista[index];
                    final id = produto.id!;
                    return CheckboxListTile(
                      value: _selecionados.contains(id),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selecionados.add(id);
                        } else {
                          _selecionados.remove(id);
                        }
                      }),
                      title: Text(produto.nome, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(produto.categoria.isNotEmpty ? produto.categoria : 'Sem categoria'),
                    );
                  },
                ),
        ),
        _BarraSelecao(
          quantidade: _selecionados.length,
          acoes: [
            FilledButton.icon(
              icon: const Icon(Icons.add_photo_alternate_outlined),
              label: const Text('Adicionar fotos'),
              onPressed: () async {
                final selecionados = lista.where((p) => _selecionados.contains(p.id)).toList();
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AdicionarImagensLoteScreen(produtosPendentes: selecionados),
                ));
                if (mounted) setState(_selecionados.clear);
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// ---------------------------------------------------------------------
/// Aba 2: Sugestões de variante
/// ---------------------------------------------------------------------
class _AbaVariantes extends StatefulWidget {
  const _AbaVariantes();

  @override
  State<_AbaVariantes> createState() => _AbaVariantesState();
}

class _AbaVariantesState extends State<_AbaVariantes> {
  final Set<String> _selecionados = {};
  bool _processando = false;

  Future<void> _aprovarSelecionadas(List<Produto> produtos, ProdutoProvider provider) async {
    final sugestoes = <SugestaoVariante>[];
    for (final produto in produtos.where((p) => _selecionados.contains(p.id))) {
      sugestoes.addAll(provider.sugestoesVariantePara(produto.id!));
    }
    final elegiveis = sugestoes.where((s) => s.origem == 'estruturado').length;
    if (elegiveis == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Nenhuma sugestão selecionada é de alta confiança — revise individualmente.'),
      ));
      return;
    }
    setState(() => _processando = true);
    final falhas = await provider.aprovarSugestoesEstruturadasEmMassa(sugestoes);
    if (!mounted) return;
    setState(() {
      _processando = false;
      _selecionados.clear();
    });
    final puladas = sugestoes.length - elegiveis;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        'Aprovadas ${elegiveis - falhas.length} de $elegiveis'
        '${puladas > 0 ? ' ($puladas heurística(s) pulada(s) — precisam de revisão individual)' : ''}'
        '${falhas.isNotEmpty ? ' — ${falhas.length} falhou/falharam' : ''}',
      ),
    ));
  }

  Future<void> _rejeitarSelecionadas(List<Produto> produtos, ProdutoProvider provider) async {
    final ids = <String>[];
    for (final produto in produtos.where((p) => _selecionados.contains(p.id))) {
      ids.addAll(provider.sugestoesVariantePara(produto.id!).map((s) => s.id));
    }
    if (ids.isEmpty) return;
    setState(() => _processando = true);
    await provider.rejeitarSugestoesEmMassa(ids);
    if (!mounted) return;
    setState(() {
      _processando = false;
      _selecionados.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final produtoProvider = context.watch<ProdutoProvider>();
    final lista = produtoProvider.produtos
        .where((p) => p.id != null && produtoProvider.sugestoesVariantePara(p.id!).isNotEmpty)
        .toList();
    final idsValidos = lista.map((p) => p.id).whereType<String>().toSet();
    _selecionados.removeWhere((id) => !idsValidos.contains(id));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.unpublished_outlined, size: 18),
              label: const Text('Ver sugestões rejeitadas'),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const SugestoesVarianteRejeitadasScreen(),
              )),
            ),
          ),
        ),
        Expanded(
          child: lista.isEmpty
              ? const Center(child: Text('Nenhuma sugestão de variante pendente'))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: lista.length,
                  itemBuilder: (context, index) {
                    final produto = lista[index];
                    final id = produto.id!;
                    final sugestoes = produtoProvider.sugestoesVariantePara(id);
                    final todasEstruturadas = sugestoes.every((s) => s.origem == 'estruturado');
                    return CheckboxListTile(
                      value: _selecionados.contains(id),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selecionados.add(id);
                        } else {
                          _selecionados.remove(id);
                        }
                      }),
                      title: Text(produto.nome, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        sugestoes.length > 1
                            ? '${sugestoes.length} sugestões — ${todasEstruturadas ? "alta confiança" : "inclui semelhança de nome, confira"}'
                            : todasEstruturadas
                                ? 'Eixo ${sugestoes.first.tipoVariacao} — alta confiança'
                                : 'Eixo ${sugestoes.first.tipoVariacao} — semelhança de nome, confira',
                        style: TextStyle(color: todasEstruturadas ? null : Theme.of(context).colorScheme.error),
                      ),
                      secondary: IconButton(
                        tooltip: 'Revisar individualmente',
                        icon: const Icon(Icons.rate_review_outlined),
                        onPressed: () => showDialog<void>(
                          context: context,
                          builder: (ctx) => DialogoRevisaoVariante(produto: produto, sugestoes: sugestoes),
                        ),
                      ),
                    );
                  },
                ),
        ),
        _BarraSelecao(
          quantidade: _selecionados.length,
          acoes: [
            OutlinedButton.icon(
              icon: const Icon(Icons.close),
              label: const Text('Rejeitar'),
              onPressed: _processando ? null : () => _rejeitarSelecionadas(lista, produtoProvider),
            ),
            FilledButton.icon(
              icon: _processando
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check),
              label: const Text('Aprovar (alta confiança)'),
              onPressed: _processando ? null : () => _aprovarSelecionadas(lista, produtoProvider),
            ),
          ],
        ),
      ],
    );
  }
}

/// ---------------------------------------------------------------------
/// Aba 3: Revisar preço
/// ---------------------------------------------------------------------
class _AbaRevisarPreco extends StatefulWidget {
  const _AbaRevisarPreco();

  @override
  State<_AbaRevisarPreco> createState() => _AbaRevisarPrecoState();
}

class _AbaRevisarPrecoState extends State<_AbaRevisarPreco> {
  final Set<String> _selecionados = {};
  final _markupController = TextEditingController();
  bool _processando = false;

  @override
  void dispose() {
    _markupController.dispose();
    super.dispose();
  }

  Future<void> _marcarComoRevisado(ProdutoProvider provider) async {
    setState(() => _processando = true);
    await provider.marcarPrecoRevisadoEmMassa(_selecionados.toList());
    if (!mounted) return;
    setState(() {
      _processando = false;
      _selecionados.clear();
    });
  }

  Future<void> _aplicarMarkup(List<Produto> lista, ProdutoProvider provider) async {
    final markup = ProdutoValidators.parseNumero(_markupController.text);
    if (markup == null || markup >= 100) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Informe um markup válido (menor que 100%).')));
      return;
    }
    final precoPorId = <String, double>{};
    for (final produto in lista.where((p) => _selecionados.contains(p.id))) {
      final novoPreco = produto.custo / (1 - markup / 100);
      if (novoPreco > 0) precoPorId[produto.id!] = novoPreco;
    }
    if (precoPorId.isEmpty) return;
    setState(() => _processando = true);
    final falhas = await provider.aplicarPrecoRevisadoEmMassa(precoPorId);
    if (!mounted) return;
    setState(() {
      _processando = false;
      _selecionados.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Preço aplicado em ${precoPorId.length - falhas.length} de ${precoPorId.length} produtos'
          '${falhas.isNotEmpty ? ' (${falhas.length} falharam)' : ''}.'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final produtoProvider = context.watch<ProdutoProvider>();
    final lista = produtoProvider.produtos.where((p) => p.revisarPreco).toList();
    final idsValidos = lista.map((p) => p.id).whereType<String>().toSet();
    _selecionados.removeWhere((id) => !idsValidos.contains(id));

    return Column(
      children: [
        if (lista.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => setState(() => _selecionados.addAll(idsValidos)),
                  child: const Text('Selecionar todos'),
                ),
                if (_selecionados.isNotEmpty)
                  TextButton(onPressed: () => setState(_selecionados.clear), child: const Text('Limpar seleção')),
              ],
            ),
          ),
        Expanded(
          child: lista.isEmpty
              ? const Center(child: Text('Nenhum produto pendente de revisão de preço'))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 160),
                  itemCount: lista.length,
                  itemBuilder: (context, index) {
                    final produto = lista[index];
                    final id = produto.id!;
                    return CheckboxListTile(
                      value: _selecionados.contains(id),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selecionados.add(id);
                        } else {
                          _selecionados.remove(id);
                        }
                      }),
                      title: Text(produto.nome, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        'Custo: R\$ ${produto.custo.toStringAsFixed(2)} • Preço atual: R\$ ${produto.preco.toStringAsFixed(2)}',
                      ),
                    );
                  },
                ),
        ),
        if (_selecionados.isNotEmpty)
          SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, -2))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${_selecionados.length} selecionado(s)', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Manter preço atual (marcar como revisado)'),
                    onPressed: _processando ? null : () => _marcarComoRevisado(produtoProvider),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _markupController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(labelText: 'Markup (%) sobre o custo'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _processando ? null : () => _aplicarMarkup(lista, produtoProvider),
                        child: _processando
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Aplicar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// ---------------------------------------------------------------------
/// Aba 4: Ciclo de recompra
/// ---------------------------------------------------------------------
class _AbaCicloRecompra extends StatefulWidget {
  const _AbaCicloRecompra();

  @override
  State<_AbaCicloRecompra> createState() => _AbaCicloRecompraState();
}

class _AbaCicloRecompraState extends State<_AbaCicloRecompra> {
  final Set<String> _selecionados = {};
  final _diasController = TextEditingController();
  String _busca = '';
  bool _processando = false;

  @override
  void dispose() {
    _diasController.dispose();
    super.dispose();
  }

  Future<void> _aplicar(ProdutoProvider provider) async {
    final dias = int.tryParse(_diasController.text.trim());
    if (dias == null || dias <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Informe um número de dias válido.')));
      return;
    }
    setState(() => _processando = true);
    await provider.atualizarCicloRecompraEmMassa(_selecionados.toList(), dias);
    if (!mounted) return;
    setState(() {
      _processando = false;
      _selecionados.clear();
    });
  }

  Future<void> _limpar(ProdutoProvider provider) async {
    setState(() => _processando = true);
    await provider.atualizarCicloRecompraEmMassa(_selecionados.toList(), null);
    if (!mounted) return;
    setState(() {
      _processando = false;
      _selecionados.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final produtoProvider = context.watch<ProdutoProvider>();
    final lista = produtoProvider.produtos.where((p) => contemTodasPalavras(p.nome, _busca)).toList();
    final idsValidos = lista.map((p) => p.id).whereType<String>().toSet();
    _selecionados.removeWhere((id) => !idsValidos.contains(id));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: const InputDecoration(hintText: 'Buscar por nome', prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => _busca = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              TextButton(
                onPressed: () => setState(() => _selecionados.addAll(idsValidos)),
                child: const Text('Selecionar todos'),
              ),
              if (_selecionados.isNotEmpty)
                TextButton(onPressed: () => setState(_selecionados.clear), child: const Text('Limpar seleção')),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 160),
            itemCount: lista.length,
            itemBuilder: (context, index) {
              final produto = lista[index];
              final id = produto.id!;
              return CheckboxListTile(
                value: _selecionados.contains(id),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selecionados.add(id);
                  } else {
                    _selecionados.remove(id);
                  }
                }),
                title: Text(produto.nome, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  produto.cicloRecompraDias != null
                      ? 'Ciclo: ${produto.cicloRecompraDias} dias'
                      : 'Sem ciclo próprio (usa o padrão da loja, se houver)',
                ),
              );
            },
          ),
        ),
        if (_selecionados.isNotEmpty)
          SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, -2))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${_selecionados.length} selecionado(s)', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _diasController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Ciclo (dias)'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: _processando ? null : () => _aplicar(produtoProvider),
                        child: const Text('Aplicar'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: _processando ? null : () => _limpar(produtoProvider),
                    child: const Text('Limpar ciclo (usar padrão da loja)'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// ---------------------------------------------------------------------
/// Aba 5: Catálogo (categoria, fabricante, visibilidade, destaque, estoque
/// mínimo em massa) — reúne outras configurações de produto que fazem
/// sentido aplicar em lote, sugeridas depois que as 4 abas acima já
/// existiam. Diferente das outras, opera sobre o catálogo inteiro (não um
/// subconjunto "pendente de algo"), por isso tem busca em vez de já vir
/// filtrada.
/// ---------------------------------------------------------------------
class _AbaCatalogo extends StatefulWidget {
  const _AbaCatalogo();

  @override
  State<_AbaCatalogo> createState() => _AbaCatalogoState();
}

class _AbaCatalogoState extends State<_AbaCatalogo> {
  final Set<String> _selecionados = {};
  String _busca = '';
  bool _processando = false;
  List<String>? _categorias;
  List<String>? _fabricantes;

  @override
  void initState() {
    super.initState();
    final provider = context.read<ProdutoProvider>();
    provider.listarCategoriasDisponiveis().then((v) {
      if (mounted) setState(() => _categorias = v);
    });
    provider.listarFabricantesDisponiveis().then((v) {
      if (mounted) setState(() => _fabricantes = v);
    });
  }

  Future<void> _aplicarBool(Future<void> Function(List<String>, bool) acao, bool valor) async {
    setState(() => _processando = true);
    await acao(_selecionados.toList(), valor);
    if (!mounted) return;
    setState(() {
      _processando = false;
      _selecionados.clear();
    });
  }

  Future<void> _dialogCategoria(ProdutoProvider provider) async {
    String? categoriaEscolhida;
    final subcategoriaController = TextEditingController();
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Definir categoria'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                value: categoriaEscolhida,
                decoration: const InputDecoration(labelText: 'Categoria'),
                items: (_categorias ?? []).map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setStateDialog(() => categoriaEscolhida = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: subcategoriaController,
                decoration: const InputDecoration(labelText: 'Subcategoria (opcional)'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: categoriaEscolhida == null ? null : () => Navigator.pop(ctx, true),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
    if (confirmou != true || categoriaEscolhida == null) return;
    setState(() => _processando = true);
    final subcategoria = subcategoriaController.text.trim();
    await provider.atualizarCategoriaEmMassa(
      _selecionados.toList(),
      categoriaEscolhida!,
      subcategoria.isEmpty ? null : subcategoria,
    );
    if (!mounted) return;
    setState(() {
      _processando = false;
      _selecionados.clear();
    });
  }

  Future<void> _dialogFabricante(ProdutoProvider provider) async {
    String? fabricanteEscolhido;
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Definir fabricante'),
          content: DropdownButtonFormField<String>(
            value: fabricanteEscolhido,
            decoration: const InputDecoration(labelText: 'Fabricante'),
            items: (_fabricantes ?? []).map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
            onChanged: (v) => setStateDialog(() => fabricanteEscolhido = v),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: fabricanteEscolhido == null ? null : () => Navigator.pop(ctx, true),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      ),
    );
    if (confirmou != true || fabricanteEscolhido == null) return;
    setState(() => _processando = true);
    await provider.atualizarFabricanteEmMassa(_selecionados.toList(), fabricanteEscolhido!);
    if (!mounted) return;
    setState(() {
      _processando = false;
      _selecionados.clear();
    });
  }

  Future<void> _dialogEstoqueMinimo(ProdutoProvider provider) async {
    final controller = TextEditingController();
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Estoque mínimo'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Quantidade mínima'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aplicar')),
        ],
      ),
    );
    if (confirmou != true) return;
    final minimo = int.tryParse(controller.text.trim());
    if (minimo == null || minimo < 0) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Informe um número válido.')));
      }
      return;
    }
    setState(() => _processando = true);
    await provider.atualizarEstoqueMinimoEmMassa(_selecionados.toList(), minimo);
    if (!mounted) return;
    setState(() {
      _processando = false;
      _selecionados.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final produtoProvider = context.watch<ProdutoProvider>();
    final lista = produtoProvider.produtos.where((p) => contemTodasPalavras(p.nome, _busca)).toList();
    final idsValidos = lista.map((p) => p.id).whereType<String>().toSet();
    _selecionados.removeWhere((id) => !idsValidos.contains(id));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: const InputDecoration(hintText: 'Buscar por nome', prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => _busca = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              TextButton(
                onPressed: () => setState(() => _selecionados.addAll(idsValidos)),
                child: const Text('Selecionar todos'),
              ),
              if (_selecionados.isNotEmpty)
                TextButton(onPressed: () => setState(_selecionados.clear), child: const Text('Limpar seleção')),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: lista.length,
            itemBuilder: (context, index) {
              final produto = lista[index];
              final id = produto.id!;
              final detalhes = [
                produto.categoria.isNotEmpty ? produto.categoria : 'Sem categoria',
                if (produto.fabricante != null && produto.fabricante!.isNotEmpty) produto.fabricante!,
                if (!produto.exibirNoCatalogo) 'oculto do catálogo',
                if (!produto.ativo) 'inativo',
                if (produto.destacar) 'destaque',
              ].join(' • ');
              return CheckboxListTile(
                value: _selecionados.contains(id),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    _selecionados.add(id);
                  } else {
                    _selecionados.remove(id);
                  }
                }),
                title: Text(produto.nome, maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(detalhes),
              );
            },
          ),
        ),
        if (_selecionados.isNotEmpty)
          SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, -2))],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${_selecionados.length} selecionado(s)', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.category_outlined, size: 18),
                        label: const Text('Categoria'),
                        onPressed: _processando ? null : () => _dialogCategoria(produtoProvider),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.factory_outlined, size: 18),
                        label: const Text('Fabricante'),
                        onPressed: _processando ? null : () => _dialogFabricante(produtoProvider),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.visibility_outlined, size: 18),
                        label: const Text('Exibir no catálogo'),
                        onPressed: _processando
                            ? null
                            : () => _aplicarBool(produtoProvider.atualizarExibirCatalogoEmMassa, true),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.visibility_off_outlined, size: 18),
                        label: const Text('Ocultar do catálogo'),
                        onPressed: _processando
                            ? null
                            : () => _aplicarBool(produtoProvider.atualizarExibirCatalogoEmMassa, false),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text('Ativar'),
                        onPressed:
                            _processando ? null : () => _aplicarBool(produtoProvider.atualizarAtivoEmMassa, true),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.block_outlined, size: 18),
                        label: const Text('Desativar'),
                        onPressed:
                            _processando ? null : () => _aplicarBool(produtoProvider.atualizarAtivoEmMassa, false),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.star_outline, size: 18),
                        label: const Text('Destacar'),
                        onPressed: _processando
                            ? null
                            : () => _aplicarBool(produtoProvider.atualizarDestaqueEmMassa, true),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.star_border, size: 18),
                        label: const Text('Remover destaque'),
                        onPressed: _processando
                            ? null
                            : () => _aplicarBool(produtoProvider.atualizarDestaqueEmMassa, false),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.inventory_2_outlined, size: 18),
                        label: const Text('Estoque mínimo'),
                        onPressed: _processando ? null : () => _dialogEstoqueMinimo(produtoProvider),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
