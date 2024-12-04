import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/produto_provider.dart';
import '../widgets/produto_item.dart';
import '../models/produto.dart';
import 'cadastro_produto_screen.dart';

class ProdutosScreen extends StatefulWidget {
  @override
  _ProdutosScreenState createState() => _ProdutosScreenState();
}

class _ProdutosScreenState extends State<ProdutosScreen> {
  TextEditingController _searchController = TextEditingController();
  List<Produto> produtosFiltrados = [];
  String selectedFilter = 'Itens'; // Filtro selecionado: 'Itens', 'Estoque', ou 'Categorias'

  @override
  void initState() {
    super.initState();
    produtosFiltrados = Provider.of<ProdutoProvider>(context, listen: false).produtos;
  }

  void _pesquisarProdutos(String query) {
    final produtoProvider = Provider.of<ProdutoProvider>(context, listen: false);
    setState(() {
      produtosFiltrados = produtoProvider.produtos.where((produto) {
        return produto.nome.toLowerCase().contains(query.toLowerCase()) ||
            produto.preco.toString().contains(query) ||
            produto.id.toString().contains(query);
      }).toList();
    });
  }

  void _exportarRelatorio() {
    // Lógica para exportar o relatório
    print('Exportando relatório...');
  }

  @override
  Widget build(BuildContext context) {
    final produtoProvider = Provider.of<ProdutoProvider>(context);
    final totalProdutos = produtoProvider.produtos.length;
    return Scaffold(
      appBar: AppBar(
        title: Text('Produtos (${totalProdutos})'),
        actions: [
          IconButton(
            icon: Icon(Icons.file_download),
            onPressed: _exportarRelatorio, // Função para exportar relatório
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          // Filtros de seleção lado a lado com botões
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Botão de filtro de Itens
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        selectedFilter = 'Itens';
                      });
                    },
                    child: Text('Itens'),
                    style: ElevatedButton.styleFrom(
                      primary: selectedFilter == 'Itens' ? Colors.blue : Colors.grey,
                      padding: EdgeInsets.symmetric(vertical: 12), // Ajustando altura para consistência
                    ),
                  ),
                ),
                // Botão de filtro de Estoque
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        selectedFilter = 'Estoque';
                      });
                    },
                    child: Text('Estoque'),
                    style: ElevatedButton.styleFrom(
                      primary: selectedFilter == 'Estoque' ? Colors.blue : Colors.grey,
                      padding: EdgeInsets.symmetric(vertical: 12), // Ajustando altura para consistência
                    ),
                  ),
                ),
                // Botão de filtro de Categorias
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        selectedFilter = 'Categorias';
                      });
                    },
                    child: Text('Categorias'),
                    style: ElevatedButton.styleFrom(
                      primary: selectedFilter == 'Categorias' ? Colors.blue : Colors.grey,
                      padding: EdgeInsets.symmetric(vertical: 12), // Ajustando altura para consistência
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Barra de pesquisa
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Pesquisar Produto',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) {
                      _pesquisarProdutos(value); // Função para pesquisar
                    },
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.add),
                  onPressed: () {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (ctx) => CadastroProdutoScreen())); // Navega para a tela de cadastro de produto
                  },
                ),
              ],
            ),
          ),
          // Exibição dos produtos filtrados e listados em ordem alfabética
          Expanded(
            child: ListView.builder(
              itemCount: produtosFiltrados.length,
              itemBuilder: (ctx, i) {
                return Card(
                  margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: ListTile(
                    contentPadding: EdgeInsets.all(16),
                    leading: produtosFiltrados[i].imagemUrl.isNotEmpty
                        ? Image.network(produtosFiltrados[i].imagemUrl)
                        : Icon(Icons.image_not_supported), // Imagem do produto
                    title: Text(
                      produtosFiltrados[i].nome,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Categoria: ${produtosFiltrados[i].categoria}'),
                        Text('Preço: R\$ ${produtosFiltrados[i].preco.toStringAsFixed(2)}'),
                        Text('Estoque Atual: ${produtosFiltrados[i].estoqueAtual}'),
                      ],
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.edit),
                      onPressed: () {
                        // Ação para editar o produto
                        print('Editando produto: ${produtosFiltrados[i].nome}');
                      },
                    ),
                    onTap: () {
                      // Ação ao clicar no produto
                      print('Produto selecionado: ${produtosFiltrados[i].nome}');
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
