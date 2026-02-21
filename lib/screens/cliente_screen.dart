import 'package:flutter/material.dart';
import 'package:gestor/screens/adicionar_cliente_screen.dart';
import 'package:provider/provider.dart';

import '../providers/cliente_provider.dart';
import 'editar_cliente_screen.dart';
import 'cliente_detalhes_screen.dart';
import '../models/cliente.dart';

class ClientesScreen extends StatefulWidget {
  @override
  _ClientesScreenState createState() => _ClientesScreenState();
}

class _ClientesScreenState extends State<ClientesScreen> {
  String _filtroSaldo = 'Todos';
  String _textoPesquisa = '';

  @override
  void initState() {
    Future.microtask(() {
      Provider.of<ClientProvider>(context, listen: false).carregarClientesDoFirestore();
    });
  }

  void _cadastrarNovoCliente() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AdicionarClienteScreen(onSalvar: (cliente) {
          Provider.of<ClientProvider>(context, listen: false).addCliente(cliente);
        }),
      ),
    ).then((_) {
      Provider.of<ClientProvider>(context, listen: false).notifyListeners();
    });
  }

  void _aplicarFiltro() {
    Provider.of<ClientProvider>(context, listen: false).pesquisarClientes(_textoPesquisa);
  }

  void _verDetalhesCliente(Cliente cliente) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ClienteDetalhesScreen(cliente: cliente),
      ),
    );
  }

  List<Widget> _iconesDePets(Cliente cliente) {
    final counts = <String, int>{};

    for (final pet in cliente.pets) {
      counts[pet.especie] = (counts[pet.especie] ?? 0) + 1;
    }

    final emojiMap = {
      'Cão': '🐶',
      'Gato': '🐱',
      'Passarinho': '🐦',
      'Peixe': '🐟',
      'Coelho': '🐰',
    };

    List<Widget> emojis = [];

    for (var especie in counts.keys) {
      final emoji = emojiMap[especie];
      if (emoji != null) {
        emojis.add(Text(emoji * counts[especie]!));
      }
    }

    return emojis;
  }



  @override
  Widget build(BuildContext context) {
    final clientProvider = Provider.of<ClientProvider>(context);
    final clientesFiltrados = clientProvider.clientes;

    return Scaffold(
      appBar: AppBar(
        title: Text('Clientes (${clientesFiltrados.length})'),
        actions: [
          IconButton(
            icon: Icon(Icons.person_add),
            onPressed: _cadastrarNovoCliente,
            tooltip: 'Cadastrar Novo Cliente',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              onChanged: (texto) {
                setState(() {
                  _textoPesquisa = texto;
                });
                _aplicarFiltro();
              },
              decoration: InputDecoration(
                labelText: 'Pesquisar cliente',
                suffixIcon: Icon(Icons.search),
              ),
            ),
            SizedBox(height: 20),
            Expanded(
              child: clientesFiltrados.isEmpty
                  ? Center(child: Text('Nenhum cliente encontrado'))
                  : ListView.builder(
                itemCount: clientesFiltrados.length,
                itemBuilder: (context, index) {
                  final cliente = clientesFiltrados[index];
                  return Card(
                    child: ListTile(
                      title: Row(
                        children: [
                          Expanded(child: Text(cliente.nome)),
                          ..._iconesDePets(cliente),
                        ],
                      ),
                      subtitle: Text(
                        'Celular: ${cliente.celular} | Saldo: R\$${cliente.saldo.toStringAsFixed(2)}',
                      ),
                      onTap: () => _verDetalhesCliente(cliente),
                      trailing: IconButton(
                        icon: Icon(Icons.delete, color: Colors.red),
                        onPressed: () async {
                          final confirmar = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text('Excluir Cliente'),
                              content: Text('Tem certeza que deseja excluir ${cliente.nome}?'),
                              actions: [
                                TextButton(child: Text('Cancelar'), onPressed: () => Navigator.of(ctx).pop(false)),
                                TextButton(child: Text('Excluir'), onPressed: () => Navigator.of(ctx).pop(true)),
                              ],
                            ),
                          );
                          if (confirmar == true) {
                            clientProvider.removerClienteDoFirestore(cliente);
                          }
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
