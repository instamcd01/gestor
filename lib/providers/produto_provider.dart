// import 'dart:async';
//
// import 'package:flutter/material.dart';
// import 'package:cloud_firestore/cloud_firestore.dart'; // Importar Firestore
// import '../models/produto.dart'; // Mantenha seu modelo Produto
//
// class ProdutoProvider with ChangeNotifier {
//   final FirebaseFirestore _firestore = FirebaseFirestore.instance; // Instância do Firestore
//   final String _collectionName = 'produtos'; // Nome da sua coleção no Firestore
//
//   List<Produto> _produtos = [];
//   // StreamSubscription<QuerySnapshot>? _produtosSubscription;
//   List<Produto> get produtos => _produtos;
//
//   // Carregar produtos do Firestore
//   Future<void> carregarProdutos() async {
//     try {
//       QuerySnapshot snapshot = await _firestore.collection(_collectionName).get();
//       _produtos = snapshot.docs.map((doc) {
//         // É crucial que seu modelo Produto tenha um construtor fromMap/fromJson
//         // e um método toMap/toJson para conversão.
//         final data = doc.data() as Map<String, dynamic>;
//         return Produto.fromMap(data, doc.id); // Passando o ID do documento
//       }).toList();
//       notifyListeners();
//     } catch (e) {
//       print("Erro ao carregar produtos: $e");
//       // Considere adicionar um tratamento de erro mais robusto aqui
//     }
//   }
//   Future<void> atualizarProdutosDoFirestore() async {
//     await carregarProdutos(); // ou qualquer método que busque os dados do Firestore
//     notifyListeners();
//   }
//   // Adicionar um novo produto ao Firestore
//   Future<void> adicionarProduto(Produto produto) async {
//     try {
//       // O Firestore gerará um ID automaticamente se você não especificar um .document()
//       DocumentReference docRef = await _firestore.collection(_collectionName).add(produto.toMap());
//       // Atualizar o ID do produto local com o ID gerado pelo Firestore
//       produto.id = docRef.id; // Supondo que seu modelo Produto tenha um campo 'id' mutável ou um método para atualizá-lo
//       _produtos.add(produto); // Adiciona à lista local para atualização imediata da UI
//       notifyListeners();
//     } catch (e) {
//       print("Erro ao adicionar produto: $e");
//     }
//   }
//
//   // Atualizar um produto existente no Firestore
//   Future<void> atualizarProduto(Produto produto) async {
//     if (produto.id == null || produto.id!.isEmpty) {
//       print("Erro: ID do produto é nulo ou vazio para atualização.");
//       return;
//     }
//     try {
//       await _firestore.collection(_collectionName).doc(produto.id).update(produto.toMap());
//       // Atualizar na lista local
//       final index = _produtos.indexWhere((p) => p.id == produto.id);
//       if (index != -1) {
//         _produtos[index] = produto;
//       }
//       notifyListeners();
//     } catch (e) {
//       print("Erro ao atualizar produto: $e");
//     }
//   }
//
//   // NOVO MÉTODO: Atualizar o estoque de um produto específico
//
//   Future<void> atualizarEstoqueProduto(String produtoId, int quantidadeVendida) async {
//     if (produtoId.isEmpty) {
//       print("Erro: ID do produto é nulo ou vazio para atualização de estoque.");
//       return;
//     }
//     try {
//       DocumentReference produtoRef = _firestore.collection(_collectionName).doc(produtoId);
//
//       // É crucial usar uma transação para garantir que a leitura e escrita do estoque
//       // sejam atômicas, evitando condições de corrida se múltiplas vendas ocorrerem simultaneamente.
//       await _firestore.runTransaction((transaction) async {
//         DocumentSnapshot snapshot = await transaction.get(produtoRef);
//
//         if (!snapshot.exists) {
//           throw Exception("Produto com ID $produtoId não encontrado!");
//         }
//
//         // Assumindo que 'estoqueAtual' é um campo numérico no Firestore
//         int estoqueAtual = (snapshot.data() as Map<String, dynamic>)['estoqueAtual'] ?? 0;
//         int novoEstoque = estoqueAtual - quantidadeVendida;
//
//         if (novoEstoque < 0) {
//           // Opcional: Lançar um erro ou impedir a venda se o estoque ficar negativo.
//           // Por enquanto, vamos permitir, mas você pode querer adicionar lógica aqui.
//           print("Atenção: Estoque do produto $produtoId ficará negativo: $novoEstoque");
//         }
//         transaction.update(produtoRef, {'estoqueAtual': novoEstoque});
//       });
//
//       // A lista local _produtos será atualizada automaticamente pelo Stream (ouvirMudancasProdutos)
//       // Se não estivesse usando Stream, você precisaria atualizar manualmente aqui e notificar.
//       print('Estoque do produto $produtoId atualizado para um novo valor após venda.');
//
//     } catch (e) {
//       print("Erro ao atualizar estoque do produto $produtoId: $e");
//       rethrow; // Propaga o erro para ser tratado na UI, se necessário
//     }
//   }
//
//   // Método para buscar um produto pelo ID (pode ser útil)
//   Produto? getProdutoPorId(String id) {
//     try {
//       return _produtos.firstWhere((p) => p.id == id);
//     } catch (e) {
//       return null; // Produto não encontrado na lista local
//     }
//   }
//
//
//   // Deletar um produto do Firestore
//   Future<void> deletarProduto(String id) async { // ID agora é String
//     if (id.isEmpty) {
//       print("Erro: ID do produto é nulo ou vazio para deleção.");
//       return;
//     }
//     try {
//       await _firestore.collection(_collectionName).doc(id).delete();
//       _produtos.removeWhere((produto) => produto.id == id);
//       notifyListeners();
//     } catch (e) {
//       print("Erro ao deletar produto: $e");
//     }
//   }
//
//   Future<void> buscarImagemAutomatica(String produtoId) async {
//     final produto = getProdutoPorId(produtoId);
//     if (produto == null || produto.codigoBarras.isEmpty) return;
//
//     try {
//       // TODO: Substitua por sua API real que retorna imagem pelo código de barras
//       String imagemUrl = await buscarImagemPorCodigoBarras(produto.codigoBarras);
//
//       produto.imagemAutomaticaUrl = imagemUrl;
//       // Atualiza produto no Firestore e na lista local
//       await atualizarProduto(produto);
//     } catch (e) {
//       print("Erro ao buscar imagem automática para $produtoId: $e");
//     }
//   }
//
//   // Função de exemplo que simula a busca de imagem
//   Future<String> buscarImagemPorCodigoBarras(String codigoBarras) async {
//     // Substitua pelo endpoint real da sua API
//     await Future.delayed(Duration(seconds: 1));
//     return 'https://via.placeholder.com/150?text=$codigoBarras';
//   }
// }
//


import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Importar Firestore
import '../models/produto.dart'; // Modelo Produto

class ProdutoProvider with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance; // Instância do Firestore
  final String _collectionName = 'produtos'; // Nome da coleção no Firestore

  List<Produto> _produtos = [];
  List<Produto> get produtos => _produtos;

  // Carregar produtos do Firestore
  Future<void> carregarProdutos() async {
    try {
      QuerySnapshot snapshot = await _firestore.collection(_collectionName).get();
      _produtos = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return Produto.fromMap(data, doc.id);
      }).toList();
      notifyListeners();
    } catch (e) {
      print("Erro ao carregar produtos: $e");
    }
  }

  // Atualiza produtos do Firestore
  Future<void> atualizarProdutosDoFirestore() async {
    await carregarProdutos();
    notifyListeners();
  }

  // Adicionar um novo produto
  Future<void> adicionarProduto(Produto produto) async {
    try {
      DocumentReference docRef = await _firestore.collection(_collectionName).add(produto.toMap());
      produto.id = docRef.id; // Atualiza ID local
      _produtos.add(produto);
      notifyListeners();
    } catch (e) {
      print("Erro ao adicionar produto: $e");
    }
  }

  // Atualizar produto existente
  Future<void> atualizarProduto(Produto produto) async {
    if (produto.id == null || produto.id!.isEmpty) {
      print("Erro: ID do produto é nulo ou vazio para atualização.");
      return;
    }
    try {
      await _firestore.collection(_collectionName).doc(produto.id).update(produto.toMap());
      final index = _produtos.indexWhere((p) => p.id == produto.id);
      if (index != -1) {
        _produtos[index] = produto;
      }
      notifyListeners();
    } catch (e) {
      print("Erro ao atualizar produto: $e");
    }
  }

  // Atualizar estoque de um produto específico
  Future<void> atualizarEstoqueProduto(String produtoId, int quantidadeVendida) async {
    if (produtoId.isEmpty) {
      print("Erro: ID do produto é nulo ou vazio para atualização de estoque.");
      return;
    }
    try {
      DocumentReference produtoRef = _firestore.collection(_collectionName).doc(produtoId);

      await _firestore.runTransaction((transaction) async {
        DocumentSnapshot snapshot = await transaction.get(produtoRef);

        if (!snapshot.exists) {
          throw Exception("Produto com ID $produtoId não encontrado!");
        }

        int estoqueAtual = (snapshot.data() as Map<String, dynamic>)['estoqueAtual'] ?? 0;
        int novoEstoque = estoqueAtual - quantidadeVendida;

        if (novoEstoque < 0) {
          print("Atenção: Estoque do produto $produtoId ficará negativo: $novoEstoque");
        }
        transaction.update(produtoRef, {'estoqueAtual': novoEstoque});
      });

      print('Estoque do produto $produtoId atualizado.');
    } catch (e) {
      print("Erro ao atualizar estoque do produto $produtoId: $e");
      rethrow;
    }
  }

  // Buscar produto pelo ID
  Produto? getProdutoPorId(String id) {
    try {
      return _produtos.firstWhere((p) => p.id == id);
    } catch (e) {
      return null;
    }
  }

  // Deletar um produto
  Future<void> deletarProduto(String id) async {
    if (id.isEmpty) {
      print("Erro: ID do produto é nulo ou vazio para deleção.");
      return;
    }
    try {
      await _firestore.collection(_collectionName).doc(id).delete();
      _produtos.removeWhere((produto) => produto.id == id);
      notifyListeners();
    } catch (e) {
      print("Erro ao deletar produto: $e");
    }
  }

  // ===========================
  // NOVA FUNÇÃO ADICIONADA
  // Gera automaticamente a URL da imagem do servidor baseado no código de barras
  // ===========================
  void buscarImagemAutomatica(String produtoId) {
    Produto? produto = getProdutoPorId(produtoId);
    if (produto == null) return;

    if (produto.codigoBarras.isNotEmpty) {
      // Alteração: define imagemAutomaticaUrl baseado no código de barras
      produto.imagemAutomaticaUrl = 'http://imagens.lukz.com.br/produtos/${produto.codigoBarras}.png';
      notifyListeners(); // Notifica a UI para atualizar
    }
  }
}
