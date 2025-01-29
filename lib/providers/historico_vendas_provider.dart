import 'package:flutter/material.dart';
import '../models/venda.dart';

class HistoricoVendasProvider with ChangeNotifier {
  final List<Venda> _vendas = [];

  List<Venda> get vendas => _vendas;

  void adicionarVenda(Venda venda) {
    _vendas.add(venda);
    notifyListeners();  // Notifica a tela de que os dados foram atualizados
  }
}
