import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/produto_provider.dart';
import '../widgets/produto_item.dart';

class ProdutosScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final produtoProvider = Provider.of<ProdutoProvider>(context);
    return Scaffold(
      appBar: AppBar(title: Text('Produtos')),
      body: ListView.builder(
        itemCount: produtoProvider.produtos.length,
        itemBuilder: (ctx, i) {
          return ProdutoItem(produto: produtoProvider.produtos[i], onAddToCart: (Produto ) {  },);
        },
      ),
    );
  }
}
