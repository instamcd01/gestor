import 'package:flutter/material.dart';
import '../models/produto.dart';

class ProdutoItem extends StatelessWidget {
  final Produto produto;
  final Function(Produto) onAddToCart;

  ProdutoItem({required this.produto, required this.onAddToCart});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 15),
      child: ListTile(
        title: Text(produto.nome),
        subtitle: Text('Preço: R\$ ${produto.preco}'),
        trailing: IconButton(
          icon: Icon(Icons.add_shopping_cart),
          onPressed: () => onAddToCart(produto),
        ),
      ),
    );
  }
}

