import 'package:flutter/material.dart';
import '../models/produto.dart';

class ProdutoProvider with ChangeNotifier {
  List<Produto> _produtos = [
    Produto(
      id: '1',
      nome: 'Ração para Cachorro',
      preco: 50.0,
      descricao: 'Ração nutritiva para cães.',
      categoria: 'Rações',
      estoque: 100,
      imagemUrl: '',
    ),
    Produto(
      id: '2',
      nome: 'Coleira para Cães',
      preco: 30.0,
      descricao: 'Coleira ajustável para cães.',
      categoria: 'Acessórios',
      estoque: 50,
      imagemUrl: '',
    ),
    // Adicione outros produtos conforme necessário
  ];

  List<Produto> get produtos => _produtos;

  void adicionarProduto(Produto produto) {
    _produtos.add(produto);
    notifyListeners();
  }
}
