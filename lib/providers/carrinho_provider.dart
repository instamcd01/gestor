// import 'package:flutter/material.dart';
// import '../models/produto.dart';
//
// class CarrinhoProvider with ChangeNotifier {
//   List<Map<String, dynamic>> _carrinho = [];
//   double _desconto = 0.0;
//   bool _opcaoEntrega = false;
//   double _valorEntrega = 0.0;
//   double _valorEntregaNormal = 0.0;
//   String _entregaSelecionada = '0-5km';
//
//   List<Map<String, dynamic>> get carrinho => _carrinho;
//   double get desconto => _desconto;
//   double get valorEntrega => _valorEntrega;
//   double get valorEntregaNormal => _valorEntregaNormal;
//   String get entregaSelecionada => _entregaSelecionada;
//
//   // Adicionar produto ao carrinho
//   void adicionarProduto(Map<String, dynamic> produto) {
//     _carrinho.add(produto);
//     notifyListeners();
//   }
//
//   // Remover produto do carrinho
//   void removerProduto(int index) {
//     _carrinho.removeAt(index);
//     notifyListeners();
//   }
//
//   // Atualizar a quantidade de um produto
//   void atualizarQuantidade(int index, int quantidade) {
//     if (quantidade > 0) {
//       _carrinho[index]['quantidade'] = quantidade;
//       notifyListeners();
//     }
//   }
//
//   // Calcular o subtotal
//   double getSubtotal() {
//     double subtotal = 0.0;
//     for (var item in _carrinho) {
//       subtotal += item['produto'].preco * item['quantidade'];
//     }
//     return subtotal;
//   }
//
//   // Calcular o valor faltante para frete grátis
//   double calcularFaltandoParaFreteGratis(double subtotal, Map<String, Map<String, double>> opcoesEntrega) {
//     double valorMinimo = opcoesEntrega['Frete grátis']![_entregaSelecionada] ?? 0.0;
//     if (subtotal < valorMinimo) {
//       return valorMinimo - subtotal;
//     }
//     return 0.0;
//   }
//
//   // Atualizar o valor da entrega
//   void atualizarEntrega(String entrega, double valor) {
//     _entregaSelecionada = entrega;
//     _valorEntregaNormal = valor;
//     _valorEntrega = valor;
//     notifyListeners();
//   }
//
//   // Aplicar desconto
//   void aplicarDesconto(double novoValor) {
//     _desconto = getSubtotal() - novoValor;
//     notifyListeners();
//   }
//
//
//   // Método para limpar o carrinho
//   void clearCarrinho() {
//     _carrinho.clear();
//     calcularTotal();
//     notifyListeners();
//   }
// }
