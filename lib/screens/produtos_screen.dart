// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import '../providers/produto_provider.dart';
// import '../widgets/importar_produtos_planilha.dart';
// import '../widgets/produto_item.dart';
// import '../models/produto.dart';
// import 'cadastro_produto_screen.dart';
// import 'editar_produto_screen.dart';  // Importando a tela de edição
//
// class ProdutosScreen extends StatefulWidget {
//   @override
//   _ProdutosScreenState createState() => _ProdutosScreenState();
// }
//
// // class _ProdutosScreenState extends State<ProdutosScreen> {
// //   TextEditingController _searchController = TextEditingController();
// //   List<Produto> produtosFiltrados = [];
// //   String selectedFilter =
// //       'Itens'; // Filtro selecionado: 'Itens', 'Estoque', ou 'Categorias'
// //
// //   @override
// //   void initState() {
// //     super.initState();
// //     produtosFiltrados =
// //         Provider.of<ProdutoProvider>(context, listen: false).produtos;
// //   }
// //
// //   void _pesquisarProdutos(String query) {
// //     final produtoProvider =
// //     Provider.of<ProdutoProvider>(context, listen: false);
// //     setState(() {
// //       produtosFiltrados = produtoProvider.produtos.where((produto) {
// //         return produto.nome.toLowerCase().contains(query.toLowerCase()) ||
// //             produto.preco.toString().contains(query) ||
// //             produto.id.toString().contains(query);
// //       }).toList();
// //     });
// //   }
// //
// //   void _exportarRelatorio() {
// //     // Lógica para exportar o relatório
// //     print('Exportando relatório...');
// //   }
// //
// //   Future<void> _importarProdutos() async {
// //     final produtoProvider = Provider.of<ProdutoProvider>(context, listen: false);
// //     // Navegar para a tela de importação
// //     await Navigator.of(context).push(MaterialPageRoute(
// //       builder: (context) => ImportarProdutosScreen(),
// //     ));
// //     // Atualizar a lista após importar
// //     setState(() {
// //       produtosFiltrados =
// //           Provider.of<ProdutoProvider>(context, listen: false).produtos;
// //     });
// //   }
// //
// //   @override
// //   Widget build(BuildContext context) {
// //     final produtoProvider = Provider.of<ProdutoProvider>(context);
// //     final totalProdutos = produtoProvider.produtos.length;
// //     return Scaffold(
// //       appBar: AppBar(
// //         title: Text('Produtos (${totalProdutos})'),
// //         actions: [
// //           IconButton(
// //             icon: Icon(Icons.file_download),
// //             onPressed: _exportarRelatorio, // Função para exportar relatório
// //           ),
// //           IconButton(
// //             icon: Icon(Icons.upload_file), // Ícone de importação
// //             onPressed: _importarProdutos,
// //           ), // Função de importação
// //         ],
// //       ),
// //       body: Column(
// //         children: <Widget>[
// //           // Barra de pesquisa
// //           Padding(
// //             padding: const EdgeInsets.all(8.0),
// //             child: Row(
// //               children: [
// //                 Expanded(
// //                   child: TextField(
// //                     controller: _searchController,
// //                     decoration: InputDecoration(
// //                       labelText: 'Pesquisar Produto',
// //                       prefixIcon: Icon(Icons.search),
// //                     ),
// //                     onChanged: (value) {
// //                       _pesquisarProdutos(value); // Função para pesquisar
// //                     },
// //                   ),
// //                 ),
// //                 IconButton(
// //                   icon: Icon(Icons.add),
// //                   onPressed: () {
// //                     Navigator.of(context).push(MaterialPageRoute(
// //                         builder: (ctx) =>
// //                             CadastroProdutoScreen())); // Navega para a tela de cadastro de produto
// //                   },
// //                 ),
// //               ],
// //             ),
// //           ),
// //           // Exibição dos produtos filtrados e listados em ordem alfabética
// //           Expanded(
// //             child: ListView.builder(
// //               itemCount: produtosFiltrados.length,
// //               itemBuilder: (ctx, i) {
// //                 return Card(
// //                   margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
// //                   child:
// //                   ListTile(
// //                     contentPadding: EdgeInsets.all(16),
// //                     leading: produtosFiltrados[i].imagemUrl.isNotEmpty
// //                         ? Image.network(produtosFiltrados[i].imagemUrl)
// //                         : Icon(Icons.image_not_supported),
// //                     // Imagem do produto
// //                     title: Text(
// //                       produtosFiltrados[i].nome,
// //                       style:
// //                       TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
// //                     ),
// //                     subtitle: Column(
// //                       crossAxisAlignment: CrossAxisAlignment.start,
// //                       children: [
// //                         Text('Categoria: ${produtosFiltrados[i].categoria}'),
// //                         Text(
// //                             'Preço: R\$ ${produtosFiltrados[i].preco.toStringAsFixed(2)}'),
// //                         Text(
// //                             'Estoque Atual: ${produtosFiltrados[i].estoqueAtual}'),
// //                       ],
// //                     ),
// //                     trailing: IconButton(
// //                       icon: Icon(Icons.edit),
// //                       onPressed: () {
// //                         // Navegar para a tela de edição ao clicar no ícone de editar
// //                         Navigator.of(context).push(MaterialPageRoute(
// //                           builder: (context) => EditarProdutoScreen(
// //                             produto: produtosFiltrados[i], // Passa o produto para a tela de edição
// //                           ),
// //                         ));
// //                       },
// //                     ),
// //                     onTap: () {
// //                       // Ação ao clicar no produto
// //                       print(
// //                           'Produto selecionado: ${produtosFiltrados[i].nome}');
// //                     },
// //                   ),
// //                 );
// //               },
// //             ),
// //           ),
// //         ],
// //       ),
// //     );
// //   }
// // }
//
// class _ProdutosScreenState extends State<ProdutosScreen> {
//   TextEditingController _searchController = TextEditingController();
//   String selectedFilter = 'Itens';
//
//   @override
//   void initState() {
//     super.initState();
//
//     // Aguarda a build inicial para mostrar a notificação
//     WidgetsBinding.instance.addPostFrameCallback((_) async {
//       await _atualizarProdutosDoFirestore();
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(
//           content: Text('Produtos atualizados com sucesso!'),
//           duration: Duration(seconds: 2),
//         ),
//       );
//     });
//   }
//
//   Future<void> _atualizarProdutosDoFirestore() async {
//     final produtoProvider = Provider.of<ProdutoProvider>(context, listen: false);
//     await produtoProvider.carregarProdutos(); // Garante que os produtos venham atualizados do Firestore
//     setState(() {});
//     for (var produto in produtoProvider.produtos) {
//       if (produto.imagemUrl.isEmpty && produto.codigoBarras.isNotEmpty) {
//         // Implementar a função buscarImagemAutomatica no ProdutoProvider
//         produtoProvider.buscarImagemAutomatica(produto.id!);
//       }
//     }// Força reconstrução da tela após atualização
//   }
//
//   void _exportarRelatorio() {
//     print('Exportando relatório...');
//   }
//
//   Future<void> _importarProdutos() async {
//     await Navigator.of(context).push(MaterialPageRoute(
//       builder: (context) => ImportarProdutosScreen(),
//     ));
//     await _atualizarProdutosDoFirestore(); // Atualiza produtos após importação
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final produtoProvider = Provider.of<ProdutoProvider>(context);
//     final query = _searchController.text.toLowerCase();
//
//     final produtosFiltrados = produtoProvider.produtos.where((produto) {
//       return produto.nome.toLowerCase().contains(query) ||
//           produto.preco.toString().contains(query) ||
//           produto.id.toString().contains(query);
//     }).toList();
//
//     final totalProdutos = produtoProvider.produtos.length;
//
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('Produtos ($totalProdutos)'),
//         actions: [
//           IconButton(
//             icon: Icon(Icons.file_download),
//             onPressed: _exportarRelatorio,
//           ),
//           IconButton(
//             icon: Icon(Icons.upload_file),
//             onPressed: _importarProdutos,
//           ),
//         ],
//       ),
//       body: Column(
//         children: <Widget>[
//           Padding(
//             padding: const EdgeInsets.all(8.0),
//             child: Row(
//               children: [
//                 Expanded(
//                   child: TextField(
//                     controller: _searchController,
//                     decoration: InputDecoration(
//                       labelText: 'Pesquisar Produto',
//                       prefixIcon: Icon(Icons.search),
//                     ),
//                     onChanged: (_) => setState(() {}), // Atualiza a UI
//                   ),
//                 ),
//                 IconButton(
//                   icon: Icon(Icons.add),
//                   onPressed: () {
//                     Navigator.of(context).push(MaterialPageRoute(
//                       builder: (ctx) => CadastroProdutoScreen(),
//                     ));
//                   },
//                 ),
//               ],
//             ),
//           ),
//           Expanded(
//             child: ListView.builder(
//               itemCount: produtosFiltrados.length,
//               itemBuilder: (ctx, i) {
//                 final produto = produtosFiltrados[i];
//                 return Card(
//                   margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
//                   child: ListTile(
//                     contentPadding: EdgeInsets.all(16),
//                     leading: (produto.imagemUrl.isNotEmpty)
//                         ? Image.network(produto.imagemUrl)
//                         : (produto.imagemAutomaticaUrl != null && produto.imagemAutomaticaUrl!.isNotEmpty)
//                         ? Image.network(produto.imagemAutomaticaUrl!)
//                         : Icon(Icons.image_not_supported),
//
//                     title: Text(
//                       produto.nome,
//                       style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//                     ),
//                     subtitle: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         Text('Categoria: ${produto.categoria}'),
//                         Text('Preço: R\$ ${produto.preco.toStringAsFixed(2)}'),
//                         Text('Estoque Atual: ${produto.estoqueAtual}'),
//                       ],
//                     ),
//                     trailing: IconButton(
//                       icon: Icon(Icons.edit),
//                       onPressed: () {
//                         Navigator.of(context).push(MaterialPageRoute(
//                           builder: (context) => EditarProdutoScreen(produto: produto),
//                         ));
//                       },
//                     ),
//                     onTap: () {
//                       print('Produto selecionado: ${produto.nome}');
//                     },
//                   ),
//                 );
//               },
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }


import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/produto_provider.dart';
import '../widgets/importar_produtos_planilha.dart';
import '../widgets/produto_item.dart';
import '../models/produto.dart';
import 'cadastro_produto_screen.dart';
import 'editar_produto_screen.dart';  // Importando a tela de edição

class ProdutosScreen extends StatefulWidget {
  @override
  _ProdutosScreenState createState() => _ProdutosScreenState();
}

class _ProdutosScreenState extends State<ProdutosScreen> {
  TextEditingController _searchController = TextEditingController();
  String selectedFilter = 'Itens';

  @override
  void initState() {
    super.initState();

    // ===========================
    // Atualização automática dos produtos ao abrir a tela
    // ===========================
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _atualizarProdutosDoFirestore();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Produtos atualizados com sucesso!'),
          duration: Duration(seconds: 2),
        ),
      );
    });
  }

  // ===========================
  // Função para atualizar produtos do Firestore e buscar imagens automáticas
  // ===========================
  Future<void> _atualizarProdutosDoFirestore() async {
    final produtoProvider = Provider.of<ProdutoProvider>(context, listen: false);
    await produtoProvider.carregarProdutos(); // Carrega produtos atualizados do Firestore
    setState(() {}); // Força reconstrução da tela

    // ===========================
    // Atribui imagem automática se produto não tiver imagem manual
    // ===========================
    for (var produto in produtoProvider.produtos) {
      if ((produto.imagemUrl.isEmpty || produto.imagemUrl == null) &&
          produto.codigoBarras.isNotEmpty) {
        produtoProvider.buscarImagemAutomatica(produto.id!); // gera a URL automática
      }
    }
  }

  void _exportarRelatorio() {
    print('Exportando relatório...');
  }

  Future<void> _importarProdutos() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => ImportarProdutosScreen(),
    ));
    await _atualizarProdutosDoFirestore(); // Atualiza produtos após importação
  }

  @override
  Widget build(BuildContext context) {
    final produtoProvider = Provider.of<ProdutoProvider>(context);
    final query = _searchController.text.toLowerCase();

    final produtosFiltrados = produtoProvider.produtos.where((produto) {
      return produto.nome.toLowerCase().contains(query) ||
          produto.preco.toString().contains(query) ||
          produto.id.toString().contains(query);
    }).toList();

    final totalProdutos = produtoProvider.produtos.length;

    return Scaffold(
      appBar: AppBar(
        title: Text('Produtos ($totalProdutos)'),
        actions: [
          IconButton(
            icon: Icon(Icons.file_download),
            onPressed: _exportarRelatorio,
          ),
          IconButton(
            icon: Icon(Icons.upload_file),
            onPressed: _importarProdutos,
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          // ===========================
          // Barra de pesquisa
          // ===========================
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
                    onChanged: (_) => setState(() {}), // Atualiza a UI ao digitar
                  ),
                ),
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
          ),
          // ===========================
          // Lista de produtos filtrados
          // ===========================
          Expanded(
            child: ListView.builder(
              itemCount: produtosFiltrados.length,
              itemBuilder: (ctx, i) {
                final produto = produtosFiltrados[i];
                return Card(
                  margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                  child: ListTile(
                    contentPadding: EdgeInsets.all(16),
                    // ===========================
                    // Imagem do produto: prioriza imagem manual, senão usa automática do servidor
                    // ===========================
                    leading: (produto.imagemUrl.isNotEmpty)
                        ? Image.network(
                      produto.imagemUrl,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(Icons.image_not_supported, size: 48, color: Colors.grey);
                        // <- MOSTRA ÍCONE QUANDO A IMAGEM FALHAR
                      },
                    )
                        : (produto.imagemAutomaticaUrl != null &&
                        produto.imagemAutomaticaUrl!.isNotEmpty)
                        ? Image.network(
                      produto.imagemAutomaticaUrl!,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(Icons.image_not_supported, size: 48, color: Colors.grey);
                      },
                    )
                        : Icon(Icons.image_not_supported, size: 48, color: Colors.grey),

                    title: Text(
                      produto.nome,
                      style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Categoria: ${produto.categoria}'),
                        Text('Preço: R\$ ${produto.preco.toStringAsFixed(2)}'),
                        Text('Estoque Atual: ${produto.estoqueAtual}'),
                      ],
                    ),
                    trailing: IconButton(
                      icon: Icon(Icons.edit),
                      onPressed: () {
                        Navigator.of(context).push(MaterialPageRoute(
                          builder: (context) =>
                              EditarProdutoScreen(produto: produto),
                        ));
                      },
                    ),
                    onTap: () {
                      print('Produto selecionado: ${produto.nome}');
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
