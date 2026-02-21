import 'package:diacritic/diacritic.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/produto_provider.dart';
import '../models/produto.dart';
import 'cadastro_produto_screen.dart';
import 'carrinho_screen.dart';

class VendasScreen extends StatefulWidget {
  @override
  _VendasScreenState createState() => _VendasScreenState();
}

class _VendasScreenState extends State<VendasScreen> {
  List<Map<String, dynamic>> carrinho = [];
  bool isGridView = true;
  TextEditingController _searchController = TextEditingController();
  List<Produto> produtosFiltrados = [];
  String categoriaSelecionada = 'Tudo';
  bool _isFirstLoad = true;

  List<String> categorias = ['Tudo'];

  @override
  void initState() {
    super.initState();
    _carregarProdutosIniciais();
  }

  Future<void> _carregarProdutosIniciais() async {
    final produtoProvider = Provider.of<ProdutoProvider>(context, listen: false);
    await produtoProvider.atualizarProdutosDoFirestore();
    final produtos = produtoProvider.produtos;
    final categoriasDinamicas = produtos.map((p) => p.categoria).toSet().toList();
    categoriasDinamicas.sort();
    setState(() {
      categorias = ['Tudo', ...categoriasDinamicas];
      produtosFiltrados = produtos;
    });
  }

  void _adicionarAoCarrinho(Produto produto) {
    setState(() {
      var item = carrinho.firstWhere(
            (element) => element['produto'].id == produto.id,
        orElse: () => {},
      );

      if (item.isNotEmpty) {
        item['quantidade']++;
      } else {
        carrinho.add({
          'produto': produto,
          'quantidade': 1,
        });
      }
    });
  }

  double get valorTotal {
    return carrinho.fold(0.0, (total, item) =>
    total + (item['produto'].preco * item['quantidade']));
  }

  String normalizeString(String input) {
    String normalized = removeDiacritics(input);
    return normalized.replaceAll(RegExp(r'[^\w\s]'), '').toLowerCase();
  }

  void _pesquisarProdutos(String query) {
    final produtoProvider = Provider.of<ProdutoProvider>(context, listen: false);
    final queryNormalized = normalizeString(query);
    setState(() {
      produtosFiltrados = produtoProvider.produtos.where((produto) {
        final nomeNormalizado = normalizeString(produto.nome);
        return nomeNormalizado.contains(queryNormalized);
      }).toList();
    });
  }

  String getTotalUnidades() {
    double totalUnidades = 0;
    for (var item in carrinho) {
      totalUnidades += item['quantidade'];
    }
    return totalUnidades == totalUnidades.toInt()
        ? totalUnidades.toInt().toString()
        : totalUnidades.toString();
  }

  void _filtrarProdutosPorCategoria(String categoria) {
    setState(() {
      categoriaSelecionada = categoria;
      final produtoProvider = Provider.of<ProdutoProvider>(context, listen: false);
      if (categoria == 'Tudo') {
        produtosFiltrados = produtoProvider.produtos;
      } else {
        final categoriaNormalizada = normalizeString(categoria);
        produtosFiltrados = produtoProvider.produtos.where((produto) {
          final categoriaProdutoNormalizada = normalizeString(produto.categoria ?? '');
          return categoriaProdutoNormalizada == categoriaNormalizada;
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final produtoProvider = Provider.of<ProdutoProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Venda de Produtos'),
        actions: [
          IconButton(
            icon: Icon(Icons.add),
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
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Pesquisar produto...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: _pesquisarProdutos,
                  ),
                ),
                IconButton(
                  icon: Icon(isGridView ? Icons.list : Icons.grid_view),
                  onPressed: () {
                    setState(() {
                      isGridView = !isGridView;
                    });
                  },
                ),
              ],
            ),
          ),
          Container(
            height: 50,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: categorias.length,
              itemBuilder: (ctx, index) {
                return GestureDetector(
                  onTap: () => _filtrarProdutosPorCategoria(categorias[index]),
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      border: categoriaSelecionada == categorias[index]
                          ? Border(bottom: BorderSide(color: Colors.blue, width: 2))
                          : null,
                    ),
                    child: Text(
                      categorias[index],
                      style: TextStyle(
                        color: categoriaSelecionada == categorias[index]
                            ? Colors.blue
                            : Colors.black,
                        fontWeight: categoriaSelecionada == categorias[index]
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Expanded(
            child: isGridView
                ? GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8.0,
                mainAxisSpacing: 8.0,
                childAspectRatio: 0.75, // AJUSTADO: controla altura/largura para evitar overflow
              ),
              itemCount: produtosFiltrados.length,
              itemBuilder: (ctx, i) {
                final produto = produtosFiltrados[i];

                final imagemUrl = produto.imagemUrl != null && produto.imagemUrl!.isNotEmpty
                    ? produto.imagemUrl!
                    : 'http://imagens.lukz.com.br/produtos/${produto.codigoBarras}.png';

                return GestureDetector(
                  onTap: () => _adicionarAoCarrinho(produto),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(4.0), // AJUSTADO: espaçamento interno
                      child: Column(
                        children: [
                          Image.network(
                            imagemUrl,
                            height: 60,
                            width: 60,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Icon(Icons.image_not_supported,
                                  size: 50, color: Colors.grey);
                            },
                          ),
                          SizedBox(height: 4), // AJUSTADO: espaçamento
                          // AJUSTADO: Texto com ellipsis para evitar overflow
                          Text(
                            produto.nome,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                          Text('R\$ ${produto.preco}'),
                          Text(
                            'Estoque: ${produto.estoqueAtual}',
                            style: TextStyle(
                              fontSize: 12,
                              color: produto.estoqueAtual == 0
                                  ? Colors.red
                                  : Colors.grey[700],
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis, // AJUSTADO
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            )
                : ListView.builder(
              itemCount: produtosFiltrados.length,
              itemBuilder: (ctx, i) {
                final produto = produtosFiltrados[i];
                final imagemUrl = produto.imagemUrl != null && produto.imagemUrl!.isNotEmpty
                    ? produto.imagemUrl!
                    : 'http://imagens.lukz.com.br/produtos/${produto.codigoBarras}.png';

                return GestureDetector(
                  onTap: () => _adicionarAoCarrinho(produto),
                  child: ListTile(
                    leading: Image.network(
                      imagemUrl,
                      width: 50,
                      height: 50,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(Icons.image_not_supported,
                            size: 30, color: Colors.grey);
                      },
                    ),
                    // AJUSTADO: Título com ellipsis
                    title: Text(
                      produto.nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      'Preço: R\$ ${produto.preco}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (ctx) => CarrinhoScreen(
                      carrinho: carrinho,
                      valorTotal: valorTotal,
                      idVenda: '',
                      idCliente: '',
                    ),
                  ),
                );

                await Provider.of<ProdutoProvider>(context, listen: false).carregarProdutos();
                setState(() {
                  produtosFiltrados = Provider.of<ProdutoProvider>(context, listen: false).produtos;
                });
              },
              child: Text(
                'Carrinho: ${getTotalUnidades()} Itens(s) - R\$ ${valorTotal.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 18),
                overflow: TextOverflow.ellipsis, // AJUSTADO: evita overflow do botão
              ),
            ),
          ),
        ],
      ),
    );
  }
}
