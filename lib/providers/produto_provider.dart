import 'package:flutter/material.dart';
import '../models/produto.dart';
import '../repositories/produto_repository.dart';

class ProdutoProvider with ChangeNotifier {
  final ProdutoRepository _repository = ProdutoRepository();

  List<Produto> _produtos = [];
  bool _carregando = false;
  String? _erro;
  String? _empresaId;

  List<Produto> get produtos => _produtos;
  bool get carregando => _carregando;
  String? get erro => _erro;

  /// Chamado uma vez pelo AuthGate assim que sabemos a empresa do usuário
  /// logado — necessário pra criar novos produtos (empresa_id é obrigatório).
  void definirEmpresa(String empresaId) {
    _empresaId = empresaId;
  }

  Future<void> carregarProdutos() async {
    _carregando = true;
    _erro = null;
    notifyListeners();

    try {
      _produtos = await _repository.listar();
    } catch (e) {
      _erro = 'Erro ao carregar produtos: $e';
      debugPrint(_erro);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  /// Mantido pelo nome antigo por compatibilidade com telas existentes.
  Future<void> atualizarProdutosDoFirestore() async {
    await carregarProdutos();
  }

  Future<Produto> adicionarProduto(Produto produto) async {
    if (_empresaId == null) {
      throw StateError('Nenhuma empresa definida no ProdutoProvider ainda.');
    }
    try {
      final novoProduto = await _repository.criar(produto, empresaId: _empresaId!);
      _produtos.add(novoProduto);
      notifyListeners();
      return novoProduto;
    } catch (e) {
      debugPrint('Erro ao adicionar produto: $e');
      rethrow;
    }
  }

  Future<void> atualizarProduto(Produto produto) async {
    if (produto.id == null || produto.id!.isEmpty) {
      debugPrint('Erro: produto sem id para atualização.');
      return;
    }
    try {
      await _repository.atualizar(produto);
      final index = _produtos.indexWhere((p) => p.id == produto.id);
      if (index != -1) {
        _produtos[index] = produto;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Erro ao atualizar produto: $e');
      rethrow;
    }
  }

  Produto? getProdutoPorId(String id) {
    try {
      return _produtos.firstWhere((p) => p.id == id);
    } catch (e) {
      return null;
    }
  }

  Future<void> deletarProduto(String id) async {
    if (id.isEmpty) return;
    try {
      await _repository.excluir(id);
      _produtos.removeWhere((produto) => produto.id == id);
      notifyListeners();
    } catch (e) {
      debugPrint('Erro ao deletar produto: $e');
      rethrow;
    }
  }
}
