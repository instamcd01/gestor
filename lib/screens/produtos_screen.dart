import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/kit_produto_provider.dart';
import '../providers/produto_provider.dart';
import '../repositories/produto_canal_repository.dart';
import '../utils/busca_utils.dart';
import '../widgets/importar_produtos_planilha.dart';
import '../widgets/produto_edicao_rapida.dart';
import '../models/produto.dart';
import 'adicionar_imagens_lote_screen.dart';
import 'analise_produtos_screen.dart';
import 'cadastro_produto_screen.dart';
import 'checklist_estoque_screen.dart';
import 'configuracoes_produto_screen.dart';
import 'detalhes_produto_screen.dart';
import 'editar_produto_screen.dart';
import 'fracionamento_lote_screen.dart';
import 'kit_produto_form_screen.dart';
import 'produtos_excluidos_screen.dart';

/// true enquanto o painel de edição rápida tem alteração não salva. Global
/// porque o menu lateral também mostra (pontinho no ícone de Produtos): a
/// tela fica guardada por trás quando se troca de seção, nada se perde,
/// mas é fácil esquecer.
final produtosAlteracaoPendente = ValueNotifier<bool>(false);

class ProdutosScreen extends StatefulWidget {
  const ProdutosScreen({super.key});

  @override
  State<ProdutosScreen> createState() => _ProdutosScreenState();
}

class _ProdutosScreenState extends State<ProdutosScreen> {
  final _searchController = TextEditingController();
  String _busca = '';
  bool _filtroEstoqueBaixo = false;
  String? _filtroCategoria;

  /// Filtro "Canal" (PC): [_canalSite], [_canalNenhum] ou o nome do
  /// marketplace (iFood, 99Food...). null = todos.
  String? _filtroCanal;
  static const _canalSite = 'Site';
  static const _canalNenhum = '__nenhum';

  /// Marketplaces em que cada produto está à venda (`produto_canal`).
  Map<String, Set<String>> _canais = {};

  // Layout largo (PC): tabela + painel de edição ao lado.
  final _buscaFoco = FocusNode();
  final _tabelaFoco = FocusNode();
  final _tabelaScroll = ScrollController();
  String? _selecionadoId;
  int _versaoPainel = 0;
  _ColunaOrdem _ordem = _ColunaOrdem.nome;
  bool _ordemCrescente = true;

  /// Largura da janela a partir da qual a tela vira tabela + painel.
  static const larguraPc = 1200.0;
  static const _alturaLinha = 56.0;

  @override
  void dispose() {
    _searchController.dispose();
    _buscaFoco.dispose();
    _tabelaFoco.dispose();
    _tabelaScroll.dispose();
    produtosAlteracaoPendente.value = false;
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProdutoProvider>().carregarProdutos();
      _carregarCanais();
    });
  }

  Future<void> _carregarCanais({List<String>? ids}) async {
    try {
      final novos = await ProdutoCanalRepository().canaisDisponiveis(produtoIds: ids);
      if (!mounted) return;
      setState(() {
        if (ids == null) {
          _canais = novos;
        } else {
          for (final id in ids) {
            _canais[id] = novos[id] ?? <String>{};
          }
        }
      });
    } catch (e) {
      debugPrint('Erro ao carregar canais dos produtos: $e');
    }
  }

  bool _noSite(Produto p) => p.ativo && p.exibirNoCatalogo;

  bool _passaCanal(Produto p) => switch (_filtroCanal) {
        null => true,
        _canalSite => _noSite(p),
        _canalNenhum => !_noSite(p) && (_canais[p.id] ?? const {}).isEmpty,
        final nome => p.ativo && (_canais[p.id] ?? const {}).contains(nome),
      };

  /// Abre o produto em tela cheia (celular, ou kit em qualquer tamanho).
  Future<void> _abrirProduto(Produto produto, bool isVendedor) async {
    // Kit entrou na lista de Produtos (09/09) só pra cupom/alerta
    // de estoque enxergarem ele — editar continua exigindo a tela
    // própria (escolha de componentes), nunca o formulário normal.
    if (produto.ehKit) {
      final kitProvider = context.read<KitProdutoProvider>();
      await kitProvider.carregarKits();
      if (!mounted) return;
      final kit = kitProvider.kits.where((k) => k.id == produto.id).firstOrNull;
      if (kit == null) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => KitProdutoFormScreen(kitInicial: kit)));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => isVendedor
          ? DetalhesProdutoScreen(produto: produto)
          : EditarProdutoScreen(produto: produto),
    ));
  }

  /// Antes de sair do produto aberto no painel: se tem alteração não
  /// salva, pergunta. true = pode sair.
  Future<bool> _podeSairDoPainel() async {
    if (!produtosAlteracaoPendente.value) return true;
    final descartar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Alterações não salvas'),
        content: const Text('Você mudou este produto e ainda não salvou. Descartar as alterações?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Continuar editando')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Descartar')),
        ],
      ),
    );
    if (descartar == true) produtosAlteracaoPendente.value = false;
    return descartar == true;
  }

  /// Troca o produto do painel (clique, setas, Esc) respeitando o aviso.
  Future<void> _selecionar(String? id, {int? indiceParaMostrar}) async {
    if (id == _selecionadoId) return;
    if (!await _podeSairDoPainel() || !mounted) return;
    setState(() => _selecionadoId = id);
    if (indiceParaMostrar != null) _mostrarLinha(indiceParaMostrar);
    _tabelaFoco.requestFocus();
  }

  void _novoProduto() {
    Navigator.of(context).push(MaterialPageRoute(builder: (ctx) => CadastroProdutoScreen()));
  }

  List<Produto> _ordenar(List<Produto> lista) {
    int compara(Produto a, Produto b) => switch (_ordem) {
          _ColunaOrdem.nome => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()),
          _ColunaOrdem.categoria => a.categoria.toLowerCase().compareTo(b.categoria.toLowerCase()),
          _ColunaOrdem.preco => a.precoVendaAtual.compareTo(b.precoVendaAtual),
          _ColunaOrdem.estoque => a.estoqueAtual.compareTo(b.estoqueAtual),
        };
    return [...lista]..sort((a, b) => _ordemCrescente ? compara(a, b) : compara(b, a));
  }

  void _trocarOrdem(_ColunaOrdem coluna) => setState(() {
        if (_ordem == coluna) {
          _ordemCrescente = !_ordemCrescente;
        } else {
          _ordem = coluna;
          _ordemCrescente = true;
        }
      });

  /// ↑ ↓ trocam de produto, Esc fecha o painel — só com o foco na tabela,
  /// pra não brigar com as setas dentro dos campos do painel.
  KeyEventResult _teclaNaTabela(KeyEvent evento, List<Produto> lista) {
    if (evento is! KeyDownEvent && evento is! KeyRepeatEvent) return KeyEventResult.ignored;
    final tecla = evento.logicalKey;
    if (tecla == LogicalKeyboardKey.escape) {
      if (_selecionadoId == null) return KeyEventResult.ignored;
      _selecionar(null);
      return KeyEventResult.handled;
    }
    final passo = tecla == LogicalKeyboardKey.arrowDown
        ? 1
        : tecla == LogicalKeyboardKey.arrowUp
            ? -1
            : 0;
    if (passo == 0 || lista.isEmpty) return KeyEventResult.ignored;
    final atual = lista.indexWhere((p) => p.id == _selecionadoId);
    final novo = atual < 0 ? 0 : (atual + passo).clamp(0, lista.length - 1);
    _selecionar(lista[novo].id, indiceParaMostrar: novo);
    return KeyEventResult.handled;
  }

  void _mostrarLinha(int indice) {
    if (!_tabelaScroll.hasClients) return;
    final pos = _tabelaScroll.position;
    final topo = indice * _alturaLinha;
    final base = topo + _alturaLinha;
    if (topo < pos.pixels) {
      _tabelaScroll.jumpTo(topo);
    } else if (base > pos.pixels + pos.viewportDimension) {
      _tabelaScroll.jumpTo((base - pos.viewportDimension).clamp(0, pos.maxScrollExtent));
    }
  }

  Future<void> _importarProdutos() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => ImportarProdutosScreen(),
    ));
    if (mounted) context.read<ProdutoProvider>().carregarProdutos();
  }

  @override
  Widget build(BuildContext context) {
    final produtoProvider = context.watch<ProdutoProvider>();
    // Vendedor só consulta o catálogo (ver detalhesProdutoScreen) — criar,
    // importar/exportar e restaurar produto excluído é gestão de catálogo,
    // não venda.
    final isVendedor = context.watch<AuthProvider>().isVendedor;

    final categoriasDisponiveis = produtoProvider.produtos
        .map((p) => p.categoria)
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    final totalEstoqueBaixo =
        produtoProvider.produtos.where((p) => p.estoqueAtual <= p.estoqueMinimo).length;

    final produtosFiltrados = produtoProvider.produtos.where((p) {
      final passaBusca = contemTodasPalavras(p.nome, _busca) ||
          p.codigoBarras.toLowerCase().contains(normalizarBusca(_busca)) ||
          contemTodasPalavras(p.categoria, _busca);
      if (!passaBusca) return false;
      if (_filtroEstoqueBaixo && p.estoqueAtual > p.estoqueMinimo) return false;
      if (_filtroCategoria != null && p.categoria != _filtroCategoria) return false;
      if (!_passaCanal(p)) return false;
      return true;
    }).toList();

    final largo = MediaQuery.sizeOf(context).width >= larguraPc;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => _buscaFoco.requestFocus(),
        if (!isVendedor) const SingleActivator(LogicalKeyboardKey.keyN, control: true): _novoProduto,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
      appBar: AppBar(
        title: Text('Produtos (${produtoProvider.produtos.length})'),
        actions: [
          // Fora do ⋮ de propósito: o vendedor também faz a contagem.
          IconButton(
            tooltip: 'Checklist de estoque',
            icon: const Icon(Icons.fact_check_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => const ChecklistEstoqueScreen(),
            )),
          ),
          if (!isVendedor)
            PopupMenuButton<VoidCallback>(
              tooltip: 'Mais opções',
              icon: const Icon(Icons.more_vert),
              onSelected: (acao) => acao(),
              itemBuilder: (context) => [
                PopupMenuItem<VoidCallback>(
                  value: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ProdutosExcluidosScreen(),
                  )),
                  child: const ListTile(
                    leading: Icon(Icons.restore_from_trash_outlined),
                    title: Text('Produtos excluídos'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem<VoidCallback>(
                  value: _importarProdutos,
                  child: const ListTile(
                    leading: Icon(Icons.upload_file_outlined),
                    title: Text('Importar planilha'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem<VoidCallback>(
                  value: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const AdicionarImagensLoteScreen(),
                  )),
                  child: const ListTile(
                    leading: Icon(Icons.add_photo_alternate_outlined),
                    title: Text('Adicionar imagens em massa'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem<VoidCallback>(
                  value: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const AnaliseProdutosScreen(),
                  )),
                  child: const ListTile(
                    leading: Icon(Icons.fact_check_outlined),
                    title: Text('Análise de produtos em massa'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem<VoidCallback>(
                  value: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const FracionamentoLoteScreen(),
                  )),
                  child: const ListTile(
                    leading: Icon(Icons.call_split),
                    title: Text('Criar fracionamento em massa'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem<VoidCallback>(
                  value: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const ConfiguracoesProdutoScreen(),
                  )),
                  child: const ListTile(
                    leading: Icon(Icons.settings_outlined),
                    title: Text('Configurações do Produto'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () => produtoProvider.carregarProdutos(),
          ),
        ],
      ),
      floatingActionButton: isVendedor || largo
          ? null
          : FloatingActionButton.extended(
              onPressed: _novoProduto,
              icon: const Icon(Icons.add),
              label: const Text('Novo produto'),
            ),
      body: largo
          ? _layoutPc(
              produtoProvider: produtoProvider,
              produtos: _ordenar(produtosFiltrados),
              categorias: categoriasDisponiveis,
              totalEstoqueBaixo: totalEstoqueBaixo,
              isVendedor: isVendedor,
            )
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              focusNode: _buscaFoco,
              decoration: InputDecoration(
                hintText: 'Buscar por nome, categoria ou código de barras',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _busca.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _busca = '');
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _busca = v),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
            child: Row(
              children: [
                FilterChip(
                  label: Text('Estoque baixo ($totalEstoqueBaixo)'),
                  selected: _filtroEstoqueBaixo,
                  onSelected: (v) => setState(() => _filtroEstoqueBaixo = v),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  tooltip: 'Filtrar por categoria',
                  initialValue: _filtroCategoria ?? '',
                  // '' = todas (o menu trata null como "cancelou").
                  onSelected: (v) => setState(() => _filtroCategoria = v.isEmpty ? null : v),
                  itemBuilder: (context) => [
                    const PopupMenuItem<String>(value: '', child: Text('Todas as categorias')),
                    for (final categoria in categoriasDisponiveis)
                      PopupMenuItem<String>(value: categoria, child: Text(categoria)),
                  ],
                  child: Chip(
                    avatar: const Icon(Icons.filter_list, size: 18),
                    label: Text(_filtroCategoria ?? 'Categoria'),
                  ),
                ),
                if (_filtroEstoqueBaixo || _filtroCategoria != null) ...[
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.close, size: 16),
                    label: const Text('Limpar filtros'),
                    onPressed: () => setState(() {
                      _filtroEstoqueBaixo = false;
                      _filtroCategoria = null;
                    }),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: produtoProvider.carregando
                ? const Center(child: CircularProgressIndicator())
                : produtoProvider.erro != null
                    ? _EstadoErro(
                        mensagem: produtoProvider.erro!,
                        onTentarNovamente: () => produtoProvider.carregarProdutos(),
                      )
                    : produtosFiltrados.isEmpty
                        ? _EstadoVazio(
                            temBusca: _busca.isNotEmpty || _filtroEstoqueBaixo || _filtroCategoria != null,
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                            itemCount: produtosFiltrados.length,
                            itemBuilder: (ctx, i) {
                              final produto = produtosFiltrados[i];
                              return _ProdutoCard(
                                produto: produto,
                                isVendedor: isVendedor,
                                onTap: () => _abrirProduto(produto, isVendedor),
                              );
                            },
                          ),
          ),
        ],
      ),
        ),
      ),
    );
  }

  bool get _temFiltroDeChip => _filtroEstoqueBaixo || _filtroCategoria != null || _filtroCanal != null;
  bool get _temFiltro => _busca.isNotEmpty || _temFiltroDeChip;

  Widget _layoutPc({
    required ProdutoProvider produtoProvider,
    required List<Produto> produtos,
    required List<String> categorias,
    required int totalEstoqueBaixo,
    required bool isVendedor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final selecionado =
        _selecionadoId == null ? null : produtoProvider.produtos.where((p) => p.id == _selecionadoId).firstOrNull;

    Widget conteudoTabela;
    if (produtoProvider.carregando) {
      conteudoTabela = const Center(child: CircularProgressIndicator());
    } else if (produtoProvider.erro != null) {
      conteudoTabela = _EstadoErro(
        mensagem: produtoProvider.erro!,
        onTentarNovamente: () => produtoProvider.carregarProdutos(),
      );
    } else if (produtos.isEmpty) {
      conteudoTabela = _EstadoVazio(temBusca: _temFiltro);
    } else {
      conteudoTabela = Focus(
        focusNode: _tabelaFoco,
        onKeyEvent: (_, evento) => _teclaNaTabela(evento, produtos),
        child: Column(
          children: [
            _CabecalhoTabela(ordem: _ordem, crescente: _ordemCrescente, onOrdenar: _trocarOrdem),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                controller: _tabelaScroll,
                itemExtent: _alturaLinha,
                itemCount: produtos.length,
                itemBuilder: (ctx, i) {
                  final produto = produtos[i];
                  return _LinhaProduto(
                    produto: produto,
                    canais: _canais[produto.id] ?? const {},
                    selecionado: produto.id == _selecionadoId,
                    onTap: () => _selecionar(produto.id),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              SizedBox(
                width: MediaQuery.sizeOf(context).width < 1400 ? 300 : 420,
                child: TextField(
                  controller: _searchController,
                  focusNode: _buscaFoco,
                  decoration: InputDecoration(
                    hintText: 'Buscar produto ou código de barras',
                    prefixIcon: const Icon(Icons.search),
                    isDense: true,
                    suffixIcon: _busca.isNotEmpty
                        ? IconButton(
                            tooltip: 'Limpar busca',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _busca = '');
                            },
                          )
                        : Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: Center(
                              widthFactor: 1,
                              child: Text('Ctrl F',
                                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                            ),
                          ),
                  ),
                  onChanged: (v) => setState(() => _busca = v),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilterChip(
                      label: Text('Estoque baixo ($totalEstoqueBaixo)'),
                      selected: _filtroEstoqueBaixo,
                      onSelected: (v) => setState(() => _filtroEstoqueBaixo = v),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Filtrar por categoria',
                      initialValue: _filtroCategoria ?? '',
                      onSelected: (v) => setState(() => _filtroCategoria = v.isEmpty ? null : v),
                      itemBuilder: (context) => [
                        const PopupMenuItem<String>(value: '', child: Text('Todas as categorias')),
                        for (final categoria in categorias)
                          PopupMenuItem<String>(value: categoria, child: Text(categoria)),
                      ],
                      child: Chip(
                        avatar: const Icon(Icons.filter_list, size: 18),
                        label: Text(_filtroCategoria ?? 'Categoria'),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Filtrar por canal de venda',
                      initialValue: _filtroCanal ?? '',
                      onSelected: (v) => setState(() => _filtroCanal = v.isEmpty ? null : v),
                      itemBuilder: (context) => [
                        const PopupMenuItem<String>(value: '', child: Text('Todos os canais')),
                        const PopupMenuItem<String>(value: _canalSite, child: Text('No site')),
                        for (final nome in ({for (final c in _canais.values) ...c}.toList()..sort()))
                          PopupMenuItem<String>(value: nome, child: Text('No $nome')),
                        const PopupMenuItem<String>(
                            value: _canalNenhum, child: Text('Em nenhum canal online')),
                      ],
                      child: Chip(
                        avatar: const Icon(Icons.storefront_outlined, size: 18),
                        label: Text(switch (_filtroCanal) {
                          null => 'Canal',
                          _canalSite => 'No site',
                          _canalNenhum => 'Em nenhum canal',
                          final nome => 'No $nome',
                        }),
                      ),
                    ),
                    if (_temFiltroDeChip)
                      ActionChip(
                        avatar: const Icon(Icons.close, size: 16),
                        label: const Text('Limpar filtros'),
                        onPressed: () => setState(() {
                          _filtroEstoqueBaixo = false;
                          _filtroCategoria = null;
                          _filtroCanal = null;
                        }),
                      ),
                    if (_temFiltro)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text('${produtos.length} encontrados',
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                      ),
                  ],
                ),
              ),
              if (!isVendedor) ...[
                const SizedBox(width: 12),
                Tooltip(
                  message: 'Ctrl N',
                  child: FilledButton.icon(
                    onPressed: _novoProduto,
                    icon: const Icon(Icons.add),
                    label: const Text('Novo produto'),
                  ),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          // Janela perto do mínimo do PC: painel um pouco mais estreito e a
          // tabela sem a coluna Categoria (ela aparece no painel).
          child: LayoutBuilder(builder: (context, limites) {
            final larguraPainel = (limites.maxWidth * 0.42).clamp(380.0, 500.0).toDouble();
            final compacto = limites.maxWidth - larguraPainel < 760;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _ColunasCompactas(compacto: compacto, child: conteudoTabela)),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: larguraPainel,
                  child: _painel(selecionado, isVendedor),
                ),
              ],
            );
          }),
        ),
        const Divider(height: 1),
        Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.centerLeft,
          child: Text(
            [
              '↑ ↓ trocar de produto',
              'Esc fechar',
              'Ctrl F buscar',
              if (!isVendedor) 'Ctrl N novo produto',
              'Clique no título da coluna pra ordenar',
            ].join('     ·     '),
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Widget _painel(Produto? produto, bool isVendedor) {
    final colorScheme = Theme.of(context).colorScheme;
    if (produto == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app_outlined, size: 40, color: colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              const Text('Clique num produto pra ver e editar aqui', textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text('As setas ↑ ↓ passam pro próximo.',
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }
    if (produto.ehKit) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.card_giftcard_outlined, size: 40, color: colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(produto.nome, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text('Kit tem editor próprio (escolha dos itens).',
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _abrirProduto(produto, isVendedor),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Abrir kit'),
              ),
            ],
          ),
        ),
      );
    }
    // Edição rápida (o do dia a dia); o resto na "Ficha completa", a tela
    // de edição de sempre. A chave muda depois de salvar, pra reabrir com
    // os dados novos.
    final chave = ValueKey('${produto.id}-$_versaoPainel');
    if (isVendedor) {
      return ClipRect(child: DetalhesProdutoScreen(key: chave, produto: produto, embutido: true));
    }
    return ProdutoEdicaoRapida(
      key: chave,
      produto: produto,
      temAlteracoes: produtosAlteracaoPendente,
      onSalvo: () {
        _carregarCanais(ids: [produto.id!]);
        if (mounted) setState(() => _versaoPainel++);
      },
      onAbrirFicha: () async {
        // A ficha lê do banco: o que foi digitado aqui e não salvo se perderia.
        if (!await _podeSairDoPainel() || !mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditarProdutoScreen(produto: produto)));
        if (!mounted) return;
        _carregarCanais(ids: [produto.id!]);
        setState(() => _versaoPainel++);
      },
    );
  }
}

enum _ColunaOrdem { nome, categoria, preco, estoque }

/// Avisa cabeçalho e linhas da tabela que falta largura (sem coluna Categoria).
class _ColunasCompactas extends InheritedWidget {
  final bool compacto;
  const _ColunasCompactas({required this.compacto, required super.child});

  static bool de(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ColunasCompactas>()?.compacto ?? false;

  @override
  bool updateShouldNotify(_ColunasCompactas antigo) => antigo.compacto != compacto;
}

const _larguraCategoria = 170.0;
const _larguraPreco = 110.0;
const _larguraEstoque = 110.0;
const _larguraSituacao = 150.0;

String _reais(double v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

class _CabecalhoTabela extends StatelessWidget {
  final _ColunaOrdem ordem;
  final bool crescente;
  final ValueChanged<_ColunaOrdem> onOrdenar;

  const _CabecalhoTabela({required this.ordem, required this.crescente, required this.onOrdenar});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    Widget titulo(String texto, _ColunaOrdem coluna, {bool direita = false}) {
      final ativa = ordem == coluna;
      final cor = ativa ? colorScheme.primary : colorScheme.onSurfaceVariant;
      return InkWell(
        onTap: () => onOrdenar(coluna),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            mainAxisAlignment: direita ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Text(texto.toUpperCase(),
                  style: TextStyle(fontSize: 11, letterSpacing: 0.5, fontWeight: FontWeight.w600, color: cor)),
              if (ativa) Icon(crescente ? Icons.arrow_upward : Icons.arrow_downward, size: 14, color: cor),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          const SizedBox(width: 52),
          Expanded(child: titulo('Produto', _ColunaOrdem.nome)),
          if (!_ColunasCompactas.de(context))
            SizedBox(width: _larguraCategoria, child: titulo('Categoria', _ColunaOrdem.categoria)),
          SizedBox(width: _ColunasCompactas.de(context) ? 96 : _larguraPreco, child: titulo('Preço', _ColunaOrdem.preco, direita: true)),
          SizedBox(width: _ColunasCompactas.de(context) ? 70 : _larguraEstoque, child: titulo('Estoque', _ColunaOrdem.estoque, direita: true)),
          SizedBox(
            width: _ColunasCompactas.de(context) ? 112 : _larguraSituacao,
            child: Padding(
              padding: const EdgeInsets.only(left: 20),
              child: Text('CANAIS',
                  style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurfaceVariant)),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinhaProduto extends StatelessWidget {
  final Produto produto;
  final Set<String> canais;
  final bool selecionado;
  final VoidCallback onTap;

  const _LinhaProduto({required this.produto, required this.canais, required this.selecionado, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final estoqueBaixo = produto.estoqueAtual <= produto.estoqueMinimo;
    final emPromocao = produto.precoVendaAtual < produto.preco;
    // Onde o cliente encontra o produto. Inativo não aparece em lugar nenhum.
    final selos = !produto.ativo
        ? const <String>[]
        : [if (produto.exibirNoCatalogo) 'Site', ...(canais.toList()..sort())];

    return Material(
      color: selecionado ? colorScheme.primary.withValues(alpha: 0.14) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: selecionado ? colorScheme.primary : Colors.transparent, width: 3),
              bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
          ),
          padding: const EdgeInsets.only(left: 13, right: 16),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  width: 38,
                  height: 38,
                  color: colorScheme.surfaceContainerHighest,
                  child: produto.imagemUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: produto.imagemUrlExibicao,
                          fit: BoxFit.cover,
                          memCacheWidth: 96,
                          errorWidget: (_, __, ___) =>
                              Icon(Icons.inventory_2_outlined, size: 18, color: colorScheme.onSurfaceVariant),
                        )
                      : Icon(produto.ehKit ? Icons.card_giftcard_outlined : Icons.inventory_2_outlined,
                          size: 18, color: colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  produto.nome,
                  // Estreito: nome em 2 linhas (numa só não dava pra ler).
                  maxLines: _ColunasCompactas.de(context) ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: _ColunasCompactas.de(context) ? 13 : 14,
                      height: 1.2,
                      fontWeight: selecionado ? FontWeight.w600 : FontWeight.w500),
                ),
              ),
              if (!_ColunasCompactas.de(context))
              SizedBox(
                width: _larguraCategoria,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(
                    produto.categoria.isNotEmpty ? produto.categoria : 'Sem categoria',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
              SizedBox(
                width: _ColunasCompactas.de(context) ? 96 : _larguraPreco,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(_reais(produto.precoVendaAtual),
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: colorScheme.primary)),
                    if (emPromocao)
                      Text(_reais(produto.preco),
                          style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSurfaceVariant,
                              decoration: TextDecoration.lineThrough)),
                  ],
                ),
              ),
              SizedBox(
                width: _ColunasCompactas.de(context) ? 70 : _larguraEstoque,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _BadgeEstoque(quantidade: produto.estoqueAtual, baixo: estoqueBaixo, curto: true),
                ),
              ),
              SizedBox(
                width: _ColunasCompactas.de(context) ? 112 : _larguraSituacao,
                child: Padding(
                  padding: EdgeInsets.only(left: _ColunasCompactas.de(context) ? 10 : 20),
                  child: selos.isEmpty
                      ? Text(produto.ativo ? 'Só na loja' : 'Inativo',
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant))
                      : Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          children: [
                            for (final selo in selos.take(3))
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  color: colorScheme.surfaceContainerHighest,
                                ),
                                child: Text(selo, style: const TextStyle(fontSize: 11)),
                              ),
                            if (selos.length > 3)
                              Text('+${selos.length - 3}',
                                  style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProdutoCard extends StatelessWidget {
  final Produto produto;
  final VoidCallback onTap;
  final bool isVendedor;

  const _ProdutoCard({required this.produto, required this.onTap, required this.isVendedor});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final estoqueBaixo = produto.estoqueAtual <= produto.estoqueMinimo;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 64,
                  height: 64,
                  color: colorScheme.surfaceContainerHighest,
                  child: produto.imagemUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: produto.imagemUrlExibicao,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Icon(
                            Icons.inventory_2_outlined,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        )
                      : Icon(Icons.inventory_2_outlined, color: colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      produto.nome,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      produto.categoria.isNotEmpty ? produto.categoria : 'Sem categoria',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // Flexible nos dois — sem isso, numa coluna estreita
                        // (ex: barra lateral sempre visível tirando espaço)
                        // essa linha estourava (RenderFlex overflow).
                        Flexible(
                          child: Text(
                            'R\$ ${produto.preco.toStringAsFixed(2)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.primary,
                                ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: _BadgeEstoque(
                            quantidade: produto.estoqueAtual,
                            baixo: estoqueBaixo,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _BadgeEstoque extends StatelessWidget {
  final int quantidade;
  final bool baixo;
  final bool curto;

  const _BadgeEstoque({required this.quantidade, required this.baixo, this.curto = false});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cor = baixo ? colorScheme.error : colorScheme.secondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            baixo ? Icons.warning_amber_rounded : Icons.inventory_outlined,
            size: 13,
            color: cor,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              curto ? '$quantidade' : '$quantidade em estoque',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cor),
            ),
          ),
        ],
      ),
    );
  }
}

class _EstadoVazio extends StatelessWidget {
  final bool temBusca;
  const _EstadoVazio({required this.temBusca});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              temBusca ? Icons.search_off : Icons.inventory_2_outlined,
              size: 56,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              temBusca ? 'Nenhum produto encontrado' : 'Nenhum produto cadastrado ainda',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              temBusca
                  ? 'Tente buscar por outro termo.'
                  : 'Toque em "Novo produto" pra começar seu catálogo.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EstadoErro extends StatelessWidget {
  final String mensagem;
  final VoidCallback onTentarNovamente;

  const _EstadoErro({required this.mensagem, required this.onTentarNovamente});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(
              'Não foi possível carregar os produtos',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onTentarNovamente,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
