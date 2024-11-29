import 'package:flutter/material.dart';

class VendasProvider with ChangeNotifier {
  List<Map<String, dynamic>> _vendas = [];

  List<Map<String, dynamic>> get vendas => _vendas;

  void registrarVenda(Map<String, dynamic> venda) {
    _vendas.add(venda);
    notifyListeners();
  }

  List<Map<String, dynamic>> filtrarVendasPorPeriodo(DateTime inicio, DateTime fim) {
    return _vendas
        .where((venda) =>
    venda['data'].isAfter(inicio) && venda['data'].isBefore(fim))
        .toList();
  }
}

