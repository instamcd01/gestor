import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/produto_provider.dart';
import '../models/produto.dart';
import 'carrinho_screen.dart';

class VendasScreen extends StatefulWidget {
  @override
  _VendasScreenState createState() => _VendasScreenState();
}

class _VendasScreenState extends State<VendasScreen> {
  List<Map<String, dynamic>> carrinho = []; // Alterando para um mapa que inclui quantidade
  bool isGridView = true;
  TextEditingController _searchController = TextEditingController();
  List<Produto> produtosFiltrados = [];

  @override
  void initState() {
    super.initState();
    produtosFiltrados = Provider.of<ProdutoProvider>(context, listen: false).produtos;
  }

  void _adicionarAoCarrinho(Produto produto) {
    setState(() {
      // Verifica se o produto já está no carrinho
      var item = carrinho.firstWhere(
              (element) => element['produto'].id == produto.id,
          orElse: () => {} // Retorna um mapa vazio se o produto não for encontrado
      );

      if (item.isNotEmpty) {
        // Se o produto já estiver no carrinho, aumenta a quantidade
        item['quantidade']++;
      } else {
        // Caso contrário, adiciona o produto com quantidade 1
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
          Expanded(
            child: isGridView
                ? GridView.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
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
          // Botão com a quantidade de produtos e o valor total
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: ElevatedButton(
              onPressed: () {
                // Navega para a tela do carrinho
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
