// import 'package:diacritic/diacritic.dart';
// import 'package:flutter/material.dart';
//
// class ClientProvider with ChangeNotifier {
//   // Lista de clientes
//   List<String> _clientes = ['João', 'Maria', 'Carlos', 'Ana', 'Felipe'];
//
//   // Lista de clientes filtrados para a pesquisa
//   List<String> _clientesFiltrados = [];
//
//   // Cliente selecionado
//   String? _clienteSelecionado;
//
//   // Getter para acessar a lista de clientes (filtrados ou completos)
//   List<String> get clientes => _clientesFiltrados.isEmpty ? _clientes : _clientesFiltrados;
//
//   String? get clienteSelecionado => _clienteSelecionado;
//
//   // Função para adicionar um cliente
//   void addCliente(String cliente) {
//     _clientes.add(cliente);
//     notifyListeners(); // Notifica os listeners para atualizar a UI
//   }
//
//   // Função para remover um cliente
//   void removeCliente(String cliente) {
//     _clientes.remove(cliente);
//     notifyListeners(); // Notifica os listeners para atualizar a UI
//   }
//
//   // Função para pesquisar clientes (filtro)
//   void pesquisarClientes(String texto) {
//     if (texto.isEmpty) {
//       _clientesFiltrados.clear(); // Se o texto estiver vazio, exibe todos os clientes
//     } else {
//       // Normaliza o texto (remove acentos e converte para minúsculo)
//       String textoNormalizado = removeDiacritics(texto).toLowerCase();
//
//       // Filtra a lista de clientes
//       _clientesFiltrados = _clientes
//           .where((cliente) {
//         // Normaliza o nome do cliente (remove acentos e converte para minúsculo)
//         String clienteNormalizado = removeDiacritics(cliente).toLowerCase();
//         // Compara o nome normalizado com o texto da pesquisa
//         return clienteNormalizado.contains(textoNormalizado);
//       })
//           .toList();
//     }
//     notifyListeners(); // Notifica os listeners para atualizar a UI
//   }
//
//
//   // Função para definir o cliente selecionado
//   void setClienteSelecionado(String cliente) {
//     _clienteSelecionado = cliente;
//     notifyListeners(); // Notifica os listeners para atualizar a UI
//   }
// }


import 'package:diacritic/diacritic.dart';
import 'package:flutter/material.dart';
import '../models/cliente.dart';

class ClientProvider with ChangeNotifier {
  // Lista de clientes
  List<Cliente> _clientes = [
    Cliente(
      idCliente: '1',
      nome: 'João',
      celular: '123456789',
      email: 'joao@exemplo.com',
      endereco: 'Rua Exemplo, 123',
      complemento: 'Apto 101',
      cpf: '123.456.789-00',
      pet: ['Cachorro'],
      observacao: 'Cliente VIP',
      saldo: 100.50,
    ),
    Cliente(
      idCliente: '2',
      nome: 'Maria',
      celular: '987654321',
      email: 'maria@exemplo.com',
      endereco: 'Av. Central, 456',
      complemento: 'Bloco B',
      cpf: '987.654.321-00',
      pet: ['Gato', 'Papagaio'],
      observacao: 'Frequente',
      saldo: 50.00,
    ),
    // Adicione outros clientes conforme necessário
  ];

  // Lista de clientes filtrados para pesquisa
  List<Cliente> _clientesFiltrados = [];

  // Cliente selecionado
  Cliente? _clienteSelecionado;

  // Getter para acessar a lista de clientes (filtrados ou completos)
  List<Cliente> get clientes => _clientesFiltrados.isEmpty ? _clientes : _clientesFiltrados;

  Cliente? get clienteSelecionado => _clienteSelecionado;

  // Função para adicionar um cliente
  void addCliente(Cliente cliente) {
    _clientes.add(cliente);
    notifyListeners(); // Notifica os listeners para atualizar a UI
  }

  // Método para atualizar um cliente existente
  void atualizarCliente(Cliente clienteAtualizado) {
    int index = _clientes.indexWhere((cliente) => cliente.idCliente == clienteAtualizado.idCliente);
    if (index != -1) {
      _clientes[index] = clienteAtualizado; // Atualiza o cliente
      notifyListeners(); // Notifica os ouvintes de que o cliente foi atualizado
    }
  }
  // Função para remover um cliente
  // Função para remover cliente
  void removeCliente(Cliente cliente) {
    _clientes.removeWhere((item) => item.idCliente == cliente.idCliente); // Remover cliente baseado no ID
    notifyListeners();
  }
  // Função para buscar cliente por nome
  Cliente? buscarClientePorNome(String nome) {
    return _clientes.firstWhere(
          (cliente) => cliente.nome.toLowerCase() == nome.toLowerCase(),
      // orElse: () => null, // Retorna null se o cliente não for encontrado
    );
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
        // Normaliza todas as variáveis do cliente (remove acentos e converte para minúsculo)
        String nomeNormalizado = removeDiacritics(cliente.nome).toLowerCase();
        String celularNormalizado = removeDiacritics(cliente.celular).toLowerCase();
        String emailNormalizado = removeDiacritics(cliente.email).toLowerCase();
        String enderecoNormalizado = removeDiacritics(cliente.endereco).toLowerCase();
        String complementoNormalizado = removeDiacritics(cliente.complemento).toLowerCase();
        String cpfNormalizado = removeDiacritics(cliente.cpf).toLowerCase();
        String petNormalizado = removeDiacritics(cliente.pet.join(" ")).toLowerCase();
        String observacaoNormalizada = removeDiacritics(cliente.observacao).toLowerCase();

        // Compara todos os campos normalizados com o texto de pesquisa
        return nomeNormalizado.contains(textoNormalizado) ||
            celularNormalizado.contains(textoNormalizado) ||
            emailNormalizado.contains(textoNormalizado) ||
            enderecoNormalizado.contains(textoNormalizado) ||
            complementoNormalizado.contains(textoNormalizado) ||
            cpfNormalizado.contains(textoNormalizado) ||
            petNormalizado.contains(textoNormalizado) ||
            observacaoNormalizada.contains(textoNormalizado);
      })
          .toList();
    }
    notifyListeners(); // Notifica os listeners para atualizar a UI
  }

  // Função para definir o cliente selecionado
  void setClienteSelecionado(Cliente cliente) {
    _clienteSelecionado = cliente;
    notifyListeners(); // Notifica os listeners para atualizar a UI
  }
}
