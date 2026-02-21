// import 'package:flutter/material.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import '../models/pet.dart';
// import '../models/venda.dart';
// import '../models/cliente.dart';
// import '../models/produto.dart';
//
// class HistoricoVendasProvider with ChangeNotifier {
//   final List<Venda> _vendas = [];
//   final FirebaseFirestore _firestore = FirebaseFirestore.instance;
//
//   List<Venda> get vendas => _vendas;
//
//   void adicionarVenda(Venda venda) {
//     _vendas.add(venda);
//     notifyListeners();
//   }
//
//   Future<void> carregarVendasDoFirestore() async {
//     try {
//       final snapshot = await _firestore.collection('vendas').orderBy('dataVenda', descending: true).get();
//       _vendas.clear();
//
//       for (var doc in snapshot.docs) {
//         final data = doc.data();
//
//         final itensData = data['itens'] as List<dynamic>;
//         final itens = itensData.map((item) {
//           final produtoData = item['produto'] ?? {};
//           return ItemVenda(
//             produto: Produto(
//               id: produtoData['id'] ?? '',
//               nome: produtoData['nome'] ?? '',
//               preco: (produtoData['preco'] ?? 0).toDouble(),
//               descricao: produtoData['descricao'] ?? '',
//               categoria: produtoData['categoria'] ?? '',
//               estoqueAtual: produtoData['estoqueAtual'] ?? 0,
//               estoqueMinimo: produtoData['estoqueMinimo'] ?? 0,
//               imagemUrl: produtoData['imagemUrl'] ?? '',
//               codigoBarras: produtoData['codigoBarras'] ?? '',
//               custo: (produtoData['custo'] ?? 0).toDouble(),
//             ),
//             quantidade: item['quantidade'] ?? 0,
//             precoTotal: item['precoTotal']?.toDouble() ?? 0.0,
//           );
//         }).toList();
//
//         final clienteData = data['cliente'] ?? {};
//         final cliente = Cliente(
//           idCliente: clienteData['idCliente'] ?? '',
//           nome: clienteData['nome'] ?? '',
//           celular: clienteData['celular'] ?? '',
//           email: clienteData['email'] ?? '',
//           endereco: clienteData['endereco'] ?? '',
//           complemento: clienteData['complemento'] ?? '',
//           cpf: clienteData['cpf'] ?? '',
//           observacao: clienteData['observacao'] ?? '',
//           saldo: (clienteData['saldo'] ?? 0.0).toDouble(),
//           pets: (clienteData['pets'] as List?)?.map((p) => Pet.fromMap(p)).toList() ?? [],
//
//         );
//
//         _vendas.add(
//           Venda(
//             idVenda: doc.id,
//             cliente: cliente,
//             itens: itens,
//             valorTotal: (data['valorTotal'] ?? 0).toDouble(),
//             dataVenda: (data['dataVenda'] as Timestamp).toDate(),
//             metodoPagamento: data['metodoPagamento'] ?? '',
//           ),
//         );
//       }
//
//       notifyListeners();
//     } catch (e) {
//       print('Erro ao carregar vendas do Firestore: $e');
//     }
//   }
// }


import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/pet.dart';
import '../models/venda.dart';
import '../models/cliente.dart';
import '../models/produto.dart';

class HistoricoVendasProvider with ChangeNotifier {
  final List<Venda> _vendas = [];
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  double saldoUsado = 0.0;
  List<Venda> get vendas => _vendas;

  void adicionarVenda(Venda venda) {
    _vendas.add(venda);
    notifyListeners();
  }

  Future<void> carregarVendasDoFirestore() async {
    try {
      final snapshot = await _firestore
          .collection('vendas')
          .orderBy('dataVenda', descending: true)
          .get();

      _vendas.clear();

      for (var doc in snapshot.docs) {
        final data = doc.data();

        // ---- Processar itens da venda ----
        final itensData = data['itens'] as List<dynamic>? ?? [];
        final itens = itensData.map((item) {
          final precoUnitario = (item['precoUnitario'] ?? item['preco'] ?? 0).toDouble();
          final quantidade = (item['quantidade'] ?? 0).toInt();
          final custoUnitario = (item['custoUnitario'] ?? item['custo'] ?? 0).toDouble();
          final lucroUnitario = precoUnitario - custoUnitario;

          return ItemVenda(
            produto: Produto(
              id: item['produtoId'] ?? '',
              nome: item['nomeProduto'] ?? '',
              preco: precoUnitario,
              descricao: item['descricaoProduto'] ?? '',
              categoria: item['categoriaProduto'] ?? '',
              estoqueAtual: (item['estoqueAtual'] ?? 0).toInt(),
              estoqueMinimo: (item['estoqueMinimo'] ?? 0).toInt(),
              imagemUrl: item['imagemUrl'] ?? '',
              codigoBarras: item['codigoBarras'] ?? '',
              custo: custoUnitario,
            ),
            quantidade: quantidade,
            precoUnitario: precoUnitario,
            // precoTotal: precoUnitario * quantidade,
            // custoUnitario: custoUnitario,
            // custoTotal: custoUnitario * quantidade,
            // lucroUnitario: lucroUnitario,
            // lucroTotal: lucroUnitario * quantidade,
          );
        }).toList();

        // ---- Calcular totais ----
        final subtotal = itens.fold<double>(0, (sum, i) => sum + i.precoTotal);
        final totalItens = itens.fold<int>(0, (sum, i) => sum + i.quantidade);
        final custoTotal = itens.fold<double>(0, (sum, i) => sum + i.custoTotal);
        final lucroTotal = itens.fold<double>(0, (sum, i) => sum + i.lucroTotal);

        // ---- Processar cliente ----
        final cliente = Cliente(
          idCliente: data['idCliente'] ?? '',
          nome: data['nomeCliente'] ?? 'Cliente não informado',
          celular: data['celularCliente'] ?? '',
          email: data['emailCliente'] ?? '',
          endereco: data['enderecoCliente'] ?? '',
          complemento: data['complementoCliente'] ?? '',
          cpf: data['cpfCliente'] ?? '',
          observacao: data['observacoes'] ?? '',
          saldo: (data['saldoCliente'] ?? 0).toDouble(),
          pets: [],
        );

        // ---- Obter dados de entrega e desconto ----
        final desconto = (data['desconto'] ?? 0).toDouble();
        final valorEntrega = (data['valorEntrega'] ?? 0).toDouble();
        final entregaSelecionada = data['entregaSelecionada'] ?? '';

        Map<String, double>? pagamentosDetalhados; // ✅ Alteração
        if (data.containsKey('pagamentosDetalhados')) { // ✅ Alteração
          pagamentosDetalhados = (data['pagamentosDetalhados'] as Map<String, dynamic>)
              .map((key, value) => MapEntry(key, (value as num).toDouble())); // ✅ Alteração
        }

        // ---- Adicionar venda na lista ----
        _vendas.add(
          Venda(
            idVenda: doc.id,
            cliente: cliente,
            dataVenda: (data['dataVenda'] is Timestamp)
                ? (data['dataVenda'] as Timestamp).toDate()
                : DateTime.tryParse(data['dataVenda'].toString()) ?? DateTime.now(),
            subtotal: subtotal,
            desconto: desconto,
            saldoUsado: doc['saldoUsado'] ?? 0.0,
            valorEntrega: valorEntrega,
            entregaSelecionada: entregaSelecionada,
            valorTotal: (data['valorTotal'] ?? subtotal - desconto + valorEntrega).toDouble(),
            valorPago: (data['valorPago'] ?? 0).toDouble(),
            troco: (data['troco'] ?? 0).toDouble(),
            metodoPagamento: data['metodoPagamento'] ?? '',
            pagamentosDetalhados: pagamentosDetalhados,
            totalItens: totalItens,
            custoTotal: custoTotal,
            lucroTotal: lucroTotal,
            observacao: data['observacao'] ?? '',
            itens: itens,
          ),
        );
      }

      notifyListeners();
    } catch (e) {
      print('Erro ao carregar vendas do Firestore: $e');
    }
  }
}


