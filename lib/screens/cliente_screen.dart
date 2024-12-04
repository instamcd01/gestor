import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../banco de dados/cliente_dao.dart';
import '../models/cliente.dart';
import 'cadastrar_cliente_screen.dart';


class ClientesScreen extends StatefulWidget {
  @override
  _ClientesScreenState createState() => _ClientesScreenState();
}

class _ClientesScreenState extends State<ClientesScreen> {
  // Lista de clientes carregada
  List<Cliente> _clientes = [];
  List<Cliente> _clientesFiltrados = [];
  String _filtroSaldo = 'Todos'; // Filtro por saldo: 'Todos', 'Positivo', 'Negativo'

  @override
  void initState() {
    super.initState();
    _carregarClientes();
  }

  void _carregarClientes() async {
    final clienteDao = ClienteDao();
    final clientes = await clienteDao.buscarClientes();
    setState(() {
      _clientes = clientes;
      _clientesFiltrados = clientes;
    });
  }
  // Função para navegar para a tela de cadastro de cliente
  void cadastrarNovoCliente() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CadastrarClienteScreen(),
      ),
    );
  }

  // Função para filtrar clientes
  void _filtrarClientes() {
    setState(() {
      if (_filtroSaldo == 'Positivo') {
        _clientesFiltrados = _clientes.where((cliente) => cliente.saldo > 0).toList();
      } else if (_filtroSaldo == 'Negativo') {
        _clientesFiltrados = _clientes.where((cliente) => cliente.saldo < 0).toList();
      } else {
        _clientesFiltrados = _clientes;
      }
    });
  }

  // Função para adicionar um cliente
  void _adicionarCliente() {
    // Redireciona para a tela de adicionar cliente
    Navigator.pushNamed(context, '/adicionar_cliente').then((_) {
      _carregarClientes(); // Atualiza a lista após adicionar um novo cliente
    });
  }

  // Função para exportar relatório
  void _exportarRelatorio() {
    // Implementação da exportação (pode ser para um arquivo CSV ou PDF)
  }

  // Função para importar clientes
  void _importarClientes() {
    // Implementação da importação de clientes (ex: via arquivo CSV)
  }

  @override
  Widget build(BuildContext context) {
    final int quantidadeClientes = _clientesFiltrados.length;

    double saldoPositivo = _clientesFiltrados.where((cliente) => cliente.saldo > 0).fold(0.0, (sum, cliente) => sum + cliente.saldo);
    double saldoNegativo = _clientesFiltrados.where((cliente) => cliente.saldo < 0).fold(0.0, (sum, cliente) => sum + cliente.saldo);

    return Scaffold(
      appBar: AppBar(
        title: Text('Clientes ($quantidadeClientes)'),
        actions: <Widget>[
          IconButton(
            icon: Icon(Icons.import_export),
            onPressed: _exportarRelatorio,
          ),
          IconButton(
            icon: Icon(Icons.file_upload),
            onPressed: _importarClientes,
          ),
          IconButton(
           icon: Icon(Icons.person_add),
            onPressed: cadastrarNovoCliente,
            tooltip: 'Cadastrar Novo Cliente',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: <Widget>[
            // Filtro de saldo
            Row(
              children: <Widget>[
                Text('Filtro de saldo: '),
                DropdownButton<String>(
                  value: _filtroSaldo,
                  onChanged: (String? novoValor) {
                    if (novoValor != null) {
                      setState(() {
                        _filtroSaldo = novoValor;
                      });
                      _filtrarClientes(); // Aplica o filtro
                    }
                  },
                  items: <String>['Todos', 'Positivo', 'Negativo']
                      .map<DropdownMenuItem<String>>((String valor) {
                    return DropdownMenuItem<String>(
                      value: valor,
                      child: Text(valor),
                    );
                  }).toList(),
                ),
              ],
            ),
            SizedBox(height: 20),
            // Lista de clientes
            Expanded(
              child: ListView.builder(
                itemCount: _clientesFiltrados.length,
                itemBuilder: (context, index) {
                  final cliente = _clientesFiltrados[index];
                  return ListTile(
                    title: Text(cliente.nome),
                    subtitle: Text('Saldo: ${cliente.saldo.toStringAsFixed(2)}'),
                  );
                },
              ),
            ),
            // Exibir saldo total
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Text('Saldo total negativo: ${saldoNegativo.toStringAsFixed(2)}'),
                  Text('Saldo total positivo: ${saldoPositivo.toStringAsFixed(2)}'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
