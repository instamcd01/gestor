import 'package:flutter/material.dart';

class Pedido {
  final String codigo;
  final String cliente;
  final double valor;
  final String status;
  final String vendedor;

  Pedido({
    required this.codigo,
    required this.cliente,
    required this.valor,
    required this.status,
    required this.vendedor,
  });
}

class PedidoProvider with ChangeNotifier {
  final List<Pedido> _pedidos = [];

  List<Pedido> get pedidos => _pedidos;

  void adicionarPedido(Pedido pedido) {
    _pedidos.add(pedido);
    notifyListeners();
  }
}
