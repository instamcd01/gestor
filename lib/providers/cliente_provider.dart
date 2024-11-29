import 'package:flutter/material.dart';
import '../models/cliente.dart';

class ClienteProvider with ChangeNotifier {
  List<Cliente> _clientes = [];

  List<Cliente> get clientes => _clientes;

  void adicionarCliente(Cliente cliente) {
    _clientes.add(cliente);
    notifyListeners();
  }

  void editarCliente(String id, Cliente novoCliente) {
    final index = _clientes.indexWhere((cliente) => cliente.id == id);
    if (index >= 0) {
      _clientes[index] = novoCliente;
      notifyListeners();
    }
  }

  void removerCliente(String id) {
    _clientes.removeWhere((cliente) => cliente.id == id);
    notifyListeners();
  }
}
