import 'package:diacritic/diacritic.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/produto_provider.dart';
import '../models/produto.dart';
import 'carrinho_screen.dart';
// import 'package:flutter_barcode_scanner/flutter_barcode_scanner.dart';

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

  // Categorias definidas
  List<String> categorias = [
    'Tudo', 'Destaques', 'Farmácia', 'Atacado', 'Petiscos e Saches',
    'Higiene e Beleza', 'Brinquedos e Outros', 'Areia e Granulado',
    'Ração para Cães', 'Ração para Gatos', 'Vermífugos', 'Antiparasitários',
    'Dermatológicos', 'Camas e Colchonetes', 'Dedetização'
  ];

  @override
  void initState() {
    super.initState();
    produtosFiltrados = Provider.of<ProdutoProvider>(context, listen: false).produtos;
  }

  void _adicionarAoCarrinho(Produto produto) {
    setState(() {
      var item = carrinho.firstWhere(
              (element) => element['produto'].id == produto.id,
          orElse: () => {}
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
    return carrinho.fold(0.0, (total, item) => total + (item['produto'].preco * item['quantidade']));
  }


// Função para remover caracteres especiais e normalizar a string
  String normalizeString(String input) {
    String normalized = removeDiacritics(input);  // Remove acentos e diacríticos
    return normalized.replaceAll(RegExp(r'[^\w\s]'), '').toLowerCase();
  }

  // Função de pesquisa
  void _pesquisarProdutos(String query) {
    final produtoProvider = Provider.of<ProdutoProvider>(context, listen: false);
    final queryNormalized = normalizeString(query); // Normaliza a query de pesquisa
    setState(() {
      produtosFiltrados = produtoProvider.produtos.where((produto) {
        // Normaliza o nome do produto também e compara com a query
        final produtoNomeNormalized = normalizeString(produto.nome);
        return produtoNomeNormalized.contains(queryNormalized);
      }).toList();
    });
  }

  void _filtrarProdutosPorCategoria(String categoria) {
    setState(() {
      categoriaSelecionada = categoria;
      if (categoria == 'Tudo') {
        produtosFiltrados = Provider.of<ProdutoProvider>(context, listen: false).produtos;
      } else {
        produtosFiltrados = Provider.of<ProdutoProvider>(context, listen: false)
            .produtos
            .where((produto) => produto.categoria == categoria)
            .toList();
      }
    });
  }

  // Future<void> _scanBarcode() async {
  //   String barcode = await FlutterBarcodeScanner.scanBarcode(
  //       '#ff6666', 'Cancelar', true, ScanMode.BARCODE);
  //   if (barcode != '-1') {
  //     // Aqui você pode usar o código de barras para buscar o produto
  //     // Exemplo de exibição:
  //     print('Código de barras: $barcode');
  //   }
  // }

  @override
  Widget build(BuildContext context) {
    final produtoProvider = Provider.of<ProdutoProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Venda de Produtos'),
        actions: [
          IconButton(
            icon: Icon(Icons.person),
            onPressed: () {
              // Ação para selecionar ou cadastrar um cliente
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
                    onChanged: (value) {
                      _pesquisarProdutos(value);
                    },
                  ),
                ),
                // IconButton(
                //   icon: Icon(Icons.camera_alt),
                //   onPressed: _scanBarcode,
                // ),
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
                  onTap: () {
                    _filtrarProdutosPorCategoria(categorias[index]);
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 16.0),
                    alignment: Alignment.center,
                    child: Text(categorias[index]),
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
              ),
              itemCount: produtosFiltrados.length,
              itemBuilder: (ctx, i) {
                return GestureDetector(
                  onTap: () {
                    _adicionarAoCarrinho(produtosFiltrados[i]);
                  },
                  child: Card(
                    child: Column(
                      children: [
                        Image.network(produtosFiltrados[i].imagemUrl),
                        Text(produtosFiltrados[i].nome),
                        Text('R\$ ${produtosFiltrados[i].preco}'),
                      ],
                    ),
                  ),
                );
              },
            )
                : ListView.builder(
              itemCount: produtosFiltrados.length,
              itemBuilder: (ctx, i) {
                return GestureDetector(
                  onTap: () {
                    _adicionarAoCarrinho(produtosFiltrados[i]);
                  },
                  child: ListTile(
                    title: Text(produtosFiltrados[i].nome),
                    subtitle: Text('Preço: R\$ ${produtosFiltrados[i].preco}'),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (ctx) => CarrinhoScreen(
                      carrinho: carrinho,
                      valorTotal: valorTotal,
                    ),
                  ),
                );
              },
              child: Text(
                'Carrinho: ${carrinho.length} item(s) - R\$ ${valorTotal.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
