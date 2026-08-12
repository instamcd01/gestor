import 'package:flutter/material.dart';

import '../models/entregador.dart';
import '../repositories/entregador_repository.dart';

class EntregadorProvider with ChangeNotifier {
  final EntregadorRepository _repository = EntregadorRepository();

  List<Entregador> _entregadores = [];
  bool _carregando = false;
  String? _erro;
  String? _empresaId;

  List<Entregador> get entregadores => _entregadores;
  List<Entregador> get ativos => _entregadores.where((e) => e.ativo).toList();
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
      _entregadores = await _repository.listar();
    } catch (e) {
      _erro = 'Erro ao carregar entregadores: $e';
      debugPrint(_erro);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> criar(Entregador entregador) async {
    if (_empresaId == null) {
      throw StateError('Nenhuma empresa definida no EntregadorProvider ainda.');
    }
    await _repository.criar(entregador, empresaId: _empresaId!);
    await carregar();
  }

  Future<void> atualizar(Entregador entregador) async {
    await _repository.atualizar(entregador);
    await carregar();
  }

  Future<void> excluir(String id) async {
    await _repository.excluir(id);
    await carregar();
  }
}
