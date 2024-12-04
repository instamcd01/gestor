import 'package:flutter/material.dart';
import '../models/produto.dart';

class ProdutoProvider with ChangeNotifier {
  List<Produto> _produtos = [
    Produto(
      id: '1',
      nome: 'Ração para Cachorro',
      preco: 50.0,
      precoPromocional: 40.0,
      descricao: 'Ração nutritiva para cães.',
      categoria: 'Rações',
      estoqueAtual: 100,
      estoqueMinimo: 10,
      imagemUrl: '', // Início sem imagem, podendo ser atualizada
      codigoBarras: '123456789',
      custo: 30.0,
      destacar: false,
      exibirNoCatalogo: true,
    ),
    Produto(
      id: '2',
      nome: 'Coleira para Cães',
      preco: 30.0,
      precoPromocional: 25.0,
      descricao: 'Coleira ajustável para cães.',
      categoria: 'Acessórios',
      estoqueAtual: 50,
      estoqueMinimo: 10,
      imagemUrl: '', // Início sem imagem, podendo ser atualizada
      codigoBarras: '987654321',
      custo: 20.0,
      destacar: false,
      exibirNoCatalogo: true,
    ),
    // Adicione outros produtos conforme necessário
  ];

  List<Produto> get produtos => _produtos;

  void adicionarProduto(Produto produto) {
    // Gerar um ID único diretamente na criação
    final novoProduto = Produto(
      id: DateTime.now().toString(),  // Gerar um novo ID
      nome: produto.nome,
      preco: produto.preco,
      precoPromocional: produto.precoPromocional,
      descricao: produto.descricao,
      categoria: produto.categoria,
      estoqueAtual: produto.estoqueAtual,
      estoqueMinimo: produto.estoqueMinimo,
      imagemUrl: produto.imagemUrl,
      codigoBarras: produto.codigoBarras,
      custo: produto.custo,
      destacar: produto.destacar,
      exibirNoCatalogo: produto.exibirNoCatalogo,
    );

    _produtos.add(novoProduto);
    notifyListeners();
  }
}
