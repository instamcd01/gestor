import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/estoque_parado.dart';
import '../models/produto.dart';
import '../models/sugestao_variante.dart';
import '../providers/auth_provider.dart';
import '../providers/branding_provider.dart';
import '../providers/produto_provider.dart';
import '../repositories/checklist_estoque_repository.dart';
import '../repositories/produto_repository.dart';
import '../repositories/revisao_preco_repository.dart';
import '../utils/busca_utils.dart';
import '../utils/produto_validators.dart';
import '../utils/telefone_utils.dart';
import '../utils/variante_label_utils.dart';
import '../widgets/dialogo_revisao_variante.dart';
import 'adicionar_imagens_lote_screen.dart';
import 'checklist_estoque_screen.dart' show diasParaVencer, formatarValidade;
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
    _tabController = TabController(length: 8, vsync: this);
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
    final revisarPreco = produtoProvider.produtos.where((p) => p.revisarPreco && !_ehPlaceholderInterno(p)).length;
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
            const Tab(text: 'Estoque parado'),
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
          _AbaEstoqueParado(),
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

/// Placeholders internos de marketplace (sku `__IFOOD_NAO_CATALOGADO__`,
/// `__99FOOD_NAO_CATALOGADO__`) — custo 0, não são produto de verdade, não
/// fazem sentido na revisão de preço.
bool _ehPlaceholderInterno(Produto p) {
  final sku = p.sku ?? '';
  return sku.startsWith('__') && sku.endsWith('_NAO_CATALOGADO__');
}

enum _ModoPreco { sugestao, markup, categoria }

enum _Arredondamento { nenhum, finalNove, noventa }

enum _FiltroDirecaoCusto { todos, subiu, caiu }

enum _OrdemRevisao { margemPerdida, maisVendidos, nome }

/// Arredonda PRA CIMA — nunca abaixo do preço calculado (senão arredondar
/// comeria parte da margem que a conta pediu). "Final 9" (padrão) sobe no
/// máximo 10 centavos (3,35 → 3,39); ",90" pode subir quase R$ 1, o que em
/// produto barato distorce a sugestão (achado testando: Pedigree com custo
/// que CAIU, sugestão 3,35 virava 3,90, acima do preço atual 3,49).
double _arredondar(double preco, _Arredondamento modo) {
  double centavos(double v) => (v * 100).roundToDouble() / 100;
  switch (modo) {
    case _Arredondamento.nenhum:
      return centavos(preco);
    case _Arredondamento.finalNove:
      var candidato = (preco * 10 + 0.0001).floorToDouble() / 10 + 0.09;
      if (candidato + 0.0001 < preco) candidato += 0.10;
      return centavos(candidato);
    case _Arredondamento.noventa:
      var candidato = preco.floorToDouble() + 0.90;
      if (candidato + 0.0001 < preco) candidato += 1;
      return centavos(candidato);
  }
}

String _pct(double valor) => '${valor >= 0 ? '+' : ''}${valor.toStringAsFixed(1).replaceAll('.', ',')}%';

String _moedaRevisao(double valor) => 'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}';

class _AbaRevisarPreco extends StatefulWidget {
  const _AbaRevisarPreco();

  @override
  State<_AbaRevisarPreco> createState() => _AbaRevisarPrecoState();
}

class _AbaRevisarPrecoState extends State<_AbaRevisarPreco> {
  final Set<String> _selecionados = {};
  final _markupController = TextEditingController();
  final _repository = RevisaoPrecoRepository();
  bool _processando = false;
  String _busca = '';
  String? _filtroCategoria;
  _FiltroDirecaoCusto _filtroDirecao = _FiltroDirecaoCusto.todos;
  _OrdemRevisao _ordem = _OrdemRevisao.margemPerdida;
  _ModoPreco _modo = _ModoPreco.sugestao;
  _Arredondamento _arredondamento = _Arredondamento.finalNove;
  bool _aplicarNoIfood = true;
  Map<String, RevisaoPrecoContexto> _contexto = {};
  bool _carregandoContexto = true;

  @override
  void initState() {
    super.initState();
    _carregarContexto();
  }

  @override
  void dispose() {
    _markupController.dispose();
    super.dispose();
  }

  Future<void> _carregarContexto() async {
    try {
      final contexto = await _repository.carregar();
      if (mounted) setState(() => _contexto = contexto);
    } catch (e) {
      debugPrint('Erro ao carregar contexto de revisão de preço: $e');
    } finally {
      if (mounted) setState(() => _carregandoContexto = false);
    }
  }

  double? _markupAtual(Produto p) => p.custo > 0 && p.preco > 0 ? (p.preco / p.custo - 1) * 100 : null;

  /// Pontos percentuais de markup perdidos desde a mudança de custo — chave
  /// da ordenação padrão (pior primeiro). Custo que caiu dá valor negativo.
  double _margemPerdida(Produto p) {
    final antes = _contexto[p.id]?.markupAnterior;
    final agora = _markupAtual(p);
    if (antes == null || agora == null) return 0;
    return antes - agora;
  }

  /// Preço novo pelo modo escolhido na barra — null quando não dá pra
  /// calcular (sem histórico, sem custo, markup inválido): esse produto é
  /// pulado e aparece como "sem cálculo" na prévia, nunca vira preço 0.
  double? _precoNovo(Produto p) {
    if (p.custo <= 0) return null;
    double? bruto;
    switch (_modo) {
      case _ModoPreco.sugestao:
        bruto = _contexto[p.id]?.precoSugerido(p.custo);
      case _ModoPreco.markup:
        final markup = ProdutoValidators.parseNumero(_markupController.text);
        if (markup == null || markup < 0) return null;
        bruto = p.custo * (1 + markup / 100);
      case _ModoPreco.categoria:
        final markup = _contexto[p.id]?.markupCategoria;
        if (markup == null) return null;
        bruto = p.custo * (1 + markup / 100);
    }
    if (bruto == null || bruto <= 0) return null;
    return _arredondar(bruto, _arredondamento);
  }

  Future<void> _marcarComoRevisado(ProdutoProvider provider) async {
    setState(() => _processando = true);
    await provider.marcarPrecoRevisadoEmMassa(_selecionados.toList());
    if (!mounted) return;
    setState(() {
      _processando = false;
      _selecionados.clear();
    });
    _carregarContexto();
  }

  /// Ajuste fino de 1 produto: digita preço (ou markup) da loja e do iFood
  /// com a conta ao vivo. Salvar sempre tira o produto da revisão — com
  /// preço da loja novo via `aplicarPrecoRevisadoEmMassa`, sem mudança nele
  /// via `marcarPrecoRevisadoEmMassa` (mantém o preço, dá como revisado).
  Future<void> _editarManual(Produto p, ProdutoProvider provider, {double? sugestaoSite, double? sugestaoIfood}) async {
    final ctx = _contexto[p.id];
    final resultado = await showDialog<({double loja, double? ifood})>(
      context: context,
      builder: (_) => _DialogoEditarPrecoRevisao(
        produto: p,
        contexto: ctx,
        precoLojaInicial: sugestaoSite ?? p.preco,
        precoIfoodInicial: sugestaoIfood ?? ctx?.precoIfood,
      ),
    );
    if (resultado == null || !mounted) return;

    final id = p.id!;
    final lojaMudou = (resultado.loja - p.preco).abs() >= 0.01;
    final novoIfood = resultado.ifood;
    final ifoodMudou = novoIfood != null &&
        ctx?.ifoodMarketplaceId != null &&
        (ctx?.precoIfood == null || (novoIfood - ctx!.precoIfood!).abs() >= 0.01);

    if (lojaMudou || ifoodMudou) {
      await _aplicar(
        provider,
        precoSitePorId: lojaMudou ? {id: resultado.loja} : const {},
        precoIfoodPorId: ifoodMudou ? {id: (marketplaceId: ctx!.ifoodMarketplaceId!, preco: novoIfood)} : const {},
      );
    }
    if (!lojaMudou && mounted) {
      await provider.marcarPrecoRevisadoEmMassa([id]);
      if (!mounted) return;
      setState(() => _selecionados.remove(id));
      if (!ifoodMudou) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Preço mantido — produto marcado como revisado.')));
      }
      _carregarContexto();
    }
  }

  String _linhaPreviaIfood(Produto p, double? novoIfood) {
    if (novoIfood == null) return '';
    final atual = _contexto[p.id]?.precoIfood;
    return '\niFood ${atual != null ? _moedaRevisao(atual) : '—'} → ${_moedaRevisao(novoIfood)}';
  }

  String _textoTaxaIfood() {
    final taxa = _contexto.values.map((c) => c.taxaIfoodPercentual).whereType<double>().firstOrNull;
    if (taxa == null) return 'Sem taxa do iFood configurada (Custos Operacionais) — não dá pra calcular.';
    return 'Mesmo líquido da loja depois de ${taxa.toStringAsFixed(1).replaceAll('.', ',')}% de taxas do iFood '
        '(comissão + pagamento online).';
  }

  /// Preço do iFood que deixa o mesmo líquido que [precoSite] na loja,
  /// arredondado do mesmo jeito. Null = sem canal iFood ou sem taxa vigente.
  double? _precoIfoodPara(Produto p, double precoSite) {
    final equivalente = _contexto[p.id]?.precoIfoodEquivalente(precoSite);
    return equivalente == null ? null : _arredondar(equivalente, _arredondamento);
  }

  /// [precoSitePorId] e [precoIfoodPorId] são independentes: o botão do
  /// cartão aplica só um dos dois; a barra em massa aplica os dois juntos.
  /// Só mexe no preço do site — `aplicarPrecoRevisadoEmMassa` também tira o
  /// produto da revisão; aplicar só no iFood deixa ele pendente.
  Future<void> _aplicar(
    ProdutoProvider provider, {
    Map<String, double> precoSitePorId = const {},
    Map<String, ({String marketplaceId, double preco})> precoIfoodPorId = const {},
  }) async {
    if (precoSitePorId.isEmpty && precoIfoodPorId.isEmpty) return;
    setState(() => _processando = true);
    final falhasSite =
        precoSitePorId.isEmpty ? <String>[] : await provider.aplicarPrecoRevisadoEmMassa(precoSitePorId);
    final falhasIfood =
        precoIfoodPorId.isEmpty ? <String>[] : await provider.aplicarPrecoIfoodEmMassa(precoIfoodPorId);
    if (!mounted) return;
    setState(() {
      _processando = false;
      _selecionados.removeAll(precoSitePorId.keys.where((id) => !falhasSite.contains(id)));
    });
    final partes = [
      if (precoSitePorId.isNotEmpty)
        'loja em ${precoSitePorId.length - falhasSite.length} de ${precoSitePorId.length}'
            '${falhasSite.isNotEmpty ? ' (${falhasSite.length} falharam)' : ''}',
      if (precoIfoodPorId.isNotEmpty)
        'iFood em ${precoIfoodPorId.length - falhasIfood.length} de ${precoIfoodPorId.length}'
            '${falhasIfood.isNotEmpty ? ' (${falhasIfood.length} falharam)' : ''}',
    ];
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Preço aplicado: ${partes.join(' · ')}.')));
    _carregarContexto();
  }

  /// Prévia obrigatória antes de aplicar em massa: de → para de cada
  /// selecionado, e quem ficou sem cálculo (não é alterado).
  Future<void> _previaEAplicar(List<Produto> lista, ProdutoProvider provider) async {
    if (_modo == _ModoPreco.markup) {
      final markup = ProdutoValidators.parseNumero(_markupController.text);
      if (markup == null || markup < 0) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Informe um markup válido (ex: 45 = preço 45% acima do custo).')));
        return;
      }
    }
    final selecionados = lista.where((p) => _selecionados.contains(p.id)).toList();
    final precoPorId = <String, double>{};
    final precoIfoodPorId = <String, ({String marketplaceId, double preco})>{};
    final semCalculo = <Produto>[];
    for (final p in selecionados) {
      final novo = _precoNovo(p);
      if (novo == null) {
        semCalculo.add(p);
        continue;
      }
      precoPorId[p.id!] = novo;
      final ctx = _contexto[p.id];
      final ifood = _aplicarNoIfood ? _precoIfoodPara(p, novo) : null;
      if (ifood != null && ctx?.ifoodMarketplaceId != null) {
        precoIfoodPorId[p.id!] = (marketplaceId: ctx!.ifoodMarketplaceId!, preco: ifood);
      }
    }

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Aplicar preço em ${precoPorId.length} produto(s)?'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final p in selecionados.where((p) => precoPorId.containsKey(p.id)))
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(p.nome, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    'Loja ${_moedaRevisao(p.preco)} → ${_moedaRevisao(precoPorId[p.id]!)}'
                    '  (markup ${(precoPorId[p.id]! / p.custo * 100 - 100).toStringAsFixed(0)}%)'
                    '${_linhaPreviaIfood(p, precoIfoodPorId[p.id]?.preco)}',
                  ),
                ),
              if (semCalculo.isNotEmpty) ...[
                const Divider(),
                Text(
                  '${semCalculo.length} sem cálculo possível (sem custo, sem histórico ou sem dado da categoria) — '
                  'não serão alterados: ${semCalculo.map((p) => p.nome).take(3).join('; ')}'
                  '${semCalculo.length > 3 ? '…' : ''}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            onPressed: precoPorId.isEmpty ? null : () => Navigator.pop(context, true),
            child: const Text('Aplicar'),
          ),
        ],
      ),
    );
    if (confirmado == true && mounted) {
      await _aplicar(provider, precoSitePorId: precoPorId, precoIfoodPorId: precoIfoodPorId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final produtoProvider = context.watch<ProdutoProvider>();
    final pendentes =
        produtoProvider.produtos.where((p) => p.revisarPreco && !_ehPlaceholderInterno(p)).toList();
    final contagemPorCategoria = <String, int>{};
    for (final p in pendentes) {
      final cat = p.categoria.isNotEmpty ? p.categoria : 'Sem categoria';
      contagemPorCategoria[cat] = (contagemPorCategoria[cat] ?? 0) + 1;
    }

    bool direcaoConfere(Produto p) {
      if (_filtroDirecao == _FiltroDirecaoCusto.todos) return true;
      final anterior = _contexto[p.id]?.custoAnterior;
      if (anterior == null) return false;
      return _filtroDirecao == _FiltroDirecaoCusto.subiu ? p.custo > anterior : p.custo < anterior;
    }

    final lista = pendentes
        .where((p) => contemTodasPalavras(p.nome, _busca))
        .where((p) => _filtroCategoria == null ||
            (p.categoria.isNotEmpty ? p.categoria : 'Sem categoria') == _filtroCategoria)
        .where(direcaoConfere)
        .toList();
    switch (_ordem) {
      case _OrdemRevisao.margemPerdida:
        lista.sort((a, b) => _margemPerdida(b).compareTo(_margemPerdida(a)));
      case _OrdemRevisao.maisVendidos:
        lista.sort((a, b) => (_contexto[b.id]?.vendas60d ?? 0).compareTo(_contexto[a.id]?.vendas60d ?? 0));
      case _OrdemRevisao.nome:
        lista.sort((a, b) => a.nome.compareTo(b.nome));
    }
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                for (final (filtro, rotulo) in [
                  (_FiltroDirecaoCusto.todos, 'Todos'),
                  (_FiltroDirecaoCusto.subiu, 'Custo subiu'),
                  (_FiltroDirecaoCusto.caiu, 'Custo caiu'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(rotulo),
                      selected: _filtroDirecao == filtro,
                      onSelected: (_) => setState(() => _filtroDirecao = filtro),
                    ),
                  ),
                const SizedBox(width: 8),
                DropdownButton<_OrdemRevisao>(
                  value: _ordem,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: _OrdemRevisao.margemPerdida, child: Text('Mais margem perdida')),
                    DropdownMenuItem(value: _OrdemRevisao.maisVendidos, child: Text('Mais vendidos (60d)')),
                    DropdownMenuItem(value: _OrdemRevisao.nome, child: Text('Nome')),
                  ],
                  onChanged: (v) => setState(() => _ordem = v ?? _ordem),
                ),
              ],
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
                if (_carregandoContexto) ...[
                  const Spacer(),
                  const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
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
                  padding: const EdgeInsets.only(bottom: 260),
                  itemCount: lista.length,
                  itemBuilder: (context, index) {
                    final produto = lista[index];
                    final id = produto.id!;
                    final ctx = _contexto[id];
                    final sugestaoSite = ctx?.precoSugerido(produto.custo) != null
                        ? _arredondar(ctx!.precoSugerido(produto.custo)!, _arredondamento)
                        : null;
                    // iFood acompanha a sugestão da loja; sem sugestão (sem
                    // histórico), acompanha o preço atual da loja.
                    final sugestaoIfood = _precoIfoodPara(produto, sugestaoSite ?? produto.preco);
                    return _CartaoRevisaoPreco(
                      produto: produto,
                      contexto: ctx,
                      selecionado: _selecionados.contains(id),
                      sugestaoArredondada: sugestaoSite,
                      sugestaoIfood: sugestaoIfood,
                      sugestaoIfoodBaseadaNaSugestao: sugestaoSite != null,
                      onSelecionar: (v) => setState(() {
                        if (v) {
                          _selecionados.add(id);
                        } else {
                          _selecionados.remove(id);
                        }
                      }),
                      onAplicarSugestao: _processando
                          ? null
                          : (preco) => _aplicar(produtoProvider, precoSitePorId: {id: preco}),
                      onEditar: _processando
                          ? null
                          : () => _editarManual(produto, produtoProvider,
                              sugestaoSite: sugestaoSite, sugestaoIfood: sugestaoIfood),
                      onAplicarIfood: _processando || ctx?.ifoodMarketplaceId == null
                          ? null
                          : (preco) => _aplicar(produtoProvider,
                              precoIfoodPorId: {id: (marketplaceId: ctx!.ifoodMarketplaceId!, preco: preco)}),
                    );
                  },
                ),
        ),
        if (_selecionados.isNotEmpty) _barraAcoes(lista, produtoProvider),
      ],
    );
  }

  Widget _barraAcoes(List<Produto> lista, ProdutoProvider produtoProvider) {
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
            Text('${_selecionados.length} selecionado(s)', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<_ModoPreco>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: _ModoPreco.sugestao, label: Text('Margem anterior')),
                ButtonSegment(value: _ModoPreco.markup, label: Text('Markup %')),
                ButtonSegment(value: _ModoPreco.categoria, label: Text('Da categoria')),
              ],
              selected: {_modo},
              onSelectionChanged: (s) => setState(() => _modo = s.first),
            ),
            if (_modo == _ModoPreco.markup) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _markupController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Markup (%) sobre o custo',
                  helperText: 'Preço = custo + %. Ex: 45 → custo R\$ 10,00 vira R\$ 14,50.',
                ),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Arredondar: '),
                DropdownButton<_Arredondamento>(
                  value: _arredondamento,
                  items: const [
                    DropdownMenuItem(value: _Arredondamento.finalNove, child: Text('pra cima, final 9 (4,59)')),
                    DropdownMenuItem(value: _Arredondamento.noventa, child: Text('pra cima em ,90 (4,90)')),
                    DropdownMenuItem(value: _Arredondamento.nenhum, child: Text('não arredondar')),
                  ],
                  onChanged: (v) => setState(() => _arredondamento = v ?? _arredondamento),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _aplicarNoIfood,
              onChanged: (v) => setState(() => _aplicarNoIfood = v),
              title: const Text('Aplicar também no iFood'),
              subtitle: Text(_textoTaxaIfood()),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _processando ? null : () => _marcarComoRevisado(produtoProvider),
                    child: const Text('Manter preço atual'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _processando ? null : () => _previaEAplicar(lista, produtoProvider),
                    child: _processando
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Ver prévia e aplicar'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CartaoRevisaoPreco extends StatelessWidget {
  final Produto produto;
  final RevisaoPrecoContexto? contexto;
  final bool selecionado;
  final double? sugestaoArredondada;
  final double? sugestaoIfood;
  final bool sugestaoIfoodBaseadaNaSugestao;
  final ValueChanged<bool> onSelecionar;
  final ValueChanged<double>? onAplicarSugestao;
  final ValueChanged<double>? onAplicarIfood;
  final VoidCallback? onEditar;

  const _CartaoRevisaoPreco({
    required this.produto,
    required this.contexto,
    required this.selecionado,
    required this.sugestaoArredondada,
    required this.sugestaoIfood,
    required this.sugestaoIfoodBaseadaNaSugestao,
    required this.onSelecionar,
    required this.onAplicarSugestao,
    required this.onAplicarIfood,
    required this.onEditar,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final estiloLinha = Theme.of(context).textTheme.bodySmall;
    final ctx = contexto;
    final custoAnterior = ctx?.custoAnterior;
    final variacaoCusto = custoAnterior != null && custoAnterior > 0 ? (produto.custo / custoAnterior - 1) * 100 : null;
    final subiu = variacaoCusto != null && variacaoCusto > 0;
    final markupAtual = produto.custo > 0 && produto.preco > 0 ? (produto.preco / produto.custo - 1) * 100 : null;
    final markupAnterior = ctx?.markupAnterior;
    final markupCategoria = ctx?.markupCategoria;
    final precoIfood = ctx?.precoIfood;
    // "Abaixo do custo" no iFood olha o LÍQUIDO (depois das taxas %), não o
    // preço de vitrine — é o que de fato entra no caixa.
    final liquidoIfood = precoIfood != null ? (ctx?.liquidoIfood(precoIfood) ?? precoIfood) : null;
    final ifoodAbaixoDoCusto = liquidoIfood != null && precoIfood! > 0 && liquidoIfood <= produto.custo;
    final markupLiquidoIfood =
        liquidoIfood != null && produto.custo > 0 && ctx?.taxaIfoodPercentual != null
            ? (liquidoIfood / produto.custo - 1) * 100
            : null;
    final abaixoDoCusto = produto.preco <= produto.custo;
    final dataCusto = ctx?.custoAlteradoEm;

    final corAlerta = colorScheme.error;
    final corMarkup = markupAtual == null
        ? null
        : (markupAnterior != null && markupAtual < markupAnterior - 0.5)
            ? corAlerta
            : null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        onTap: () => onSelecionar(!selecionado),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(value: selecionado, onChanged: (v) => onSelecionar(v ?? false)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(produto.nome,
                              maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                        if (variacaoCusto != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(
                              '${subiu ? '▲' : '▼'} custo ${_pct(variacaoCusto)}',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: subiu ? corAlerta : Colors.green.shade700),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      custoAnterior != null
                          ? 'Custo ${_moedaRevisao(custoAnterior)} → ${_moedaRevisao(produto.custo)}'
                              '${dataCusto != null ? '  (em ${DateFormat('dd/MM').format(dataCusto.toLocal())})' : ''}'
                          : 'Custo ${_moedaRevisao(produto.custo)} (sem histórico da mudança)',
                      style: estiloLinha,
                    ),
                    Text.rich(
                      TextSpan(style: estiloLinha, children: [
                        TextSpan(text: 'Preço ${_moedaRevisao(produto.preco)}'),
                        if (abaixoDoCusto)
                          TextSpan(text: '  ABAIXO DO CUSTO', style: TextStyle(color: corAlerta, fontWeight: FontWeight.bold)),
                        if (markupAtual != null)
                          TextSpan(text: ' · Markup ${markupAtual.toStringAsFixed(0)}%', style: TextStyle(color: corMarkup)),
                        if (markupAnterior != null) TextSpan(text: ' (antes ${markupAnterior.toStringAsFixed(0)}%)'),
                        if (markupCategoria != null) TextSpan(text: ' · categoria ${markupCategoria.toStringAsFixed(0)}%'),
                      ]),
                    ),
                    Text.rich(
                      TextSpan(style: estiloLinha, children: [
                        if (precoIfood != null)
                          TextSpan(
                            text: 'iFood ${_moedaRevisao(precoIfood)}'
                                '${markupLiquidoIfood != null ? ' (líquido ${_moedaRevisao(liquidoIfood!)}, markup ${markupLiquidoIfood.toStringAsFixed(0)}%)' : ''}'
                                '${ifoodAbaixoDoCusto ? ' ABAIXO DO CUSTO' : ''} · ',
                            style: ifoodAbaixoDoCusto ? TextStyle(color: corAlerta, fontWeight: FontWeight.bold) : null,
                          ),
                        TextSpan(text: 'Vendas 60d: ${ctx?.vendas60d ?? '—'} · Estoque: ${produto.estoqueAtual}'),
                      ]),
                    ),
                    if (sugestaoArredondada != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Sugestão: ${_moedaRevisao(sugestaoArredondada!)} (mantém a margem anterior)',
                              style: estiloLinha?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.w600),
                            ),
                          ),
                          if ((sugestaoArredondada! - produto.preco).abs() >= 0.01)
                            TextButton(
                              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                              onPressed: onAplicarSugestao == null ? null : () => onAplicarSugestao!(sugestaoArredondada!),
                              child: const Text('Aplicar'),
                            ),
                        ],
                      ),
                    ],
                    if (sugestaoIfood != null)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Sugestão iFood: ${_moedaRevisao(sugestaoIfood!)} '
                              '(mesmo líquido ${sugestaoIfoodBaseadaNaSugestao ? 'da sugestão' : 'do preço atual'} da loja)',
                              style: estiloLinha?.copyWith(color: colorScheme.tertiary, fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (precoIfood == null || (sugestaoIfood! - precoIfood).abs() >= 0.01)
                            TextButton(
                              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                              onPressed: onAplicarIfood == null ? null : () => onAplicarIfood!(sugestaoIfood!),
                              child: const Text('Aplicar iFood'),
                            ),
                        ],
                      ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Editar preço'),
                        onPressed: onEditar,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Edição manual de preço na revisão — nos dois sentidos, igual
/// `CalculadoraPrecoMarkup` da tela de produto: digitar o preço recalcula o
/// markup, digitar o markup recalcula o preço. No iFood o markup é sobre o
/// LÍQUIDO (preço − taxas % vigentes), que é o que entra no caixa.
class _DialogoEditarPrecoRevisao extends StatefulWidget {
  final Produto produto;
  final RevisaoPrecoContexto? contexto;
  final double precoLojaInicial;
  final double? precoIfoodInicial;

  const _DialogoEditarPrecoRevisao({
    required this.produto,
    required this.contexto,
    required this.precoLojaInicial,
    required this.precoIfoodInicial,
  });

  @override
  State<_DialogoEditarPrecoRevisao> createState() => _DialogoEditarPrecoRevisaoState();
}

class _DialogoEditarPrecoRevisaoState extends State<_DialogoEditarPrecoRevisao> {
  late final _precoLoja = TextEditingController(text: ProdutoValidators.formatarMoeda(widget.precoLojaInicial));
  final _markupLoja = TextEditingController();
  late final _precoIfood = TextEditingController(text: ProdutoValidators.formatarMoeda(widget.precoIfoodInicial));
  final _markupIfood = TextEditingController();
  String? _erro;

  double get _custo => widget.produto.custo;
  double? get _taxaIfood => widget.contexto?.taxaIfoodPercentual;
  bool get _temIfood => widget.contexto?.ifoodMarketplaceId != null;

  @override
  void initState() {
    super.initState();
    _preencherMarkupLoja();
    _preencherMarkupIfood();
  }

  @override
  void dispose() {
    _precoLoja.dispose();
    _markupLoja.dispose();
    _precoIfood.dispose();
    _markupIfood.dispose();
    super.dispose();
  }

  // Os campos recíprocos são escritos só a partir de `onChanged` (que o
  // Flutter chama apenas quando o USUÁRIO digita, nunca por `controller.text
  // = ...`), então preço ⇄ markup não entram em loop.

  double _liquidoIfood(double preco) => preco * (1 - (_taxaIfood ?? 0) / 100);

  String _formatarPct(double valor) => valor.toStringAsFixed(1).replaceAll('.', ',');

  void _preencherMarkupLoja() {
    final preco = ProdutoValidators.parseNumero(_precoLoja.text);
    _markupLoja.text = preco != null && _custo > 0 ? _formatarPct((preco / _custo - 1) * 100) : '';
  }

  void _preencherMarkupIfood() {
    final preco = ProdutoValidators.parseNumero(_precoIfood.text);
    _markupIfood.text = preco != null && _custo > 0 ? _formatarPct((_liquidoIfood(preco) / _custo - 1) * 100) : '';
  }

  void _aoMudarMarkupLoja(String texto) {
    final markup = ProdutoValidators.parseNumero(texto);
    setState(() {
      if (markup != null && _custo > 0) _precoLoja.text = ProdutoValidators.formatarMoeda(_custo * (1 + markup / 100));
    });
  }

  void _aoMudarMarkupIfood(String texto) {
    final markup = ProdutoValidators.parseNumero(texto);
    final taxa = _taxaIfood ?? 0;
    setState(() {
      if (markup != null && _custo > 0 && taxa < 100) {
        _precoIfood.text = ProdutoValidators.formatarMoeda(_custo * (1 + markup / 100) / (1 - taxa / 100));
      }
    });
  }

  /// Atalho: iFood com o mesmo líquido do preço da loja digitado.
  void _igualarIfoodALoja() {
    final loja = ProdutoValidators.parseNumero(_precoLoja.text);
    final equivalente = loja != null ? widget.contexto?.precoIfoodEquivalente(loja) : null;
    if (equivalente == null) return;
    setState(() {
      _precoIfood.text = ProdutoValidators.formatarMoeda(equivalente);
      _preencherMarkupIfood();
    });
  }

  void _salvar() {
    final loja = ProdutoValidators.parseNumero(_precoLoja.text);
    if (loja == null || loja <= 0) {
      setState(() => _erro = 'Informe o preço da loja.');
      return;
    }
    double? ifood;
    if (_temIfood && _precoIfood.text.trim().isNotEmpty) {
      ifood = ProdutoValidators.parseNumero(_precoIfood.text);
      if (ifood == null || ifood <= 0) {
        setState(() => _erro = 'Preço do iFood inválido.');
        return;
      }
    }
    double centavos(double v) => (v * 100).roundToDouble() / 100;
    Navigator.of(context).pop((loja: centavos(loja), ifood: ifood == null ? null : centavos(ifood)));
  }

  @override
  Widget build(BuildContext context) {
    final estiloAjuda = TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);
    final corAlerta = Theme.of(context).colorScheme.error;
    final loja = ProdutoValidators.parseNumero(_precoLoja.text);
    final ifood = ProdutoValidators.parseNumero(_precoIfood.text);
    final markupAnterior = widget.contexto?.markupAnterior;
    final markupCategoria = widget.contexto?.markupCategoria;
    final taxa = _taxaIfood;

    Widget linhaResumo(String texto, {bool alerta = false}) =>
        Text(texto, style: alerta ? estiloAjuda.copyWith(color: corAlerta, fontWeight: FontWeight.bold) : estiloAjuda);

    String textoIfood(double preco) {
      final liquido = _liquidoIfood(preco);
      final abaixo = liquido <= _custo ? '  ABAIXO DO CUSTO' : '';
      if (taxa == null) return 'Sem taxa do iFood configurada — markup sem descontar taxas.$abaixo';
      return 'Líquido ${_moedaRevisao(liquido)} (−${_formatarPct(taxa)}% taxas) · '
          'lucro ${_moedaRevisao(liquido - _custo)}$abaixo';
    }

    return AlertDialog(
      title: const Text('Editar preço'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.produto.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              'Custo ${_moedaRevisao(_custo)}'
              '${markupAnterior != null ? ' · markup antes ${markupAnterior.toStringAsFixed(0)}%' : ''}'
              '${markupCategoria != null ? ' · categoria ${markupCategoria.toStringAsFixed(0)}%' : ''}',
              style: estiloAjuda,
            ),
            const SizedBox(height: 12),
            const Text('Loja', style: TextStyle(fontWeight: FontWeight.w600)),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _precoLoja,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Preço (R\$)'),
                    onChanged: (_) => setState(_preencherMarkupLoja),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _markupLoja,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                    decoration: const InputDecoration(labelText: 'Markup (%)'),
                    onChanged: _aoMudarMarkupLoja,
                  ),
                ),
              ],
            ),
            if (loja != null)
              linhaResumo(
                'Lucro por unidade: ${_moedaRevisao(loja - _custo)}${loja <= _custo ? '  ABAIXO DO CUSTO' : ''}',
                alerta: loja <= _custo,
              ),
            if (_temIfood) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(child: Text('iFood', style: TextStyle(fontWeight: FontWeight.w600))),
                  if (taxa != null)
                    TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      onPressed: _igualarIfoodALoja,
                      child: const Text('Mesmo líquido da loja'),
                    ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _precoIfood,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Preço (R\$)'),
                      onChanged: (_) => setState(_preencherMarkupIfood),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _markupIfood,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      decoration: const InputDecoration(labelText: 'Markup líquido (%)'),
                      onChanged: _aoMudarMarkupIfood,
                    ),
                  ),
                ],
              ),
              if (ifood != null) linhaResumo(textoIfood(ifood), alerta: _liquidoIfood(ifood) <= _custo),
            ],
            const SizedBox(height: 12),
            Text('Salvar grava os preços e tira o produto da revisão.', style: estiloAjuda),
            if (_erro != null) ...[
              const SizedBox(height: 8),
              Text(_erro!, style: TextStyle(color: corAlerta)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _salvar, child: const Text('Salvar')),
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

/// ---------------------------------------------------------------------
/// Aba: Estoque parado — produtos com estoque e sem venda há mais de 90
/// dias (RPC `produtos_estoque_parado`), ordenados pelo dinheiro parado.
/// Ações: promoção em % (nunca abaixo do custo), destaque no site e
/// contagem física por produto (vai pro histórico de estoque como
/// "contagem") — a contagem vem primeiro porque parte desse saldo pode nem
/// existir na prateleira (caso real da Golden 3kg, 01/10).
/// ---------------------------------------------------------------------
class _AbaEstoqueParado extends StatefulWidget {
  const _AbaEstoqueParado();

  @override
  State<_AbaEstoqueParado> createState() => _AbaEstoqueParadoState();
}

class _AbaEstoqueParadoState extends State<_AbaEstoqueParado> {
  static final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  static final _data = DateFormat('dd/MM/yy');

  List<EstoqueParado>? _itens;
  String? _erro;
  final Set<String> _selecionados = {};
  String _busca = '';
  String? _filtroFaixa;
  String? _filtroCategoria;
  String? _filtroValidade;
  String? _filtroSugestao;
  bool _processando = false;

  /// Do checklist de estoque. Produto ausente = validade nunca conferida;
  /// valor null = conferido sem validade (ex: acessório).
  Map<String, DateTime?> _validades = {};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  String _faixaValidade(String produtoId) {
    if (!_validades.containsKey(produtoId)) return 'Não conferida';
    final v = _validades[produtoId];
    if (v == null) return 'Sem validade';
    final dias = diasParaVencer(v);
    if (dias < 0) return 'Vencido';
    if (dias <= 90) return 'Vence em até 90 dias';
    return 'Mais de 90 dias';
  }

  Future<void> _carregar() async {
    setState(() => _erro = null);
    try {
      final resultados = await Future.wait([
        ProdutoRepository().listarEstoqueParado(),
        ChecklistEstoqueRepository().listarValidades(),
      ]);
      if (!mounted) return;
      setState(() {
        _itens = resultados[0] as List<EstoqueParado>;
        _validades = resultados[1] as Map<String, DateTime?>;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = 'Erro ao carregar estoque parado: $e');
    }
  }

  EstoqueParado? _item(String? produtoId) => _itens?.where((i) => i.produtoId == produtoId).firstOrNull;

  ({SugestaoEstoqueParado sugestao, String motivo}) _sugestao(EstoqueParado item) {
    final validade = _validades[item.produtoId];
    return sugerirAcaoEstoqueParado(item, diasValidade: validade != null ? diasParaVencer(validade) : null);
  }

  /// Menor promocional sem prejuízo. O mesmo promocional vai pro iFood (a
  /// exportação do catálogo usa ele quando é menor que o preço do iFood), e
  /// lá a taxa sai do valor cheio — então o piso é custo + taxa do iFood,
  /// não só o custo.
  double _pisoPromocao(Produto p) {
    final item = _item(p.id);
    if (p.custo <= 0) return 0;
    if (item == null || item.precoIfood == null) return p.custo;
    return (item.precoMinimoIfood(p.custo) * 100).ceilToDouble() / 100;
  }

  /// Promoção = preço × (1 − %), arredondado, com piso em [_pisoPromocao].
  /// Produto cujo preço já está no piso (ou sem preço) fica de fora.
  Map<String, double> _calcularPromocao(List<Produto> produtos, double percentual) {
    final resultado = <String, double>{};
    for (final p in produtos) {
      if (p.id == null || p.preco <= 0) continue;
      final comDesconto = double.parse((p.preco * (1 - percentual / 100)).toStringAsFixed(2));
      final piso = _pisoPromocao(p);
      final promocional = comDesconto < piso ? piso : comDesconto;
      if (promocional >= p.preco) continue;
      resultado[p.id!] = promocional;
    }
    return resultado;
  }

  Future<void> _aplicarPromocao(List<Produto> selecionados, ProdutoProvider provider) async {
    final percentual = await showDialog<double>(
      context: context,
      builder: (_) => _DialogoPromocaoEstoqueParado(
        produtos: selecionados,
        calcular: _calcularPromocao,
        piso: _pisoPromocao,
      ),
    );
    if (percentual == null || !mounted) return;
    final promocoes = _calcularPromocao(selecionados, percentual);
    setState(() => _processando = true);
    final falhas = await provider.aplicarPrecoPromocionalEmMassa(promocoes);
    // Fica no histórico do produto pra medir se a promoção vendeu.
    final pct = percentual.toStringAsFixed(percentual % 1 == 0 ? 0 : 1);
    try {
      await Future.wait([
        for (final e in promocoes.entries)
          if (!falhas.contains(e.key))
            ProdutoRepository().registrarAcaoEstoqueParado(
              produtoId: e.key,
              acao: 'Promoção',
              detalhe: '$pct% → ${_moeda.format(e.value)}',
              quantidade: _item(e.key)?.quantidade,
              preco: e.value,
            ),
      ]);
    } catch (e) {
      debugPrint('Erro ao registrar ação de promoção: $e');
    }
    if (!mounted) return;
    setState(() {
      _processando = false;
      _selecionados.removeAll(promocoes.keys.where((id) => !falhas.contains(id)));
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(falhas.isEmpty
          ? 'Promoção aplicada em ${promocoes.length} produto(s).'
          : 'Promoção aplicada em ${promocoes.length - falhas.length}; ${falhas.length} falharam.'),
    ));
    await _carregar();
  }

  Future<void> _registrarAcao(Produto produto, EstoqueParado item) async {
    final resultado = await showDialog<({String acao, String? detalhe})>(
      context: context,
      builder: (_) => const _DialogoRegistrarAcao(),
    );
    if (resultado == null || !mounted) return;
    try {
      await ProdutoRepository().registrarAcaoEstoqueParado(
        produtoId: item.produtoId,
        acao: resultado.acao,
        detalhe: resultado.detalhe,
        quantidade: item.quantidade,
        preco: produto.precoPromocional ?? produto.preco,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${resultado.acao}" registrada — a análise mostra quanto vendeu desde então.')),
      );
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível registrar: $e')));
    }
  }

  Future<void> _abrirClientes(Produto produto, EstoqueParado item) async {
    final avisados = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ClientesQueCompraramSheet(
        produto: produto,
        nomeLoja: context.read<BrandingProvider>().nomeEmpresa,
      ),
    );
    if (avisados == null || avisados == 0 || !mounted) return;
    try {
      await ProdutoRepository().registrarAcaoEstoqueParado(
        produtoId: item.produtoId,
        acao: 'Avisei clientes',
        detalhe: '$avisados cliente(s) no WhatsApp',
        quantidade: item.quantidade,
        preco: produto.precoPromocional ?? produto.preco,
      );
    } catch (e) {
      debugPrint('Erro ao registrar aviso a clientes: $e');
    }
    await _carregar();
  }

  void _abrirDetalhes(Produto produto, EstoqueParado item, ProdutoProvider provider) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _DetalhesEstoqueParado(
        produto: produto,
        item: item,
        sugestao: _sugestao(item),
        validade: _validades[item.produtoId],
        validadeConferida: _validades.containsKey(item.produtoId),
        onContagem: () {
          Navigator.pop(sheetContext);
          _contagemFisica(produto, item, provider);
        },
        onRegistrarAcao: () {
          Navigator.pop(sheetContext);
          _registrarAcao(produto, item);
        },
        onClientes: () {
          Navigator.pop(sheetContext);
          _abrirClientes(produto, item);
        },
      ),
    );
  }

  Future<void> _removerPromocao(List<Produto> selecionados, ProdutoProvider provider) async {
    final comPromocao = <String, double?>{
      for (final p in selecionados)
        if (p.id != null && p.precoPromocional != null) p.id!: null,
    };
    if (comPromocao.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Nenhum dos selecionados está em promoção.')));
      return;
    }
    setState(() => _processando = true);
    final falhas = await provider.aplicarPrecoPromocionalEmMassa(comPromocao);
    if (!mounted) return;
    setState(() => _processando = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Promoção removida de ${comPromocao.length - falhas.length} produto(s).'),
    ));
  }

  Future<void> _destacar(bool destacar, ProdutoProvider provider) async {
    setState(() => _processando = true);
    await provider.atualizarDestaqueEmMassa(_selecionados.toList(), destacar);
    if (!mounted) return;
    setState(() => _processando = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(destacar ? 'Produtos destacados no site.' : 'Destaque removido.'),
    ));
  }

  Future<void> _contagemFisica(Produto produto, EstoqueParado item, ProdutoProvider provider) async {
    final contado = await showDialog<int>(
      context: context,
      builder: (_) => _DialogoContagemFisica(nome: produto.nome, quantidadeSistema: item.quantidade),
    );
    if (contado == null || !mounted) return;
    try {
      await provider.ajustarEstoque(
        produtoId: item.produtoId,
        quantidadeNova: contado,
        motivo: 'contagem',
        quantidadeEsperada: item.quantidade,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(contado == item.quantidade
            ? 'Contagem confere com o sistema (${item.quantidade}).'
            : 'Estoque ajustado de ${item.quantidade} para $contado (registrado no histórico).'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível ajustar: $e')));
    }
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final produtoProvider = context.watch<ProdutoProvider>();
    if (_erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(_erro!, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _carregar, child: const Text('Tentar de novo')),
          ]),
        ),
      );
    }
    final itens = _itens;
    if (itens == null) return const Center(child: CircularProgressIndicator());

    final porId = {for (final p in produtoProvider.produtos) if (p.id != null) p.id!: p};
    final pares = [
      for (final item in itens)
        if (porId[item.produtoId] != null) (item: item, produto: porId[item.produtoId]!, sugestao: _sugestao(item)),
    ];
    final contagemPorSugestao = <String, int>{};
    final contagemPorFaixa = <String, int>{};
    final contagemPorCategoria = <String, int>{};
    final contagemPorValidade = <String, int>{};
    for (final par in pares) {
      final rotulo = par.sugestao.sugestao.rotulo;
      contagemPorSugestao[rotulo] = (contagemPorSugestao[rotulo] ?? 0) + 1;
      contagemPorFaixa[par.item.faixa] = (contagemPorFaixa[par.item.faixa] ?? 0) + 1;
      final fv = _faixaValidade(par.item.produtoId);
      contagemPorValidade[fv] = (contagemPorValidade[fv] ?? 0) + 1;
      final cat = par.produto.categoria.isNotEmpty ? par.produto.categoria : 'Sem categoria';
      contagemPorCategoria[cat] = (contagemPorCategoria[cat] ?? 0) + 1;
    }
    final lista = pares
        .where((par) => contemTodasPalavras(par.produto.nome, _busca))
        .where((par) => _filtroFaixa == null || par.item.faixa == _filtroFaixa)
        .where((par) => _filtroSugestao == null || par.sugestao.sugestao.rotulo == _filtroSugestao)
        .where((par) => _filtroValidade == null || _faixaValidade(par.item.produtoId) == _filtroValidade)
        .where((par) =>
            _filtroCategoria == null ||
            (par.produto.categoria.isNotEmpty ? par.produto.categoria : 'Sem categoria') == _filtroCategoria)
        .toList();
    final idsValidos = lista.map((par) => par.item.produtoId).toSet();
    _selecionados.removeWhere((id) => !idsValidos.contains(id));
    final capitalTotal = lista.fold<double>(0, (soma, par) => soma + par.item.capital);
    final selecionados = [
      for (final par in lista)
        if (_selecionados.contains(par.item.produtoId)) par.produto,
    ];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '${lista.length} produto(s) sem venda há mais de 90 dias\n'
                      '${_moeda.format(capitalTotal)} parados (a preço de custo)',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
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
                label: 'Sugestão',
                valor: _filtroSugestao,
                contagemPorValor: contagemPorSugestao,
                onChanged: (v) => setState(() => _filtroSugestao = v),
              ),
              _FiltroPorValor(
                label: 'Tempo parado',
                valor: _filtroFaixa,
                contagemPorValor: contagemPorFaixa,
                onChanged: (v) => setState(() => _filtroFaixa = v),
              ),
              _FiltroPorValor(
                label: 'Categoria',
                valor: _filtroCategoria,
                contagemPorValor: contagemPorCategoria,
                onChanged: (v) => setState(() => _filtroCategoria = v),
              ),
              _FiltroPorValor(
                label: 'Validade',
                valor: _filtroValidade,
                contagemPorValor: contagemPorValidade,
                onChanged: (v) => setState(() => _filtroValidade = v),
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
          child: RefreshIndicator(
            onRefresh: _carregar,
            child: lista.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 80),
                    Center(child: Text('Nenhum produto parado com esse filtro')),
                  ])
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 24),
                    itemCount: lista.length,
                    itemBuilder: (context, index) {
                      final par = lista[index];
                      final item = par.item;
                      final produto = par.produto;
                      final ultimaVenda = item.ultimaVenda == null
                          ? 'Sem venda no histórico'
                          : 'Última venda ${_data.format(item.ultimaVenda!)} (${item.diasSemVenda} dias)';
                      final validade = _validades[item.produtoId];
                      final diasValidade = validade != null ? diasParaVencer(validade) : null;
                      final textoValidade = !_validades.containsKey(item.produtoId)
                          ? 'Validade não conferida'
                          : validade == null
                              ? 'Sem validade'
                              : diasValidade! < 0
                                  ? 'VENCIDO (${formatarValidade(validade)})'
                                  : 'Validade ${formatarValidade(validade)} ($diasValidade dias)';
                      final emPromocao = produto.precoPromocional != null && produto.precoPromocional! < produto.preco;
                      final precos = emPromocao
                          ? 'Promoção ${_moeda.format(produto.precoPromocional)} (de ${_moeda.format(produto.preco)})'
                          : 'Preço ${_moeda.format(produto.preco)} • custo ${_moeda.format(produto.custo)}';
                      return CheckboxListTile(
                        value: _selecionados.contains(item.produtoId),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selecionados.add(item.produtoId);
                          } else {
                            _selecionados.remove(item.produtoId);
                          }
                        }),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text(produto.nome, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text.rich(TextSpan(children: [
                          TextSpan(
                            text: '${item.quantidade} un. • ${_moeda.format(item.capital)} parados\n'
                                '$ultimaVenda\n'
                                '$precos${produto.destacar ? ' • destaque' : ''}\n',
                          ),
                          TextSpan(
                            text: '$textoValidade\n',
                            style: diasValidade != null && diasValidade <= 90
                                ? TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600)
                                : null,
                          ),
                          TextSpan(
                            text: par.sugestao.sugestao.rotulo,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ])),
                        isThreeLine: true,
                        secondary: IconButton(
                          tooltip: 'Detalhes e ações',
                          icon: const Icon(Icons.insights_outlined),
                          onPressed: () => _abrirDetalhes(produto, item, produtoProvider),
                        ),
                      );
                    },
                  ),
          ),
        ),
        _BarraSelecao(
          quantidade: _selecionados.length,
          acoes: [
            FilledButton.icon(
              onPressed: _processando ? null : () => _aplicarPromocao(selecionados, produtoProvider),
              icon: const Icon(Icons.sell_outlined),
              label: const Text('Promoção %'),
            ),
            OutlinedButton(
              onPressed: _processando ? null : () => _removerPromocao(selecionados, produtoProvider),
              child: const Text('Remover promoção'),
            ),
            OutlinedButton.icon(
              onPressed: _processando ? null : () => _destacar(true, produtoProvider),
              icon: const Icon(Icons.star_outline),
              label: const Text('Destacar no site'),
            ),
            OutlinedButton(
              onPressed: _processando ? null : () => _destacar(false, produtoProvider),
              child: const Text('Tirar destaque'),
            ),
          ],
        ),
      ],
    );
  }
}

/// Pede o % de desconto e mostra a prévia (quantos ficam no piso do custo,
/// quantos ficam de fora) antes de aplicar. Retorna o % confirmado.
class _DialogoPromocaoEstoqueParado extends StatefulWidget {
  final List<Produto> produtos;
  final Map<String, double> Function(List<Produto>, double) calcular;
  final double Function(Produto) piso;

  const _DialogoPromocaoEstoqueParado({required this.produtos, required this.calcular, required this.piso});

  @override
  State<_DialogoPromocaoEstoqueParado> createState() => _DialogoPromocaoEstoqueParadoState();
}

class _DialogoPromocaoEstoqueParadoState extends State<_DialogoPromocaoEstoqueParado> {
  final _controller = TextEditingController(text: '10');

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double? get _percentual {
    final v = double.tryParse(_controller.text.replaceAll(',', '.'));
    return v != null && v > 0 && v < 100 ? v : null;
  }

  @override
  Widget build(BuildContext context) {
    final percentual = _percentual;
    final promocoes = percentual == null ? <String, double>{} : widget.calcular(widget.produtos, percentual);
    final noPiso =
        widget.produtos.where((p) => p.id != null && p.custo > 0 && promocoes[p.id] == widget.piso(p)).length;
    final deFora = widget.produtos.length - promocoes.length;

    return AlertDialog(
      title: const Text('Promoção nos selecionados'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Desconto', suffixText: '%'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Text('${promocoes.length} produto(s) entram em promoção.'),
          if (noPiso > 0) Text('$noPiso ficam no preço mínimo (o desconto daria prejuízo).'),
          if (deFora > 0) Text('$deFora ficam de fora (preço já no mínimo ou sem preço).'),
          const SizedBox(height: 8),
          Text(
            'O preço normal não muda — só o promocional, que aparece riscado no site e também vai pro '
            'iFood na próxima exportação do catálogo. Por isso o mínimo é o custo + a taxa do iFood.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: percentual == null || promocoes.isEmpty ? null : () => Navigator.pop(context, percentual),
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}

/// Quantidade contada na prateleira — vai pro `ajustar_estoque` com motivo
/// "contagem". Quando confere com o sistema a RPC não grava nada (só
/// divergência vira movimentação no histórico).
class _DialogoContagemFisica extends StatefulWidget {
  final String nome;
  final int quantidadeSistema;

  const _DialogoContagemFisica({required this.nome, required this.quantidadeSistema});

  @override
  State<_DialogoContagemFisica> createState() => _DialogoContagemFisicaState();
}

class _DialogoContagemFisicaState extends State<_DialogoContagemFisica> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contado = int.tryParse(_controller.text.trim());
    return AlertDialog(
      title: const Text('Contagem física'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('No sistema: ${widget.quantidadeSistema}'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Quantidade na prateleira'),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: contado == null || contado < 0 ? null : () => Navigator.pop(context, contado),
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}


/// Tudo que ajuda a decidir o que fazer com 1 produto parado: sugestão com
/// o porquê, preço mínimo sem prejuízo por canal, compra, clientes,
/// família, sazonalidade e a última ação (com quanto vendeu depois).
class _DetalhesEstoqueParado extends StatelessWidget {
  final Produto produto;
  final EstoqueParado item;
  final ({SugestaoEstoqueParado sugestao, String motivo}) sugestao;
  final DateTime? validade;
  final bool validadeConferida;
  final VoidCallback onContagem;
  final VoidCallback onRegistrarAcao;
  final VoidCallback onClientes;

  const _DetalhesEstoqueParado({
    required this.produto,
    required this.item,
    required this.sugestao,
    required this.validade,
    required this.validadeConferida,
    required this.onContagem,
    required this.onRegistrarAcao,
    required this.onClientes,
  });

  static final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  static final _data = DateFormat('dd/MM/yy');

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final custo = produto.custo;
    final precoIfood = item.precoIfood;
    final minIfood = item.precoMinimoIfood(custo);
    String descontoMax(double preco, double minimo) =>
        preco > 0 && minimo < preco ? 'até ${((1 - minimo / preco) * 100).floor()}% de desconto' : 'sem margem pra desconto';

    Widget secao(String titulo, List<Widget> filhos) => Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: cores.primary)),
            const SizedBox(height: 4),
            ...filhos,
          ]),
        );

    final fornecedor = item.fornecedorPrincipal ?? item.ultimaCompraFornecedor;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(produto.nome, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('${item.quantidade} un. • ${_moeda.format(item.capital)} parados (a preço de custo)'),
            const SizedBox(height: 12),
            Card(
              margin: EdgeInsets.zero,
              color: cores.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(sugestao.sugestao.rotulo,
                      style: TextStyle(fontWeight: FontWeight.w700, color: cores.onPrimaryContainer)),
                  const SizedBox(height: 4),
                  Text(sugestao.motivo, style: TextStyle(color: cores.onPrimaryContainer)),
                ]),
              ),
            ),
            secao('Preço e quanto dá pra baixar', [
              Text('Loja: ${_moeda.format(produto.preco)} • mínimo ${_moeda.format(custo)} '
                  '(${descontoMax(produto.preco, custo)})'),
              if (precoIfood != null)
                Text('iFood: ${_moeda.format(precoIfood)} • mínimo ${_moeda.format(minIfood)} '
                    '(${descontoMax(precoIfood, minIfood)}, taxa ${item.taxaIfoodPct.toStringAsFixed(1)}%)'),
              if (produto.precoPromocional != null)
                Text('Em promoção agora: ${_moeda.format(produto.precoPromocional)}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
            secao('Vendas', [
              Text(item.ultimaVenda == null
                  ? 'Nenhuma venda registrada'
                  : 'Última venda ${_data.format(item.ultimaVenda!)} • ${item.vendas12m} venda(s) em 12 meses'),
              Text(item.vendasAnoPassadoProx90d > 0
                  ? 'Ano passado, nos próximos 90 dias: ${item.vendasAnoPassadoProx90d} un.'
                  : 'Ano passado, nos próximos 90 dias: nada'),
              if (item.familiaVendas90d > 0)
                Text('Família (outros tamanhos/sabores): ${item.familiaVendas90d} un. em 90 dias'
                    '${item.familiaMaisVendido != null ? ' — mais vendido: ${item.familiaMaisVendido}' : ''}'),
            ]),
            secao('Clientes', [
              Text(item.clientesCompraram == 0
                  ? 'Nenhum cliente identificado comprou (vendas só por iFood ou balcão sem cadastro)'
                  : '${item.clientesCompraram} cliente(s) já compraram • ${item.clientesComContato} com telefone'),
              if (item.clientesComContato > 0)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: onClientes,
                    icon: const Icon(Icons.chat_outlined),
                    label: const Text('Ver clientes e avisar no WhatsApp'),
                  ),
                ),
            ]),
            secao('Compra e fornecedor', [
              Text(item.ultimaCompraEm == null
                  ? 'Sem compra registrada no Gestor (entradas só desde 26/07)'
                  : 'Última compra ${_data.format(item.ultimaCompraEm!)}: '
                      '${item.ultimaCompraQtd?.toStringAsFixed(0) ?? '?'} un.'
                      '${item.ultimaCompraFornecedor != null ? ' de ${item.ultimaCompraFornecedor}' : ''}'),
              Text(fornecedor != null ? 'Fornecedor: $fornecedor' : 'Fornecedor não cadastrado'),
            ]),
            secao('Validade', [
              Text(!validadeConferida
                  ? 'Não conferida — faça o checklist de estoque'
                  : validade == null
                      ? 'Sem validade'
                      : 'Mais próxima: ${formatarValidade(validade!)} (${diasParaVencer(validade!)} dias)'),
              if (item.validadeNfe != null)
                Text('Lote da última NF-e: ${formatarValidade(item.validadeNfe!)}',
                    style: TextStyle(color: cores.onSurfaceVariant)),
            ]),
            if (item.ultimaAcao != null)
              secao('Última ação', [
                Text('${item.ultimaAcao}${item.ultimaAcaoDetalhe != null ? ' — ${item.ultimaAcaoDetalhe}' : ''}'),
                Text('Em ${_data.format(item.ultimaAcaoEm!)} • vendeu ${item.vendasDesdeAcao ?? 0} un. desde então'),
              ]),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onRegistrarAcao,
              icon: const Icon(Icons.edit_note),
              label: const Text('Registrar o que fiz'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onContagem,
              icon: const Icon(Icons.fact_check_outlined),
              label: const Text('Contagem física'),
            ),
          ],
        ),
      ),
    );
  }
}

/// O que foi feito com o produto parado. Promoção e aviso a clientes já são
/// registrados sozinhos quando feitos pela própria aba.
class _DialogoRegistrarAcao extends StatefulWidget {
  const _DialogoRegistrarAcao();

  static const acoes = [
    'Montei kit',
    'Troca/devolução com fornecedor',
    'Mudei exposição na loja',
    'Ofereci no balcão/atendimento',
    'Doação',
    'Descarte (vencido ou avariado)',
    'Parei de recomprar',
    'Outra',
  ];

  @override
  State<_DialogoRegistrarAcao> createState() => _DialogoRegistrarAcaoState();
}

class _DialogoRegistrarAcaoState extends State<_DialogoRegistrarAcao> {
  String? _acao;
  final _detalhe = TextEditingController();

  @override
  void dispose() {
    _detalhe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detalhe = _detalhe.text.trim();
    final pode = _acao != null && (_acao != 'Outra' || detalhe.isNotEmpty);
    return AlertDialog(
      title: const Text('O que você fez?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final a in _DialogoRegistrarAcao.acoes)
                ChoiceChip(label: Text(a), selected: _acao == a, onSelected: (_) => setState(() => _acao = a)),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _detalhe,
              decoration: InputDecoration(
                labelText: _acao == 'Outra' ? 'Descreva' : 'Detalhe (opcional)',
                hintText: 'Ex: kit com Golden 1kg',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 8),
            Text(
              'Doação e descarte não mexem no estoque — faça a contagem física depois pra baixar.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: pode
              ? () => Navigator.pop(context, (acao: _acao!, detalhe: detalhe.isEmpty ? null : detalhe))
              : null,
          child: const Text('Registrar'),
        ),
      ],
    );
  }
}

/// Clientes que já compraram o produto, com o WhatsApp aberto já com a
/// mensagem (quem manda revisa e envia — não é envio automático). Devolve
/// quantos foram abertos, pra registrar a ação.
class _ClientesQueCompraramSheet extends StatefulWidget {
  final Produto produto;
  final String nomeLoja;

  const _ClientesQueCompraramSheet({required this.produto, required this.nomeLoja});

  @override
  State<_ClientesQueCompraramSheet> createState() => _ClientesQueCompraramSheetState();
}

class _ClientesQueCompraramSheetState extends State<_ClientesQueCompraramSheet> {
  static final _data = DateFormat('dd/MM/yy');
  static final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  List<({String nome, String? telefone, int vezes, DateTime ultimaCompra})>? _clientes;
  String? _erro;
  final Set<int> _avisados = {};

  @override
  void initState() {
    super.initState();
    ProdutoRepository().clientesQueCompraram(widget.produto.id!).then((lista) {
      if (mounted) setState(() => _clientes = lista.where((c) => c.telefone != null).toList());
    }).catchError((Object e) {
      if (mounted) setState(() => _erro = 'Erro ao carregar clientes: $e');
    });
  }

  String _mensagem(String nome) {
    final primeiroNome = nome.trim().split(' ').first;
    final p = widget.produto;
    final emPromocao = p.precoPromocional != null && p.precoPromocional! < p.preco;
    final oferta = emPromocao
        ? ' Ele está em promoção esta semana: de ${_moeda.format(p.preco)} por ${_moeda.format(p.precoPromocional)}.'
        : '';
    return 'Oi, $primeiroNome! Aqui é da ${widget.nomeLoja}. '
        'Você já levou ${p.nome} com a gente.$oferta '
        'Quer que eu separe um pra você?';
  }

  Future<void> _abrir(int indice) async {
    final c = _clientes![indice];
    final uri = Uri.parse(linkWhatsAppComTexto(c.telefone!, _mensagem(c.nome)));
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!mounted) return;
    if (ok) {
      setState(() => _avisados.add(indice));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível abrir o WhatsApp.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final clientes = _clientes;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _avisados.length);
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Quem já comprou', style: Theme.of(context).textTheme.titleMedium),
            Text(widget.produto.nome, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Text(
              'Abre o WhatsApp com a mensagem pronta — revise e envie de lá. '
              'Avise poucos por vez; mensagem demais vira spam.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _erro != null
                  ? Center(child: Text(_erro!))
                  : clientes == null
                      ? const Center(child: CircularProgressIndicator())
                      : clientes.isEmpty
                          ? const Center(child: Text('Nenhum cliente com telefone.'))
                          : ListView.builder(
                              itemCount: clientes.length,
                              itemBuilder: (context, i) {
                                final c = clientes[i];
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(c.nome),
                                  subtitle: Text('Comprou ${c.vezes}x • última em ${_data.format(c.ultimaCompra)}'),
                                  trailing: _avisados.contains(i)
                                      ? const Icon(Icons.check)
                                      : IconButton(
                                          tooltip: 'Abrir WhatsApp',
                                          icon: const Icon(Icons.chat_outlined),
                                          onPressed: () => _abrir(i),
                                        ),
                                );
                              },
                            ),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, _avisados.length),
              child: Text(_avisados.isEmpty ? 'Fechar' : 'Concluir (${_avisados.length} avisado(s))'),
            ),
          ],
        ),
      ),
    );
  }
}
