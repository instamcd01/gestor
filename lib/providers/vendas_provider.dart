// import 'package:flutter/material.dart';
//
// class VendasProvider with ChangeNotifier {
//   List<Map<String, dynamic>> _vendas = [];
//
//   List<Map<String, dynamic>> get vendas => _vendas;
//
//   void adicionarVenda(Map<String, dynamic> venda) {
//     _vendas.add(venda);
//     notifyListeners();
//   }
//
//   List<Map<String, dynamic>> filtrarVendasPorPeriodo(DateTime inicio, DateTime fim) {
//     return _vendas
//         .where((venda) =>
//     venda['data'].isAfter(inicio) && venda['data'].isBefore(fim))
//         .toList();
//   }
// }
//


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
