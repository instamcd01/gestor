import 'package:flutter/material.dart';
import '../models/kit_produto.dart';
import '../repositories/kit_produto_repository.dart';

/// Espelha a estrutura de ProdutoProvider — lista de kits carregada,
/// métodos de carregar/criar/atualizar chamando o repository.
class KitProdutoProvider with ChangeNotifier {
  final KitProdutoRepository _repository = KitProdutoRepository();

  List<KitProduto> _kits = [];
  bool _carregando = false;
  String? _erro;
  String? _empresaId;

  List<KitProduto> get kits => _kits;
  bool get carregando => _carregando;
  String? get erro => _erro;

  void definirEmpresa(String empresaId) {
    _empresaId = empresaId;
  }

  Future<void> carregarKits() async {
    _carregando = true;
    _erro = null;
    notifyListeners();

    try {
      _kits = await _repository.listar();
    } catch (e) {
      _erro = 'Erro ao carregar kits: $e';
      debugPrint(_erro);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<KitProduto> adicionarKit(KitProduto kit) async {
    if (_empresaId == null) {
      throw StateError('Nenhuma empresa definida no KitProdutoProvider ainda.');
    }
    final kitCriado = await _repository.criar(kit, empresaId: _empresaId!);
    _kits.add(kitCriado);
    notifyListeners();
    return kitCriado;
  }

  Future<void> atualizarKit(KitProduto kit) async {
    if (_empresaId == null) {
      throw StateError('Nenhuma empresa definida no KitProdutoProvider ainda.');
    }
    if (kit.id == null) {
      debugPrint('Erro: kit sem id para atualização.');
      return;
    }
    await _repository.atualizar(kit, empresaId: _empresaId!);
    final index = _kits.indexWhere((k) => k.id == kit.id);
    if (index != -1) _kits[index] = kit;
    notifyListeners();
  }

  Future<void> excluirKit(String id) async {
    await _repository.excluir(id);
    _kits.removeWhere((k) => k.id == id);
    notifyListeners();
  }
}
