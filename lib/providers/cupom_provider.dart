import 'package:flutter/material.dart';
import '../models/cupom.dart';
import '../repositories/cupom_repository.dart';

class CupomProvider with ChangeNotifier {
  final CupomRepository _repository = CupomRepository();

  List<Cupom> _cupons = [];
  bool _carregando = false;
  String? _erro;
  String? _empresaId;

  List<Cupom> get cupons => _cupons;
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
      _cupons = await _repository.listar();
    } catch (e) {
      _erro = 'Erro ao carregar cupons: $e';
      debugPrint(_erro);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  Future<Cupom> adicionar(Cupom cupom, {List<String> produtoIds = const []}) async {
    if (_empresaId == null) {
      throw StateError('Nenhuma empresa definida no CupomProvider ainda.');
    }
    final novo = await _repository.criar(cupom, empresaId: _empresaId!);
    if (produtoIds.isNotEmpty && novo.id != null) {
      await _repository.definirProdutos(novo.id!, produtoIds);
    }
    _cupons.insert(0, novo);
    notifyListeners();
    return novo;
  }

  Future<void> atualizar(Cupom cupom, {List<String>? produtoIds}) async {
    await _repository.atualizar(cupom);
    if (produtoIds != null && cupom.id != null) {
      await _repository.definirProdutos(cupom.id!, produtoIds);
    }
    final index = _cupons.indexWhere((c) => c.id == cupom.id);
    if (index != -1) _cupons[index] = cupom;
    notifyListeners();
  }

  Future<void> alternarAtivo(Cupom cupom) async {
    if (cupom.ativo) {
      await _repository.desativar(cupom.id!);
    } else {
      await _repository.ativar(cupom.id!);
    }
    final index = _cupons.indexWhere((c) => c.id == cupom.id);
    if (index != -1) {
      _cupons[index] = Cupom(
        id: cupom.id,
        codigo: cupom.codigo,
        tipoDesconto: cupom.tipoDesconto,
        valor: cupom.valor,
        escopoTipo: cupom.escopoTipo,
        escopoValor: cupom.escopoValor,
        clienteId: cupom.clienteId,
        clienteNome: cupom.clienteNome,
        vendedorId: cupom.vendedorId,
        vendedorNome: cupom.vendedorNome,
        origem: cupom.origem,
        valorMinimoPedido: cupom.valorMinimoPedido,
        usoMaximo: cupom.usoMaximo,
        usos: cupom.usos,
        usoMaximoPorCliente: cupom.usoMaximoPorCliente,
        dataInicio: cupom.dataInicio,
        dataExpiracao: cupom.dataExpiracao,
        ativo: !cupom.ativo,
        descricao: cupom.descricao,
      );
    }
    notifyListeners();
  }
}
