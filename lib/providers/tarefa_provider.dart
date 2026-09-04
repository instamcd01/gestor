import 'package:flutter/material.dart';
import '../models/tarefa.dart';
import '../repositories/tarefa_repository.dart';

class TarefaProvider with ChangeNotifier {
  final TarefaRepository _repository = TarefaRepository();

  List<Tarefa> _tarefas = [];
  bool _carregando = false;
  String? _erro;
  String? _empresaId;

  List<Tarefa> get tarefas => _tarefas;
  bool get carregando => _carregando;
  String? get erro => _erro;

  List<Tarefa> get tarefasPendentesHoje {
    final hoje = DateTime.now();
    return _tarefas
        .where((t) =>
            !t.concluida &&
            t.data.year == hoje.year &&
            t.data.month == hoje.month &&
            t.data.day == hoje.day)
        .toList();
  }

  void definirEmpresa(String empresaId) {
    _empresaId = empresaId;
  }

  Future<void> carregar() async {
    _carregando = true;
    _erro = null;
    notifyListeners();

    try {
      _tarefas = await _repository.listar();
    } catch (e) {
      _erro = 'Erro ao carregar tarefas: $e';
      debugPrint(_erro);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<void> adicionar(Tarefa tarefa, {String? criadoPor}) async {
    if (_empresaId == null) {
      throw StateError('Nenhuma empresa definida no TarefaProvider ainda.');
    }
    await _repository.criar(tarefa, empresaId: _empresaId!, criadoPor: criadoPor);
    await carregar();
  }

  Future<void> atualizar(Tarefa tarefa) async {
    await _repository.atualizar(tarefa);
    await carregar();
  }

  Future<void> concluir(String tarefaId, {required String concluidaPor}) async {
    await _repository.concluir(tarefaId, concluidaPor: concluidaPor);
    await carregar();
  }

  Future<void> reabrir(String tarefaId) async {
    await _repository.reabrir(tarefaId);
    await carregar();
  }

  Future<void> excluir(String tarefaId) async {
    await _repository.excluir(tarefaId);
    await carregar();
  }
}
