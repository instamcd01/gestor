import 'package:diacritic/diacritic.dart';
import 'package:flutter/material.dart';

class ClientProvider with ChangeNotifier {
  // Lista de clientes
  List<String> _clientes = ['João', 'Maria', 'Carlos', 'Ana', 'Felipe'];

  // Lista de clientes filtrados para a pesquisa
  List<String> _clientesFiltrados = [];

  // Cliente selecionado
  String? _clienteSelecionado;

  // Getter para acessar a lista de clientes (filtrados ou completos)
  List<String> get clientes => _clientesFiltrados.isEmpty ? _clientes : _clientesFiltrados;

  String? get clienteSelecionado => _clienteSelecionado;

  // Função para adicionar um cliente
  void addCliente(String cliente) {
    _clientes.add(cliente);
    notifyListeners(); // Notifica os listeners para atualizar a UI
  }

  // Função para remover um cliente
  void removeCliente(String cliente) {
    _clientes.remove(cliente);
    notifyListeners(); // Notifica os listeners para atualizar a UI
  }

  // Função para pesquisar clientes (filtro)
  void pesquisarClientes(String texto) {
    if (texto.isEmpty) {
      _clientesFiltrados.clear(); // Se o texto estiver vazio, exibe todos os clientes
    } else {
      // Normaliza o texto (remove acentos e converte para minúsculo)
      String textoNormalizado = removeDiacritics(texto).toLowerCase();

      // Filtra a lista de clientes
      _clientesFiltrados = _clientes
          .where((cliente) {
        // Normaliza o nome do cliente (remove acentos e converte para minúsculo)
        String clienteNormalizado = removeDiacritics(cliente).toLowerCase();
        // Compara o nome normalizado com o texto da pesquisa
        return clienteNormalizado.contains(textoNormalizado);
      })
          .toList();
    }
    notifyListeners(); // Notifica os listeners para atualizar a UI
  }

  // Função para definir o cliente selecionado
  void setClienteSelecionado(String cliente) {
    _clienteSelecionado = cliente;
    notifyListeners(); // Notifica os listeners para atualizar a UI
  }
}
