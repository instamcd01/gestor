import 'package:flutter/material.dart';
import '../models/produto.dart';

class ProdutoProvider with ChangeNotifier {
  List<Produto> _produtos = [
    // Produto(
    //   id: '1',
    //   nome: 'Ração para Cachorro',
    //   preco: 50.0,
    //   precoPromocional: 40.0,
    //   descricao: 'Ração nutritiva para cães.',
    //   categoria: 'Rações',
    //   estoqueAtual: 100,
    //   estoqueMinimo: 10,
    //   imagemUrl: '', // Início sem imagem, podendo ser atualizada
    //   codigoBarras: '123456789',
    //   custo: 30.0,
    //   destacar: false,
    //   exibirNoCatalogo: true,
    //   precoIfood: 70.0,
    //   validade: '',
    //   markup: '',
    //   lucro: '',
    //   empresa: '',
    //   precoConcorrencia: '',
    //
    // ),
    // Produto(
    //   id: '2',
    //   nome: 'Coleira para Cães',
    //   preco: 30.0,
    //   precoPromocional: 25.0,
    //   descricao: 'Coleira ajustável para cães.',
    //   categoria: 'Acessórios',
    //   estoqueAtual: 50,
    //   estoqueMinimo: 10,
    //   imagemUrl: '', // Início sem imagem, podendo ser atualizada
    //   codigoBarras: '987654321',
    //   custo: 20.0,
    //   destacar: false,
    //   exibirNoCatalogo: true,
    //   precoIfood: 40.0,
    //   validade: '',
    //   markup: '',
    //   lucro: '',
    //   empresa: '',
    //   precoConcorrencia: '',
    // ),
    // // Adicione outros produtos conforme necessário
  ];

  List<Produto> get produtos => _produtos;

  void atualizarProduto(Produto produto) {
    final index = _produtos.indexWhere((p) => p.id == produto.id);
    if (index >= 0) {
      _produtos[index] = produto;
      notifyListeners(); // Notifica os listeners (telas) sobre a alteração
    }
  }
  void adicionarProduto(Produto produto) {
    // Gerar um ID único diretamente na criação
    // final novoProduto = Produto(
    //   id: DateTime.now().toString(),  // Gerar um novo ID
    //   nome: produto.nome,
    //   preco: produto.preco,
    //   precoPromocional: produto.precoPromocional,
    //   descricao: produto.descricao,
    //   categoria: produto.categoria,
    //   estoqueAtual: produto.estoqueAtual,
    //   estoqueMinimo: produto.estoqueMinimo,
    //   imagemUrl: produto.imagemUrl,
    //   codigoBarras: produto.codigoBarras,
    //   custo: produto.custo,
    //   destacar: produto.destacar,
    //   exibirNoCatalogo: produto.exibirNoCatalogo,
    //   precoIfood: produto.precoIfood,
    //   validade: produto.validade,
    //   markup: produto.markup,
    //   lucro: produto.lucro,
    //   empresa: produto.empresa,
    //   precoConcorrencia: produto.precoConcorrencia,
    //
    //
    //
    // );

    // _produtos.add(novoProduto);

    _produtos.add(produto);
    notifyListeners();
  }
  void adicionarProdutos(List<Produto> novosProdutos) {
    // Adicionar múltiplos produtos à lista existente
    _produtos.addAll(novosProdutos);
    notifyListeners();
  }
}


