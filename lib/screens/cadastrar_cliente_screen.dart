import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cliente_provider.dart';
import 'adicionar_cliente_screen.dart'; // Importe a tela de adicionar cliente

class CadastrarClienteScreen extends StatefulWidget {
  @override
  _CadastrarClienteScreenState createState() =>
      _CadastrarClienteScreenState();
}

class _CadastrarClienteScreenState extends State<CadastrarClienteScreen> {
  @override
  Widget build(BuildContext context) {
    // Obtém o ClientProvider
    final clientProvider = Provider.of<ClientProvider>(context);

    // Função para pesquisar clientes
    void pesquisarCliente(String texto) {
      // Chama a função de pesquisa do provider
      setState(() {
        clientProvider.pesquisarClientes(texto);
      });
    }

    // Função para importar clientes da lista de contatos
    void importarClientes() {
      print('Importando contatos...');
    }

// Função para selecionar o cliente
    void selecionarCliente(String cliente) {
      clientProvider.setClienteSelecionado(cliente); // Define o cliente selecionado no provider
      Navigator.pop(context); // Volta para a tela de pagamento
    }

    // Função para adicionar um novo cliente
    void adicionarNovoCliente() {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => AdicionarClienteScreen(
            onSalvar: (nome) {
              clientProvider.addCliente(nome); // Adiciona o cliente ao provider
              Navigator.pop(context); // Volta para a tela de cadastro com lista atualizada
            },
          ),
        ),
      );
    }

    // Função para desvincular um cliente
    void desvincularCliente(String cliente) {
      clientProvider.removeCliente(cliente); // Remove o cliente do provider
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Cadastrar Cliente'),
        actions: [
          IconButton(
            icon: Icon(Icons.contacts),
            onPressed: importarClientes,
            tooltip: 'Importar Clientes',
          ),
          IconButton(
            icon: Icon(Icons.add),
            onPressed: adicionarNovoCliente,
            tooltip: 'Adicionar Novo Cliente',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Campo de pesquisa
            TextField(
              onChanged: pesquisarCliente,
              decoration: InputDecoration(
                labelText: 'Pesquisar Cliente',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 20),

            // Lista de clientes
            Expanded(
              child: ListView.builder(
                itemCount: clientProvider.clientes.length,
                itemBuilder: (context, index) {
                  final cliente = clientProvider.clientes[index];
                  return ListTile(
                    title: Text(cliente),
                    onTap: () => selecionarCliente(cliente), // Seleciona o cliente ao clicar
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