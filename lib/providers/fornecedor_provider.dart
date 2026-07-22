import 'package:flutter/material.dart';
import '../models/fornecedor.dart';
import '../repositories/fornecedor_repository.dart';

class FornecedorProvider with ChangeNotifier {
  final FornecedorRepository _repository = FornecedorRepository();

  List<Fornecedor> _fornecedores = [];
  bool _carregando = false;
  String? _erro;
  String? _empresaId;

  List<Fornecedor> get fornecedores => _fornecedores;
  bool get carregando => _carregando;
  String? get erro => _erro;

  void definirEmpresa(String empresaId) {
    _empresaId = empresaId;
  }

  Future<void> carregar() async {
    _carregando = true;
    _erro = null;
    notifyListeners();

    try {
      _fornecedores = await _repository.listar();
    } catch (e) {
      _erro = 'Erro ao carregar fornecedores: $e';
      debugPrint(_erro);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<Fornecedor> adicionar(Fornecedor fornecedor) async {
    if (_empresaId == null) {
      throw StateError('Nenhuma empresa definida no FornecedorProvider ainda.');
    }
    final novo = await _repository.criar(fornecedor, empresaId: _empresaId!);
    _fornecedores.add(novo);
    _fornecedores.sort((a, b) => a.nome.compareTo(b.nome));
    notifyListeners();
    return novo;
  }

  Future<void> atualizar(Fornecedor fornecedor) async {
    await _repository.atualizar(fornecedor);
    final index = _fornecedores.indexWhere((f) => f.id == fornecedor.id);
    if (index != -1) _fornecedores[index] = fornecedor;
    notifyListeners();
  }

  Future<void> excluir(String fornecedorId) async {
    await _repository.excluir(fornecedorId);
    _fornecedores.removeWhere((f) => f.id == fornecedorId);
    notifyListeners();
  }
}
