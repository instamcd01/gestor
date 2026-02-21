import 'package:flutter/material.dart';
import 'package:gestor/models/venda.dart';
// Importe o arquivo onde as classes Venda e ItemVenda estão definidas

class VendasProvider with ChangeNotifier {
  List<Venda> _vendas = [];

  List<Venda> get vendas => _vendas;

  // Função para adicionar uma venda ao histórico
  void adicionarVenda(Venda venda) {
    _vendas.add(venda);
    notifyListeners();
  }

  // Função para filtrar vendas por período
  List<Venda> filtrarVendasPorPeriodo(DateTime inicio, DateTime fim) {
    return _vendas
        .where((venda) =>
    venda.dataVenda.isAfter(inicio) && venda.dataVenda.isBefore(fim))
        .toList();
  }
}
