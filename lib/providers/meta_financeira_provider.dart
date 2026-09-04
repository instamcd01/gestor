import 'package:flutter/material.dart';
import '../models/meta_financeira.dart';
import '../models/periodo_planejamento.dart';
import '../repositories/meta_financeira_repository.dart';

class MetaFinanceiraProvider with ChangeNotifier {
  final MetaFinanceiraRepository _repository = MetaFinanceiraRepository();

  String? _empresaId;
  bool _carregando = false;
  String? _erro;
  MetaFinanceira? _meta;
  double _realizado = 0;

  bool get carregando => _carregando;
  String? get erro => _erro;
  MetaFinanceira? get meta => _meta;
  double get realizado => _realizado;

  void definirEmpresa(String empresaId) {
    _empresaId = empresaId;
  }

  Future<void> carregar(PeriodoSelecionado periodo) async {
    if (_empresaId == null) return;
    _carregando = true;
    _erro = null;
    notifyListeners();

    try {
      _meta = await _repository.buscar(periodoTipo: periodo.tipo.name, periodoInicio: periodo.inicio);
      _realizado = await _repository.buscarRealizado(inicio: periodo.inicio, fim: periodo.fim);
    } catch (e) {
      _erro = 'Erro ao carregar meta financeira: $e';
      debugPrint(_erro);
    }

    _carregando = false;
    notifyListeners();
  }

  Future<void> salvar(PeriodoSelecionado periodo, double valorMeta, {String? criadoPor}) async {
    if (_empresaId == null) {
      throw StateError('Nenhuma empresa definida no MetaFinanceiraProvider ainda.');
    }
    await _repository.salvar(
      MetaFinanceira(periodoTipo: periodo.tipo.name, periodoInicio: periodo.inicio, valorMeta: valorMeta),
      empresaId: _empresaId!,
      criadoPor: criadoPor,
    );
    await carregar(periodo);
  }
}
