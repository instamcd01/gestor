import 'package:diacritic/diacritic.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/produto_provider.dart';
import '../providers/carrinho_provider.dart';
import '../providers/kit_produto_provider.dart';
import '../models/kit_produto.dart';
import '../models/produto.dart';
import '../utils/busca_utils.dart';
import '../widgets/preco_com_desconto.dart';
import 'cadastro_produto_screen.dart';
import 'carrinho_screen.dart';

/// Categoria sintética (não vem do banco) pra alternar a grade pra kits —
/// distinto de um nome de categoria real que o lojista possa ter cadastrado
/// (inclusive "Kits", já que é a categoria sugerida por padrão no cadastro
/// de kit) evitando colisão de nome.
const _categoriaKits = '__kits__';

class VendasScreen extends StatefulWidget {
  const VendasScreen({super.key});

  @override
  State<VendasScreen> createState() => _VendasScreenState();
}

class _VendasScreenState extends State<VendasScreen> {
  bool isGridView = true;
  bool _carregando = true;
  final TextEditingController _searchController = TextEditingController();
  List<Produto> produtosFiltrados = [];
  String categoriaSelecionada = 'Tudo';

  List<String> categorias = ['Tudo'];

  @override
  void initState() {
    super.initState();
    _carregarProdutosIniciais();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _carregarProdutosIniciais() async {
    final produtoProvider = Provider.of<ProdutoProvider>(context, listen: false);
    await Future.wait([
      produtoProvider.atualizarProdutosDoFirestore(),
      context.read<KitProdutoProvider>().carregarKits(),
    ]);
    if (!mounted) return;
    final produtos = produtoProvider.produtos;
    final categoriasDinamicas = produtos.map((p) => p.categoria).toSet().toList();
    categoriasDinamicas.sort();
    setState(() {
      categorias = ['Tudo', ...categoriasDinamicas, _categoriaKits];
      produtosFiltrados = produtos;
      _carregando = false;
    });
  }

  void _adicionarAoCarrinho(Produto produto) {
    try {
      context.read<CarrinhoProvider>().adicionarProduto(produto);
      // Sem SnackBar de sucesso — a barra fixa embaixo já mostra a
      // contagem de itens atualizada na hora; avisar de novo a cada toque
      // só atrapalhava quem tocava vários produtos em sequência.
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível adicionar: estoque insuficiente de ${produto.nome}.')),
      );
    }
  }

  void _adicionarKitAoCarrinho(KitProduto kit) {
    try {
      final catalogoProdutos = context.read<ProdutoProvider>().produtos;
      context.read<CarrinhoProvider>().adicionarKit(kit, catalogoProdutos);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível adicionar o kit "${kit.nome}": $e')),
      );
    }
  }

  String normalizeString(String input) {
    String normalized = removeDiacritics(input);
    return normalized.replaceAll(RegExp(r'[^\w\s]'), '').toLowerCase();
  }

  void _pesquisarProdutos(String query) {
    final produtoProvider = Provider.of<ProdutoProvider>(context, listen: false);
    setState(() {
      produtosFiltrados = produtoProvider.produtos.where((produto) {
        return contemTodasPalavras(produto.nome, query);
      }).toList();
    });
  }

  void _filtrarProdutosPorCategoria(String categoria) {
    setState(() {
      categoriaSelecionada = categoria;
      if (categoria == _categoriaKits) return; // grade de kits usa KitProdutoProvider direto, ver build()
      final produtoProvider = Provider.of<ProdutoProvider>(context, listen: false);
      if (categoria == 'Tudo') {
        produtosFiltrados = produtoProvider.produtos;
      } else {
        final categoriaNormalizada = normalizeString(categoria);
        produtosFiltrados = produtoProvider.produtos.where((produto) {
          final categoriaProdutoNormalizada = normalizeString(produto.categoria);
          return categoriaProdutoNormalizada == categoriaNormalizada;
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Venda de Produtos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Cadastrar produto',
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(
                builder: (ctx) => CadastroProdutoScreen(),
              ));
            },
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: const InputDecoration(
                      hintText: 'Pesquisar produto...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: _pesquisarProdutos,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  icon: Icon(isGridView ? Icons.view_list_outlined : Icons.grid_view_outlined),
                  tooltip: isGridView ? 'Ver em lista' : 'Ver em grade',
                  onPressed: () {
                    setState(() {
                      isGridView = !isGridView;
                    });
                  },
                ),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: categorias.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, index) {
                final categoria = categorias[index];
                final selecionada = categoriaSelecionada == categoria;
                return ChoiceChip(
                  avatar: categoria == _categoriaKits ? const Icon(Icons.card_giftcard, size: 16) : null,
                  label: Text(categoria == _categoriaKits ? 'Kits' : categoria),
                  selected: selecionada,
                  onSelected: (_) => _filtrarProdutosPorCategoria(categoria),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : categoriaSelecionada == _categoriaKits
                    ? _gradeKits(colorScheme)
                    : produtosFiltrados.isEmpty
                        ? _estadoVazio(colorScheme)
                        : (isGridView ? _grade(colorScheme) : _lista(colorScheme)),
          ),
          _barraCarrinho(colorScheme),
        ],
      ),
    );
  }

  Widget _estadoVazio(ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 56, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              'Nenhum produto encontrado',
              style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              'Tente outra busca ou categoria.',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _grade(ColorScheme colorScheme) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.72,
      ),
      itemCount: produtosFiltrados.length,
      itemBuilder: (ctx, i) {
        final produto = produtosFiltrados[i];
        final semEstoque = produto.estoqueAtual == 0;

        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: semEstoque ? null : () => _adicionarAoCarrinho(produto),
            child: Opacity(
              opacity: semEstoque ? 0.5 : 1,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    Expanded(child: _imagemProduto(produto, colorScheme)),
                    const SizedBox(height: 6),
                    Text(
                      produto.nome,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    PrecoComDesconto(produto: produto, compact: true),
                    Text(
                      semEstoque ? 'Sem estoque' : '${produto.estoqueAtual} em estoque',
                      style: TextStyle(
                        fontSize: 11,
                        color: semEstoque ? Colors.red : colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _gradeKits(ColorScheme colorScheme) {
    final kits = context.watch<KitProdutoProvider>().kits;
    if (kits.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.card_giftcard, size: 56, color: colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text('Nenhum kit cadastrado ainda', style: TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.72,
      ),
      itemCount: kits.length,
      itemBuilder: (ctx, i) {
        final kit = kits[i];
        final semEstoque = kit.estoqueDisponivel <= 0;

        return Card(
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: semEstoque ? null : () => _adicionarKitAoCarrinho(kit),
            child: Opacity(
              opacity: semEstoque ? 0.5 : 1,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          width: double.infinity,
                          color: colorScheme.surfaceContainerHighest,
                          child: kit.imagemUrl.isNotEmpty
                              ? Image.network(
                                  kit.imagemUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      Icon(Icons.card_giftcard, color: colorScheme.onSurfaceVariant),
                                )
                              : Icon(Icons.card_giftcard, color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      kit.nome,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'R\$ ${(kit.precoPromocional ?? kit.preco).toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      semEstoque ? 'Sem estoque' : '${kit.estoqueDisponivel} kits disponíveis',
                      style: TextStyle(
                        fontSize: 11,
                        color: semEstoque ? Colors.red : colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _lista(ColorScheme colorScheme) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: produtosFiltrados.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final produto = produtosFiltrados[i];
        final semEstoque = produto.estoqueAtual == 0;

        return Opacity(
          opacity: semEstoque ? 0.5 : 1,
          child: ListTile(
            onTap: semEstoque ? null : () => _adicionarAoCarrinho(produto),
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(width: 48, height: 48, child: _imagemProduto(produto, colorScheme)),
            ),
            title: Text(produto.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: PrecoComDesconto(produto: produto),
            trailing: Text(
              semEstoque ? 'Sem estoque' : '${produto.estoqueAtual} un.',
              style: TextStyle(
                fontSize: 12,
                color: semEstoque ? Colors.red : colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _imagemProduto(Produto produto, ColorScheme colorScheme) {
    final imagemUrl = produto.imagemUrl.isNotEmpty
        ? produto.imagemUrl
        : 'http://imagens.lukz.com.br/produtos/${produto.codigoBarras}.png';

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: colorScheme.surfaceContainerHighest,
        child: Image.network(
          imagemUrl,
          fit: BoxFit.cover,
          width: double.infinity,
          loadingBuilder: (context, child, progress) {
            if (progress == null) return child;
            return Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
              ),
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return Icon(Icons.image_not_supported_outlined, color: colorScheme.onSurfaceVariant);
          },
        ),
      ),
    );
  }

  Widget _barraCarrinho(ColorScheme colorScheme) {
    return Consumer<CarrinhoProvider>(
      builder: (context, carrinhoProvider, _) {
        final vazio = carrinhoProvider.totalUnidades == 0;

        return SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
            ),
            child: ElevatedButton(
              onPressed: vazio
                  ? null
                  : () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CarrinhoScreen(idVenda: ''),
                        ),
                      );
                      if (!mounted) return;
                      await Provider.of<ProdutoProvider>(context, listen: false).carregarProdutos();
                      setState(() {
                        produtosFiltrados = Provider.of<ProdutoProvider>(context, listen: false).produtos;
                      });
                    },
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.shopping_bag_outlined, size: 20),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${carrinhoProvider.totalUnidades} ite${carrinhoProvider.totalUnidades == 1 ? 'm' : 'ns'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'R\$ ${carrinhoProvider.totalCarrinho.toStringAsFixed(2)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
