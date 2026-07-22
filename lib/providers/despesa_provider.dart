import 'package:flutter/material.dart';
import '../models/despesa.dart';
import '../repositories/despesa_repository.dart';

class DespesaProvider with ChangeNotifier {
  final DespesaRepository _repository = DespesaRepository();

  List<Despesa> _despesas = [];
  bool _carregando = false;
  String? _erro;
  String? _empresaId;

  List<Despesa> get despesas => _despesas;
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
      _despesas = await _repository.listar();
    } catch (e) {
      _erro = 'Erro ao carregar despesas: $e';
      debugPrint(_erro);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> adicionar(Despesa despesa, {String? criadoPor}) async {
    if (_empresaId == null) {
      throw StateError('Nenhuma empresa definida no DespesaProvider ainda.');
    }
    await _repository.criar(despesa, empresaId: _empresaId!, criadoPor: criadoPor);
    await carregar();
  }

  Future<void> atualizar(Despesa despesa) async {
    await _repository.atualizar(despesa);
    await carregar();
  }

  Future<void> marcarComoPaga(String despesaId, {required String metodoPagamento}) async {
    await _repository.marcarComoPaga(despesaId, metodoPagamento: metodoPagamento);
    await carregar();
  }

  Future<void> cancelar(String despesaId) async {
    await _repository.cancelar(despesaId);
    await carregar();
  }

  Future<void> excluir(String despesaId) async {
    await _repository.excluir(despesaId);
    await carregar();
  }
}
