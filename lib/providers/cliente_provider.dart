import 'package:diacritic/diacritic.dart';
import 'package:flutter/material.dart';
import '../models/cliente.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ClientProvider with ChangeNotifier {
  // Lista de clientes
  List<Cliente> _clientes = [
  ];

  // Lista de clientes filtrados para pesquisa
  List<Cliente> _clientesFiltrados = [];

  // Cliente selecionado
  Cliente? _clienteSelecionado;

  // Getter para acessar a lista de clientes (filtrados ou completos)
  List<Cliente> get clientes => _clientesFiltrados.isEmpty ? _clientes : _clientesFiltrados;

  Cliente? get clienteSelecionado => _clienteSelecionado;

  Future<void> addCliente(Cliente cliente) async {
    try {
      final firestore = FirebaseFirestore.instance;
      await firestore
          .collection('clientes')
          .doc(cliente.idCliente)
          .set(cliente.toMap());

      _clientes.add(cliente);
      notifyListeners();
      print('✅ Cliente adicionado e salvo no Firestore');
    } catch (e) {
      print('❌ Erro ao adicionar cliente: $e');
    }
  }

  Future<void> carregarClientesDoFirestore() async {
    final firestore = FirebaseFirestore.instance;

    try {
      final snapshot = await FirebaseFirestore.instance.collection('clientes').get();

      print('📥 Total de documentos encontrados: ${snapshot.docs.length}');

      final List<Cliente> clientesFirestore = snapshot.docs.map((doc) {
        print('🔎 Documento: ${doc.data()}');
        final data = doc.data();
        return Cliente.fromMap(data);
      }).toList();

      _clientes = clientesFirestore;
      notifyListeners();

      print('✅ Clientes carregados: ${_clientes.length}');
    } catch (e) {
      print('❌ Erro ao carregar clientes: $e');
    }
  }

  // Método para atualizar um cliente existente
  Future<void> atualizarCliente(Cliente clienteAtualizado) async {
    try {
      final firestore = FirebaseFirestore.instance;

      await firestore
          .collection('clientes')
          .doc(clienteAtualizado.idCliente)
          .set(clienteAtualizado.toMap());

      int index = _clientes.indexWhere((cliente) => cliente.idCliente == clienteAtualizado.idCliente);
      if (index != -1) {
        _clientes[index] = clienteAtualizado;
      } else {
        _clientes.add(clienteAtualizado); // fallback de segurança
      }

      notifyListeners();
      print('✅ Cliente atualizado no Firestore');
    } catch (e) {
      print('❌ Erro ao atualizar cliente no Firestore: $e');
    }
  }

  // Função para remover um cliente
  // Função para remover cliente
  Future<void> removerClienteDoFirestore(Cliente cliente) async {
    final firestore = FirebaseFirestore.instance;

    try {
      // Remove do Firestore
      await firestore.collection('clientes').doc(cliente.idCliente).delete();

      // Remove localmente
      _clientes.removeWhere((item) => item.idCliente == cliente.idCliente);
      notifyListeners();

      print('🗑️ Cliente removido do Firestore: ${cliente.nome}');
    } catch (e) {
      print('❌ Erro ao remover cliente do Firestore: $e');
    }
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
      _clientesFiltrados = List.from(_clientes); // ← ANTES estava clear()
    } else {
      String textoNormalizado = removeDiacritics(texto).toLowerCase();

      _clientesFiltrados = _clientes.where((cliente) {
        final nome = removeDiacritics(cliente.nome).toLowerCase();
        final celular = removeDiacritics(cliente.celular).toLowerCase();
        final email = removeDiacritics(cliente.email).toLowerCase();
        final endereco = removeDiacritics(cliente.endereco).toLowerCase();
        final complemento = removeDiacritics(cliente.complemento).toLowerCase();
        final cpf = removeDiacritics(cliente.cpf).toLowerCase();
        final pet = removeDiacritics(cliente.especies.join(" ")).toLowerCase();
        final observacao = removeDiacritics(cliente.observacao).toLowerCase();

        return nome.contains(textoNormalizado) ||
            celular.contains(textoNormalizado) ||
            email.contains(textoNormalizado) ||
            endereco.contains(textoNormalizado) ||
            complemento.contains(textoNormalizado) ||
            cpf.contains(textoNormalizado) ||
            pet.contains(textoNormalizado) ||
            observacao.contains(textoNormalizado);
      }).toList();
    }

    notifyListeners();
  }

  // Função para definir o cliente selecionado
  void setClienteSelecionado(Cliente cliente) {
    _clienteSelecionado = cliente;
    notifyListeners(); // Notifica os listeners para atualizar a UI
  }
}
final _firestore = FirebaseFirestore.instance;

Future<List<String>> carregarCanaisOrigem() async {
  try {
    final snapshot = await _firestore.collection('canais_origem').get();
    final canais = snapshot.docs.map((doc) => doc['nome'] as String).toList();
    return canais;
  } catch (e) {
    print('❌ Erro ao carregar canais: $e');
    return ['WhatsApp', 'Instagram', 'Ifood', 'Outro canal'];
  }
}

Future<void> adicionarCanalOrigem(String canal) async {
  try {
    final snapshot = await _firestore
        .collection('canais_origem')
        .where('nome', isEqualTo: canal)
        .get();

    if (snapshot.docs.isEmpty) {
      await _firestore.collection('canais_origem').add({'nome': canal});
    }
  } catch (e) {
    print('❌ Erro ao salvar canal: $e');
  }
}
