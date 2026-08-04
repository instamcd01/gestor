import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/produto_provider.dart';
import '../utils/busca_utils.dart';
import '../widgets/importar_produtos_planilha.dart';
import '../models/produto.dart';
import '../models/sugestao_variante.dart';
import 'adicionar_imagens_lote_screen.dart';
import 'cadastro_produto_screen.dart';
import 'configuracoes_produto_screen.dart';
import 'detalhes_produto_screen.dart';
import 'editar_produto_screen.dart';
import 'produtos_excluidos_screen.dart';
import 'sugestoes_variante_rejeitadas_screen.dart';

/// Rótulo amigável do eixo de variante ("peso"/"dose"/"sabor"...) pro
/// filtro em ProdutosScreen — cai pro próprio nome do tipo se for um eixo
/// novo ainda não previsto aqui (extensível sem mudar código, mesmo
/// espírito de `tipos_variacao` no banco).
String _rotuloTipoVariacao(String tipo) {
  switch (tipo) {
    case 'peso':
      return 'Peso';
    case 'volume':
      return 'Volume';
    case 'dose':
      return 'Dose';
    case 'sabor':
      return 'Sabor';
    case 'apresentacao':
      return 'Apresentação';
    default:
      return tipo;
  }
}

class ProdutosScreen extends StatefulWidget {
  const ProdutosScreen({super.key});

  @override
  State<ProdutosScreen> createState() => _ProdutosScreenState();
}

class _ProdutosScreenState extends State<ProdutosScreen> {
  final _searchController = TextEditingController();
  String _busca = '';
  // null = sem filtro; '' = qualquer tipo (equivalente ao antigo "tem
  // sugestão"); um tipo específico ("peso"/"dose"/"sabor"...) = só esse
  // eixo — dá pra ignorar um eixo específico (ex: "sabor" ainda não é
  // considerado) sem esconder os outros.
  String? _filtroTipoVariacao;
  bool _filtroRevisarPreco = false;
  bool _filtroEstoqueBaixo = false;
  String? _filtroCategoria;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProdutoProvider>().carregarProdutos();
    });
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

    final totalSugestaoVariante = produtoProvider.totalProdutosComSugestaoVariante;
    final contagemPorTipoVariacao = produtoProvider.contagemSugestoesPorTipo;
    final tiposVariacaoDisponiveis = contagemPorTipoVariacao.keys.toList()..sort();
    final totalRevisarPreco = produtoProvider.produtos.where((p) => p.revisarPreco).length;
    final totalEstoqueBaixo =
        produtoProvider.produtos.where((p) => p.estoqueAtual <= p.estoqueMinimo).length;

    final produtosFiltrados = produtoProvider.produtos.where((p) {
      final passaBusca = contemTodasPalavras(p.nome, _busca) ||
          p.codigoBarras.toLowerCase().contains(normalizarBusca(_busca)) ||
          contemTodasPalavras(p.categoria, _busca);
      if (!passaBusca) return false;
      if (_filtroTipoVariacao != null) {
        final sugestoes = p.id == null ? const <SugestaoVariante>[] : produtoProvider.sugestoesVariantePara(p.id!);
        final bate = _filtroTipoVariacao!.isEmpty
            ? sugestoes.isNotEmpty
            : sugestoes.any((s) => s.tipoVariacao == _filtroTipoVariacao);
        if (!bate) return false;
      }
      if (_filtroRevisarPreco && !p.revisarPreco) return false;
      if (_filtroEstoqueBaixo && p.estoqueAtual > p.estoqueMinimo) return false;
      if (_filtroCategoria != null && p.categoria != _filtroCategoria) return false;
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Produtos (${produtoProvider.produtos.length})'),
        actions: [
          if (!isVendedor) ...[
            IconButton(
              tooltip: 'Produtos excluídos',
              icon: const Icon(Icons.restore_from_trash_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ProdutosExcluidosScreen(),
              )),
            ),
            IconButton(
              tooltip: 'Importar planilha',
              icon: const Icon(Icons.upload_file_outlined),
              onPressed: _importarProdutos,
            ),
            IconButton(
              tooltip: 'Adicionar imagens em massa',
              icon: const Icon(Icons.add_photo_alternate_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const AdicionarImagensLoteScreen(),
              )),
            ),
            IconButton(
              tooltip: 'Configurações do Produto',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ConfiguracoesProdutoScreen(),
              )),
            ),
            IconButton(
              tooltip: 'Sugestões de variante rejeitadas',
              icon: const Icon(Icons.unpublished_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const SugestoesVarianteRejeitadasScreen(),
              )),
            ),
          ],
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () => produtoProvider.carregarProdutos(),
          ),
        ],
      ),
      floatingActionButton: isVendedor
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (ctx) => CadastroProdutoScreen(),
                ));
              },
              icon: const Icon(Icons.add),
              label: const Text('Novo produto'),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
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
                if (!isVendedor) ...[
                  PopupMenuButton<String?>(
                    tooltip: 'Filtrar sugestão de variante por tipo',
                    initialValue: _filtroTipoVariacao,
                    onSelected: (v) => setState(() => _filtroTipoVariacao = v),
                    itemBuilder: (context) => [
                      const PopupMenuItem<String?>(value: null, child: Text('Sem filtro')),
                      PopupMenuItem<String>(
                        value: '',
                        child: Text('Todas as sugestões ($totalSugestaoVariante)'),
                      ),
                      for (final tipo in tiposVariacaoDisponiveis)
                        PopupMenuItem<String>(
                          value: tipo,
                          child: Text('${_rotuloTipoVariacao(tipo)} (${contagemPorTipoVariacao[tipo]})'),
                        ),
                    ],
                    child: Chip(
                      avatar: const Icon(Icons.link_outlined, size: 18),
                      label: Text(
                        _filtroTipoVariacao == null
                            ? 'Sugestão de variante'
                            : _filtroTipoVariacao!.isEmpty
                                ? 'Todas as sugestões'
                                : _rotuloTipoVariacao(_filtroTipoVariacao!),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    label: Text('Revisar preço ($totalRevisarPreco)'),
                    selected: _filtroRevisarPreco,
                    onSelected: (v) => setState(() => _filtroRevisarPreco = v),
                  ),
                  const SizedBox(width: 8),
                ],
                FilterChip(
                  label: Text('Estoque baixo ($totalEstoqueBaixo)'),
                  selected: _filtroEstoqueBaixo,
                  onSelected: (v) => setState(() => _filtroEstoqueBaixo = v),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String?>(
                  tooltip: 'Filtrar por categoria',
                  initialValue: _filtroCategoria,
                  onSelected: (v) => setState(() => _filtroCategoria = v),
                  itemBuilder: (context) => [
                    const PopupMenuItem<String?>(value: null, child: Text('Todas as categorias')),
                    for (final categoria in categoriasDisponiveis)
                      PopupMenuItem<String?>(value: categoria, child: Text(categoria)),
                  ],
                  child: Chip(
                    avatar: const Icon(Icons.filter_list, size: 18),
                    label: Text(_filtroCategoria ?? 'Categoria'),
                  ),
                ),
                if (_filtroTipoVariacao != null ||
                    _filtroRevisarPreco ||
                    _filtroEstoqueBaixo ||
                    _filtroCategoria != null) ...[
                  const SizedBox(width: 8),
                  ActionChip(
                    avatar: const Icon(Icons.close, size: 16),
                    label: const Text('Limpar filtros'),
                    onPressed: () => setState(() {
                      _filtroTipoVariacao = null;
                      _filtroRevisarPreco = false;
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
                            temBusca: _busca.isNotEmpty ||
                                _filtroTipoVariacao != null ||
                                _filtroRevisarPreco ||
                                _filtroEstoqueBaixo ||
                                _filtroCategoria != null,
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                            itemCount: produtosFiltrados.length,
                            itemBuilder: (ctx, i) {
                              final produto = produtosFiltrados[i];
                              return _ProdutoCard(
                                produto: produto,
                                isVendedor: isVendedor,
                                onTap: () {
                                  Navigator.of(context).push(MaterialPageRoute(
                                    builder: (context) => isVendedor
                                        ? DetalhesProdutoScreen(produto: produto)
                                        : EditarProdutoScreen(produto: produto),
                                  ));
                                },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _ProdutoCard extends StatelessWidget {
  final Produto produto;
  final VoidCallback onTap;
  final bool isVendedor;

  const _ProdutoCard({required this.produto, required this.onTap, required this.isVendedor});

  Future<void> _confirmarRevisado(BuildContext context) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Marcar como revisado'),
        content: Text(
          'O custo de "${produto.nome}" mudou (agora R\$ ${produto.custo.toStringAsFixed(2)}). '
          'Marcar como revisado indica que você já conferiu o preço de venda (R\$ ${produto.preco.toStringAsFixed(2)}) e decidiu mantê-lo assim.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Marcar como revisado')),
        ],
      ),
    );
    if (confirmou == true && context.mounted) {
      await context.read<ProdutoProvider>().marcarPrecoRevisado(produto.id!);
    }
  }

  Future<void> _abrirRevisaoVariante(BuildContext context, List<SugestaoVariante> sugestoes) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _DialogoRevisaoVariante(produto: produto, sugestoes: sugestoes),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final estoqueBaixo = produto.estoqueAtual <= produto.estoqueMinimo;
    final sugestoesVariante =
        produto.id == null ? <SugestaoVariante>[] : context.watch<ProdutoProvider>().sugestoesVariantePara(produto.id!);

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
                      ? Image.network(
                          produto.imagemUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
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
                    if (produto.revisarPreco && !isVendedor) ...[
                      const SizedBox(height: 8),
                      ActionChip(
                        avatar: const Icon(Icons.price_change_outlined, size: 16, color: Colors.orange),
                        label: const Text('Custo mudou — revisar preço', style: TextStyle(fontSize: 12)),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: Color.alphaBlend(Colors.orange.withValues(alpha: 0.15), colorScheme.surface),
                        onPressed: () => _confirmarRevisado(context),
                      ),
                    ],
                    if (sugestoesVariante.isNotEmpty && !isVendedor) ...[
                      const SizedBox(height: 8),
                      ActionChip(
                        avatar: Icon(
                          sugestoesVariante.first.origem == 'estruturado'
                              ? Icons.link_outlined
                              : Icons.link_off_outlined,
                          size: 16,
                          color: colorScheme.tertiary,
                        ),
                        label: Text(
                          sugestoesVariante.length > 1
                              ? 'Sugestões de variante (${sugestoesVariante.length})'
                              : 'Sugestão de variante',
                          style: const TextStyle(fontSize: 12),
                        ),
                        visualDensity: VisualDensity.compact,
                        backgroundColor:
                            Color.alphaBlend(colorScheme.tertiary.withValues(alpha: 0.15), colorScheme.surface),
                        onPressed: () => _abrirRevisaoVariante(context, sugestoesVariante),
                      ),
                    ],
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

  const _BadgeEstoque({required this.quantidade, required this.baixo});

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
              '$quantidade em estoque',
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

/// Diálogo de revisão das sugestões automáticas de agrupamento de variante
/// pra um produto — um produto pode ter mais de uma pendente (ex: 3+
/// variantes da mesma linha), então passa por elas uma de cada vez ("X de
/// N"), sem fechar até acabar. Compara os dois produtos lado a lado e deixa
/// o rótulo de cada um editável antes de aprovar. Nada é publicado sem essa
/// confirmação manual (ver seção 4 da spec de variantes).
class _DialogoRevisaoVariante extends StatefulWidget {
  final Produto produto;
  final List<SugestaoVariante> sugestoes;

  const _DialogoRevisaoVariante({required this.produto, required this.sugestoes});

  @override
  State<_DialogoRevisaoVariante> createState() => _DialogoRevisaoVarianteState();
}

class _DialogoRevisaoVarianteState extends State<_DialogoRevisaoVariante> {
  late List<SugestaoVariante> _restantes;
  late TextEditingController _labelProdutoController;
  late TextEditingController _labelCandidatoController;
  Produto? _candidato;
  bool _processando = false;

  /// Quando o candidato ainda não tem variante_label (primeira vez que dois
  /// produtos avulsos são pareados), tenta um valor inicial razoável a
  /// partir do campo estruturado correspondente ao eixo detectado.
  String _labelPadrao(Produto p, String tipoVariacao) {
    if (p.varianteLabel != null && p.varianteLabel!.isNotEmpty) return p.varianteLabel!;
    switch (tipoVariacao) {
      case 'peso':
        return p.peso != null ? '${p.peso}kg' : '';
      case 'volume':
        return p.volume != null ? '${p.volume}ml' : '';
      case 'dose':
        return p.dose ?? '';
      case 'sabor':
        return p.sabor ?? '';
      case 'apresentacao':
        return p.apresentacao ?? '';
      default:
        return '';
    }
  }

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
    _labelCandidatoController =
        TextEditingController(text: _candidato != null ? _labelPadrao(_candidato!, atual.tipoVariacao) : '');
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
