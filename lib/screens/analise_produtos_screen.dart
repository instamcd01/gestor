import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/produto.dart';
import '../models/sugestao_variante.dart';
import '../providers/auth_provider.dart';
import '../providers/produto_provider.dart';
import '../utils/busca_utils.dart';
import '../utils/produto_validators.dart';
import '../utils/variante_label_utils.dart';
import '../widgets/dialogo_revisao_variante.dart';
import 'adicionar_imagens_lote_screen.dart';
import 'editar_produto_screen.dart';
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
    _tabController = TabController(length: 7, vsync: this);
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
    final eanDuplicado = _gruposEanDuplicado(produtoProvider.produtos).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Análise de produtos'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            icon: produtoProvider.carregando
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: produtoProvider.carregando ? null : () => produtoProvider.carregarProdutos(),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [
            Tab(text: 'Sem imagem ($semImagem)'),
            Tab(text: 'Variantes ($comSugestao)'),
            Tab(text: 'Revisar preço ($revisarPreco)'),
            const Tab(text: 'Ciclo de recompra'),
            const Tab(text: 'Catálogo'),
            Tab(text: 'EAN duplicado ($eanDuplicado)'),
            const Tab(text: 'Estratégia'),
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
          _AbaEanDuplicado(),
          _AbaEstrategia(),
        ],
      ),
    );
  }
}

/// Agrupa produtos pelo mesmo código de barras — ignora vazio e "0" (usado
/// como placeholder de "sem EAN real", ex. taxas de entrega cadastradas
/// como produto; achado real em 07/09 comparando a exportação do catálogo
/// iFood com o histórico de uploads: várias dezenas de produtos sem EAN
/// verdadeiro colidiam ali, mas isso é um problema à parte de duplicata de
/// cadastro de verdade, que é o que esta aba mostra). Só grupos com 2+
/// produtos voltam — o mesmo EAN em produtos diferentes nunca deveria
/// acontecer (o iFood, por exemplo, só consegue representar um deles).
List<List<Produto>> _gruposEanDuplicado(List<Produto> produtos) {
  final porEan = <String, List<Produto>>{};
  for (final produto in produtos) {
    final ean = produto.codigoBarras.trim();
    if (ean.isEmpty || ean == '0') continue;
    (porEan[ean] ??= []).add(produto);
  }
  return porEan.values.where((grupo) => grupo.length > 1).toList()
    ..sort((a, b) => a.first.nome.compareTo(b.first.nome));
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
  // Ordem em que o usuário marcou cada checkbox — um Set não preserva isso
  // de forma confiável na hora de montar a lista pra AdicionarImagensLoteScreen
  // (que vincula a N-ésima foto escolhida ao N-ésimo produto da fila), então
  // a fila tem que seguir esta lista, não a ordem de `lista` (que é a ordem
  // do catálogo, não a ordem de seleção).
  final List<String> _ordemSelecao = [];
  String _busca = '';
  bool? _filtroExibido;
  bool? _filtroComEstoque;

  void _alternar(String id, bool selecionado) {
    setState(() {
      if (selecionado) {
        if (_selecionados.add(id)) _ordemSelecao.add(id);
      } else {
        _selecionados.remove(id);
        _ordemSelecao.remove(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final produtoProvider = context.watch<ProdutoProvider>();
    final lista = produtoProvider.produtos
        .where((p) => p.imagemUrl.isEmpty)
        .where((p) => contemTodasPalavras(p.nome, _busca))
        .where((p) => _filtroExibido == null || p.exibirNoCatalogo == _filtroExibido)
        .where((p) => _filtroComEstoque == null || (p.estoqueAtual > 0) == _filtroComEstoque)
        .toList();
    final idsValidos = lista.map((p) => p.id).whereType<String>().toSet();
    _selecionados.removeWhere((id) => !idsValidos.contains(id));
    _ordemSelecao.removeWhere((id) => !_selecionados.contains(id));

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            decoration: const InputDecoration(hintText: 'Buscar por nome', prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => _busca = v),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _FiltroTriEstado(
                label: 'Site',
                valor: _filtroExibido,
                rotuloVerdadeiro: 'Exibidos',
                rotuloFalso: 'Ocultos',
                onChanged: (v) => setState(() => _filtroExibido = v),
              ),
              _FiltroTriEstado(
                label: 'Estoque',
                valor: _filtroComEstoque,
                rotuloVerdadeiro: 'Com estoque',
                rotuloFalso: 'Sem estoque',
                onChanged: (v) => setState(() => _filtroComEstoque = v),
              ),
            ],
          ),
        ),
        if (lista.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    for (final id in idsValidos) {
                      if (_selecionados.add(id)) _ordemSelecao.add(id);
                    }
                  }),
                  child: const Text('Selecionar todos'),
                ),
                if (_selecionados.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() {
                      _selecionados.clear();
                      _ordemSelecao.clear();
                    }),
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
                    final comEstoque = produto.estoqueAtual > 0;
                    final detalhes = [
                      produto.categoria.isNotEmpty ? produto.categoria : 'Sem categoria',
                      produto.exibirNoCatalogo ? 'Exibido no site' : 'Oculto no site',
                      comEstoque ? 'Estoque: ${produto.estoqueAtual}' : 'Sem estoque',
                    ].join(' • ');
                    return CheckboxListTile(
                      value: _selecionados.contains(id),
                      onChanged: (v) => _alternar(id, v == true),
                      title: Text(produto.nome, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        detalhes,
                        style: !produto.exibirNoCatalogo || !comEstoque
                            ? TextStyle(color: Theme.of(context).colorScheme.error)
                            : null,
                      ),
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
                final porId = {for (final p in lista) p.id: p};
                final selecionados = _ordemSelecao.map((id) => porId[id]).whereType<Produto>().toList();
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => AdicionarImagensLoteScreen(produtosPendentes: selecionados),
                ));
                if (mounted) {
                  setState(() {
                    _selecionados.clear();
                    _ordemSelecao.clear();
                  });
                }
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// Filtro de três estados (todos / sim / não) como um par de chips — usado
/// pelos filtros "Site" e "Estoque" da aba "Sem imagem", pra dar pra saber
/// (antes de sair caçando fotos) se o produto sem imagem sequer aparece no
/// site ou tem estoque — sem isso o único jeito de saber era abrir cada
/// produto individualmente.
class _FiltroTriEstado extends StatelessWidget {
  const _FiltroTriEstado({
    required this.label,
    required this.valor,
    required this.rotuloVerdadeiro,
    required this.rotuloFalso,
    required this.onChanged,
  });

  final String label;
  final bool? valor;
  final String rotuloVerdadeiro;
  final String rotuloFalso;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<bool?>(
      initialValue: valor,
      onSelected: onChanged,
      itemBuilder: (context) => [
        const PopupMenuItem(value: null, child: Text('Todos')),
        PopupMenuItem(value: true, child: Text(rotuloVerdadeiro)),
        PopupMenuItem(value: false, child: Text(rotuloFalso)),
      ],
      child: Chip(
        label: Text(
          valor == null ? '$label: todos' : '$label: ${valor! ? rotuloVerdadeiro : rotuloFalso}',
        ),
        avatar: const Icon(Icons.filter_list, size: 16),
      ),
    );
  }
}

/// Filtro por eixo de variação (peso/dose/sabor...) da aba "Variantes" —
/// mostra só os eixos que de fato têm sugestão pendente no momento, com a
/// contagem de produtos de cada um, pra dar pra focar (ex: "só sabor")
/// quando há eixos que o usuário não quer revisar agora.
class _FiltroTipoVariante extends StatelessWidget {
  const _FiltroTipoVariante({
    required this.valor,
    required this.contagemPorTipo,
    required this.onChanged,
  });

  final String? valor;
  final Map<String, int> contagemPorTipo;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final tipos = contagemPorTipo.keys.toList()..sort();
    return PopupMenuButton<String?>(
      initialValue: valor,
      onSelected: onChanged,
      itemBuilder: (context) => [
        PopupMenuItem(value: null, child: const Text('Todos os eixos')),
        for (final tipo in tipos)
          PopupMenuItem(value: tipo, child: Text('${rotuloTipoVariacao(tipo)} (${contagemPorTipo[tipo]})')),
      ],
      child: Chip(
        label: Text(valor == null ? 'Eixo: todos' : 'Eixo: ${rotuloTipoVariacao(valor!)}'),
        avatar: const Icon(Icons.filter_list, size: 16),
      ),
    );
  }
}

/// Filtro genérico por um valor de texto (categoria, subcategoria,
/// fabricante...) com a contagem de produtos de cada valor — mesmo padrão
/// visual de _FiltroTipoVariante, mas sem a tradução de rótulo específica
/// de variante, pra reusar nas abas que não tinham filtro nenhum (Revisar
/// preço, Ciclo de recompra, Catálogo) e o usuário via ficando difícil achar
/// os produtos certos numa lista longa sem poder restringir por categoria.
class _FiltroPorValor extends StatelessWidget {
  const _FiltroPorValor({
    required this.label,
    required this.valor,
    required this.contagemPorValor,
    required this.onChanged,
  });

  final String label;
  final String? valor;
  final Map<String, int> contagemPorValor;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final valores = contagemPorValor.keys.toList()..sort();
    return PopupMenuButton<String?>(
      initialValue: valor,
      onSelected: onChanged,
      itemBuilder: (context) => [
        const PopupMenuItem(value: null, child: Text('Todas')),
        for (final v in valores) PopupMenuItem(value: v, child: Text('$v (${contagemPorValor[v]})')),
      ],
      child: Chip(
        label: Text(valor == null ? '$label: todas' : '$label: $valor'),
        avatar: const Icon(Icons.filter_list, size: 16),
      ),
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
  String _busca = '';
  String? _filtroTipo;

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
    final contagemPorTipo = produtoProvider.contagemSugestoesPorTipo;
    final lista = produtoProvider.produtos
        .where((p) => p.id != null && produtoProvider.sugestoesVariantePara(p.id!).isNotEmpty)
        .where((p) => contemTodasPalavras(p.nome, _busca))
        .where((p) =>
            _filtroTipo == null ||
            produtoProvider.sugestoesVariantePara(p.id!).any((s) => s.tipoVariacao == _filtroTipo))
        .toList();
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
        if (contagemPorTipo.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _FiltroTipoVariante(
                valor: _filtroTipo,
                contagemPorTipo: contagemPorTipo,
                onChanged: (v) => setState(() => _filtroTipo = v),
              ),
            ),
          ),
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
  String _busca = '';
  String? _filtroCategoria;

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
    final pendentes = produtoProvider.produtos.where((p) => p.revisarPreco).toList();
    final contagemPorCategoria = <String, int>{};
    for (final p in pendentes) {
      final cat = p.categoria.isNotEmpty ? p.categoria : 'Sem categoria';
      contagemPorCategoria[cat] = (contagemPorCategoria[cat] ?? 0) + 1;
    }
    final lista = pendentes
        .where((p) => contemTodasPalavras(p.nome, _busca))
        .where((p) => _filtroCategoria == null ||
            (p.categoria.isNotEmpty ? p.categoria : 'Sem categoria') == _filtroCategoria)
        .toList();
    final idsValidos = lista.map((p) => p.id).whereType<String>().toSet();
    _selecionados.removeWhere((id) => !idsValidos.contains(id));

    return Column(
      children: [
        if (pendentes.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              decoration: const InputDecoration(hintText: 'Buscar por nome', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => _busca = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: _FiltroPorValor(
              label: 'Categoria',
              valor: _filtroCategoria,
              contagemPorValor: contagemPorCategoria,
              onChanged: (v) => setState(() => _filtroCategoria = v),
            ),
          ),
        ],
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
              ? Center(
                  child: Text(pendentes.isEmpty
                      ? 'Nenhum produto pendente de revisão de preço'
                      : 'Nenhum produto encontrado com esse filtro'))
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
  String? _filtroCategoria;
  bool? _filtroComCiclo;

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
    final contagemPorCategoria = <String, int>{};
    for (final p in produtoProvider.produtos) {
      final cat = p.categoria.isNotEmpty ? p.categoria : 'Sem categoria';
      contagemPorCategoria[cat] = (contagemPorCategoria[cat] ?? 0) + 1;
    }
    final lista = produtoProvider.produtos
        .where((p) => contemTodasPalavras(p.nome, _busca))
        .where((p) => _filtroCategoria == null ||
            (p.categoria.isNotEmpty ? p.categoria : 'Sem categoria') == _filtroCategoria)
        .where((p) => _filtroComCiclo == null || (p.cicloRecompraDias != null) == _filtroComCiclo)
        .toList();
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
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _FiltroPorValor(
                label: 'Categoria',
                valor: _filtroCategoria,
                contagemPorValor: contagemPorCategoria,
                onChanged: (v) => setState(() => _filtroCategoria = v),
              ),
              _FiltroTriEstado(
                label: 'Ciclo',
                valor: _filtroComCiclo,
                rotuloVerdadeiro: 'Com ciclo próprio',
                rotuloFalso: 'Sem ciclo (usa padrão)',
                onChanged: (v) => setState(() => _filtroComCiclo = v),
              ),
            ],
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
          child: lista.isEmpty
              ? const Center(child: Text('Nenhum produto encontrado com esse filtro'))
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
  String? _filtroCategoria;
  String? _filtroSubcategoria;
  bool? _filtroExibido;
  bool? _filtroAtivo;

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

    final contagemPorCategoria = <String, int>{};
    for (final p in produtoProvider.produtos) {
      final cat = p.categoria.isNotEmpty ? p.categoria : 'Sem categoria';
      contagemPorCategoria[cat] = (contagemPorCategoria[cat] ?? 0) + 1;
    }

    // Subcategorias só da categoria escolhida (ou de todo o catálogo, se
    // nenhuma categoria estiver selecionada ainda) — evita listar "Adultos"
    // de Ração junto com "Adultos" de Sachê como se fosse uma coisa só.
    final baseParaSubcategoria = _filtroCategoria == null
        ? produtoProvider.produtos
        : produtoProvider.produtos
            .where((p) => (p.categoria.isNotEmpty ? p.categoria : 'Sem categoria') == _filtroCategoria);
    final contagemPorSubcategoria = <String, int>{};
    for (final p in baseParaSubcategoria) {
      final sub = p.subcategoria;
      if (sub == null || sub.isEmpty) continue;
      contagemPorSubcategoria[sub] = (contagemPorSubcategoria[sub] ?? 0) + 1;
    }
    if (_filtroSubcategoria != null && !contagemPorSubcategoria.containsKey(_filtroSubcategoria)) {
      _filtroSubcategoria = null;
    }

    final lista = produtoProvider.produtos
        .where((p) => contemTodasPalavras(p.nome, _busca))
        .where((p) => _filtroCategoria == null ||
            (p.categoria.isNotEmpty ? p.categoria : 'Sem categoria') == _filtroCategoria)
        .where((p) => _filtroSubcategoria == null || p.subcategoria == _filtroSubcategoria)
        .where((p) => _filtroExibido == null || p.exibirNoCatalogo == _filtroExibido)
        .where((p) => _filtroAtivo == null || p.ativo == _filtroAtivo)
        .toList();
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
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              _FiltroPorValor(
                label: 'Categoria',
                valor: _filtroCategoria,
                contagemPorValor: contagemPorCategoria,
                onChanged: (v) => setState(() {
                  _filtroCategoria = v;
                  _filtroSubcategoria = null;
                }),
              ),
              _FiltroPorValor(
                label: 'Subcategoria',
                valor: _filtroSubcategoria,
                contagemPorValor: contagemPorSubcategoria,
                onChanged: (v) => setState(() => _filtroSubcategoria = v),
              ),
              _FiltroTriEstado(
                label: 'Site',
                valor: _filtroExibido,
                rotuloVerdadeiro: 'Exibidos',
                rotuloFalso: 'Ocultos',
                onChanged: (v) => setState(() => _filtroExibido = v),
              ),
              _FiltroTriEstado(
                label: 'Status',
                valor: _filtroAtivo,
                rotuloVerdadeiro: 'Ativos',
                rotuloFalso: 'Inativos',
                onChanged: (v) => setState(() => _filtroAtivo = v),
              ),
            ],
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
          child: lista.isEmpty
              ? const Center(child: Text('Nenhum produto encontrado com esse filtro'))
              : ListView.builder(
            padding: const EdgeInsets.only(bottom: 8),
            itemCount: lista.length,
            itemBuilder: (context, index) {
              final produto = lista[index];
              final id = produto.id!;
              final detalhes = [
                produto.categoria.isNotEmpty ? produto.categoria : 'Sem categoria',
                if (produto.subcategoria != null && produto.subcategoria!.isNotEmpty)
                  'sub: ${produto.subcategoria}',
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

/// ---------------------------------------------------------------------
/// Aba 6: EAN duplicado — produtos diferentes com o mesmo código de barras.
/// Achado real comparando a exportação do catálogo iFood com o histórico
/// de uploads (07/09): nunca deveria acontecer, plataformas indexadas por
/// EAN (iFood, 99Food...) só conseguem representar um dos produtos, o
/// outro fica invisível sem erro nenhum. Sem ação em massa — cada caso
/// precisa julgamento (mesclar cadastro, corrigir o EAN errado...), só
/// busca + atalho pra abrir cada produto e editar.
/// ---------------------------------------------------------------------
class _AbaEanDuplicado extends StatefulWidget {
  const _AbaEanDuplicado();

  @override
  State<_AbaEanDuplicado> createState() => _AbaEanDuplicadoState();
}

class _AbaEanDuplicadoState extends State<_AbaEanDuplicado> {
  String _busca = '';

  @override
  Widget build(BuildContext context) {
    final produtoProvider = context.watch<ProdutoProvider>();
    final grupos = _gruposEanDuplicado(produtoProvider.produtos)
        .where((grupo) => _busca.isEmpty || grupo.any((p) => contemTodasPalavras(p.nome, _busca)))
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: TextField(
            decoration: const InputDecoration(hintText: 'Buscar por nome', prefixIcon: Icon(Icons.search)),
            onChanged: (v) => setState(() => _busca = v),
          ),
        ),
        Expanded(
          child: grupos.isEmpty
              ? const Center(child: Text('Nenhum código de barras duplicado 🎉'))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: grupos.length,
                  itemBuilder: (context, index) {
                    final grupo = grupos[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 18),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'EAN ${grupo.first.codigoBarras} — ${grupo.length} produtos',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(),
                            for (final produto in grupo)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(produto.nome, maxLines: 2, overflow: TextOverflow.ellipsis),
                                subtitle: Text(
                                  'Preço: R\$ ${produto.preco.toStringAsFixed(2)} • Estoque: ${produto.estoqueAtual}',
                                ),
                                trailing: const Icon(Icons.edit_outlined),
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => EditarProdutoScreen(produto: produto)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// ---------------------------------------------------------------------
/// Aba 7: Estratégia — matriz margem × giro (versão de BCG adaptada pra
/// PME, sem precisar de dado de concorrente: eixo de "participação de
/// mercado" clássico do BCG vira giro de venda real, que é o dado que a
/// loja de fato tem — ver [[gestor_pedido_compra_fornecedor]] pra
/// contexto/fontes da pesquisa) + diagnóstico por produto (preço fora da
/// faixa da categoria, cadastro incompleto) + produtos comprados junto
/// (cross-sell) + sugestões de produto que cliente pediu e não achou
/// (reaproveita sugestoes_produto_cliente, já existente em Clientes —
/// só trazida pra cá pra ficar junto do resto da análise de produto).
/// ---------------------------------------------------------------------
class _AbaEstrategia extends StatefulWidget {
  const _AbaEstrategia();

  @override
  State<_AbaEstrategia> createState() => _AbaEstrategiaState();
}

class _QuadranteInfo {
  final String label;
  final Color cor;
  final String explicacao;
  const _QuadranteInfo(this.label, this.cor, this.explicacao);
}

const _quadrantes = {
  'estrela': _QuadranteInfo('Estrela', Colors.green, 'Giro alto + margem alta — o melhor time, proteger estoque.'),
  'vaca_leiteira': _QuadranteInfo('Vaca leiteira', Colors.blue, 'Giro alto + margem baixa — vende bem, mas rende pouco por unidade.'),
  'interrogacao': _QuadranteInfo('Interrogação', Colors.amber, 'Giro baixo + margem alta — vale destacar/promover antes de desistir.'),
  'abacaxi': _QuadranteInfo('Abacaxi', Colors.red, 'Giro baixo + margem baixa — candidato real a descontinuar.'),
  'sem_dado': _QuadranteInfo('Sem venda', Colors.grey, 'Nenhuma venda registrada no período analisado.'),
};

/// Texto curto de estratégia por célula ABC×XYZ — A/B/C é contribuição de
/// receita (Pareto acumulado, 180 dias), X/Y/Z é variabilidade de venda
/// (mesmo cálculo do estoque mínimo, 90 dias). Ver [[gestor_pedido_compra_fornecedor]].
const _estrategiaAbcXyz = {
  'A-X': 'Alto valor, previsível — controle rigoroso, é o núcleo do negócio.',
  'A-Y': 'Alto valor, moderado — revisão frequente, vale acompanhar de perto.',
  'A-Z': 'Alto valor, errático — atenção alta mas difícil de prever; revisar manualmente, não confiar só na média.',
  'B-X': 'Valor médio, previsível — controle padrão.',
  'B-Y': 'Valor médio, moderado — controle padrão.',
  'B-Z': 'Valor médio, errático — controle mais simples, não vale afinar demais.',
  'C-X': 'Baixo valor, previsível — pedidos grandes e espaçados, baixa prioridade administrativa.',
  'C-Y': 'Baixo valor, moderado — controle mínimo.',
  'C-Z': 'Baixo valor, errático — menor prioridade, manter só o piso operacional.',
};

class _AbaEstrategiaState extends State<_AbaEstrategia> {
  bool _carregando = true;
  String? _erro;
  List<Map<String, dynamic>> _linhas = [];
  List<Map<String, dynamic>> _sugestoesClientes = [];
  Map<String, Map<String, dynamic>> _abcXyzPorProduto = {};
  String? _filtroQuadrante;
  String _busca = '';
  bool _sugestoesExpandido = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final supabase = Supabase.instance.client;
      final resultado = await supabase.rpc('matriz_produto_margem_giro', params: {'p_empresa_id': empresaId});
      final abcXyz = await supabase.rpc('matriz_abc_xyz', params: {'p_empresa_id': empresaId});
      final sugestoes = await supabase
          .from('sugestoes_produto_cliente')
          .select()
          .eq('empresa_id', empresaId)
          .eq('status', 'pendente')
          .order('created_at', ascending: false)
          .limit(30);
      if (!mounted) return;
      final abcXyzLista = (abcXyz as List).cast<Map<String, dynamic>>();
      setState(() {
        _linhas = (resultado as List).cast<Map<String, dynamic>>();
        _sugestoesClientes = (sugestoes as List).cast<Map<String, dynamic>>();
        _abcXyzPorProduto = {for (final l in abcXyzLista) l['produto_id'] as String: l};
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar: $e';
        _carregando = false;
      });
    }
  }

  Future<void> _abrirDetalhe(Map<String, dynamic> linha) async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;
    final produtoProvider = context.read<ProdutoProvider>();
    Produto? produto;
    try {
      produto = produtoProvider.produtos.firstWhere((p) => p.id == linha['produto_id']);
    } catch (_) {
      produto = null;
    }
    final quadrante = _quadrantes[linha['quadrante']] ?? _quadrantes['sem_dado']!;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          maxChildSize: 0.92,
          expand: false,
          builder: (context, scrollController) {
            return ListView(
              controller: scrollController,
              padding: const EdgeInsets.all(20),
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: quadrante.cor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(linha['produto_nome'] as String,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(quadrante.label, style: TextStyle(color: quadrante.cor, fontWeight: FontWeight.w600)),
                Text(quadrante.explicacao, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                if (_abcXyzPorProduto[linha['produto_id']] != null) ...[
                  const SizedBox(height: 8),
                  Builder(builder: (context) {
                    final cel = _abcXyzPorProduto[linha['produto_id']]!;
                    final celula = cel['celula'] as String;
                    final texto = _estrategiaAbcXyz[celula];
                    return Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Classe ABC×XYZ: $celula', style: const TextStyle(fontWeight: FontWeight.w600)),
                          if (texto != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(texto, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            ),
                        ],
                      ),
                    );
                  }),
                ],
                const Divider(height: 24),
                _linhaDiagnostico('Giro semanal', '${linha['giro_semanal']} un/semana'),
                _linhaDiagnostico(
                  'Margem',
                  linha['margem_pct'] != null ? '${linha['margem_pct']}%' : 'sem dado',
                ),
                _linhaDiagnostico('Preço atual', 'R\$ ${(linha['preco_atual'] as num).toStringAsFixed(2)}'),
                if (linha['preco_mediano_categoria'] != null)
                  _linhaDiagnostico(
                    'Preço mediano da categoria',
                    'R\$ ${(linha['preco_mediano_categoria'] as num).toStringAsFixed(2)}',
                  ),
                const SizedBox(height: 8),
                Text('Possíveis causas se estiver parado', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                if (linha['preco_fora_da_faixa'] == true)
                  const _AlertaCausa('Preço bem acima da mediana da categoria (1,5x ou mais)'),
                if (linha['tem_foto'] == false) const _AlertaCausa('Produto sem foto no catálogo'),
                if (linha['codigo_barras_valido'] == false)
                  const _AlertaCausa('Sem código de barras válido — some do catálogo iFood/site'),
                if (linha['preco_fora_da_faixa'] != true &&
                    linha['tem_foto'] != false &&
                    linha['codigo_barras_valido'] != false)
                  const Text('Nenhuma causa óbvia encontrada — pode ser só falta de demanda mesmo.',
                      style: TextStyle(fontSize: 13, color: Colors.grey)),
                const Divider(height: 24),
                Text('Comprado junto com', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                FutureBuilder<List<dynamic>>(
                  future: Supabase.instance.client.rpc('produtos_comprados_juntos', params: {
                    'p_empresa_id': empresaId,
                    'p_produto_id': linha['produto_id'],
                  }),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                      );
                    }
                    final pares = (snapshot.data ?? []).cast<Map<String, dynamic>>();
                    if (pares.isEmpty) {
                      return const Text('Sem combinação frequente registrada ainda.',
                          style: TextStyle(fontSize: 13, color: Colors.grey));
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: pares
                          .map((par) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 3),
                                child: Text(
                                  '• ${par['produto_nome']} — junto em ${par['confianca_pct']}% das compras',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ))
                          .toList(),
                    );
                  },
                ),
                const SizedBox(height: 20),
                if (produto != null)
                  FilledButton.icon(
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar produto'),
                    onPressed: () {
                      Navigator.of(context).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => EditarProdutoScreen(produto: produto!)),
                      );
                    },
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _linhaDiagnostico(String label, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(valor, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) return const Center(child: CircularProgressIndicator());
    if (_erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_erro!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _carregar, child: const Text('Tentar de novo')),
            ],
          ),
        ),
      );
    }

    final contagemPorQuadrante = <String, int>{};
    for (final linha in _linhas) {
      final q = linha['quadrante'] as String? ?? 'sem_dado';
      contagemPorQuadrante[q] = (contagemPorQuadrante[q] ?? 0) + 1;
    }

    final filtrado = _linhas.where((linha) {
      if (_filtroQuadrante != null && linha['quadrante'] != _filtroQuadrante) return false;
      if (_busca.isNotEmpty && !contemTodasPalavras(linha['produto_nome'] as String, _busca)) return false;
      return true;
    }).toList()
      ..sort((a, b) => ((b['giro_semanal'] as num?) ?? 0).compareTo((a['giro_semanal'] as num?) ?? 0));

    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (_sugestoesClientes.isNotEmpty)
            Card(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    leading: const Icon(Icons.search_off, color: Colors.orange),
                    title: Text('Clientes buscaram e não acharam (${_sugestoesClientes.length})'),
                    trailing: Icon(_sugestoesExpandido ? Icons.expand_less : Icons.expand_more),
                    onTap: () => setState(() => _sugestoesExpandido = !_sugestoesExpandido),
                  ),
                  if (_sugestoesExpandido)
                    for (final s in _sugestoesClientes)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Text('• ${s['termo_buscado'] ?? s['mensagem'] ?? '(sem termo)'}',
                            style: const TextStyle(fontSize: 13)),
                      ),
                ],
              ),
            ),
          if (_abcXyzPorProduto.isNotEmpty) _CardAbcXyz(dados: _abcXyzPorProduto.values.toList()),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              decoration: const InputDecoration(hintText: 'Buscar produto', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => _busca = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: Text('Todos (${_linhas.length})'),
                  selected: _filtroQuadrante == null,
                  onSelected: (_) => setState(() => _filtroQuadrante = null),
                ),
                for (final entry in _quadrantes.entries)
                  ChoiceChip(
                    label: Text('${entry.value.label} (${contagemPorQuadrante[entry.key] ?? 0})'),
                    selected: _filtroQuadrante == entry.key,
                    selectedColor: entry.value.cor.withValues(alpha: 0.25),
                    onSelected: (_) => setState(() => _filtroQuadrante = entry.key),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          if (filtrado.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Nenhum produto encontrado com esse filtro')),
            )
          else
            for (final linha in filtrado)
              _CartaoProdutoEstrategia(
                linha: linha,
                quadrante: _quadrantes[linha['quadrante']] ?? _quadrantes['sem_dado']!,
                celula: _abcXyzPorProduto[linha['produto_id']]?['celula'] as String?,
                onTap: () => _abrirDetalhe(linha),
              ),
        ],
      ),
    );
  }
}

class _AlertaCausa extends StatelessWidget {
  final String texto;
  const _AlertaCausa(this.texto);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
          const SizedBox(width: 6),
          Expanded(child: Text(texto, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _CartaoProdutoEstrategia extends StatelessWidget {
  final Map<String, dynamic> linha;
  final _QuadranteInfo quadrante;
  final String? celula;
  final VoidCallback onTap;

  const _CartaoProdutoEstrategia({required this.linha, required this.quadrante, required this.celula, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final temAlerta = linha['preco_fora_da_faixa'] == true ||
        linha['tem_foto'] == false ||
        linha['codigo_barras_valido'] == false;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(color: quadrante.cor, shape: BoxShape.circle),
        ),
        title: Text(linha['produto_nome'] as String, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          'Giro: ${linha['giro_semanal']}/sem. • Margem: ${linha['margem_pct'] ?? '—'}%'
          '${celula != null && celula != 'sem_dado-sem_dado' ? ' • $celula' : ''}'
          '${temAlerta ? ' • ⚠ possível causa encontrada' : ''}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

/// Card-resumo colapsável da matriz ABC (valor/receita) × XYZ
/// (variabilidade) — grid com contagem por célula + estratégia curta.
class _CardAbcXyz extends StatefulWidget {
  final List<Map<String, dynamic>> dados;
  const _CardAbcXyz({required this.dados});

  @override
  State<_CardAbcXyz> createState() => _CardAbcXyzState();
}

class _CardAbcXyzState extends State<_CardAbcXyz> {
  bool _expandido = false;

  @override
  Widget build(BuildContext context) {
    final contagem = <String, int>{};
    for (final d in widget.dados) {
      final celula = d['celula'] as String? ?? 'sem_dado-sem_dado';
      contagem[celula] = (contagem[celula] ?? 0) + 1;
    }
    const classesAbc = ['A', 'B', 'C'];
    const classesXyz = ['X', 'Y', 'Z'];

    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            leading: const Icon(Icons.grid_view_rounded, color: Colors.indigo),
            title: const Text('Classificação ABC × XYZ'),
            subtitle: const Text('A/B/C = contribuição de receita • X/Y/Z = previsibilidade da venda'),
            trailing: Icon(_expandido ? Icons.expand_less : Icons.expand_more),
            onTap: () => setState(() => _expandido = !_expandido),
          ),
          if (_expandido)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final abc in classesAbc)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 20,
                            child: Text(abc, style: const TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                for (final xyz in classesXyz)
                                  Tooltip(
                                    message: _estrategiaAbcXyz['$abc-$xyz'] ?? '',
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '$abc$xyz: ${contagem['$abc-$xyz'] ?? 0}',
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    'Sem venda suficiente pra classificar: ${contagem['sem_dado-sem_dado'] ?? 0}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Toque numa célula (segurar) pra ver a estratégia sugerida.',
                    style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
