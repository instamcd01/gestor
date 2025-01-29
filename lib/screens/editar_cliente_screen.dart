// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import '../providers/cliente_provider.dart';
// import 'adicionar_cliente_screen.dart'; // Importe a tela de adicionar cliente
//
// class EditarClienteScreen extends StatefulWidget {
//   @override
//   _EditarClienteScreenState createState() =>
//       _EditarClienteScreenState();
// }
//
// class _EditarClienteScreenState extends State<EditarClienteScreen> {
//   @override
//   Widget build(BuildContext context) {
//     // Obtém o ClientProvider
//     final clientProvider = Provider.of<ClientProvider>(context);
//
//     // Função para pesquisar clientes
//     void pesquisarCliente(String texto) {
//       // Chama a função de pesquisa do provider
//       setState(() {
//         clientProvider.pesquisarClientes(texto);
//       });
//     }
//
//     // Função para importar clientes da lista de contatos
//     void importarClientes() {
//       print('Importando contatos...');
//     }
//
// // Função para selecionar o cliente
//     void selecionarCliente(String cliente) {
//       clientProvider.setClienteSelecionado(cliente); // Define o cliente selecionado no provider
//       Navigator.pop(context); // Volta para a tela de pagamento
//     }
//
//     // Função para adicionar um novo cliente
//     void adicionarNovoCliente() {
//       Navigator.push(
//         context,
//         MaterialPageRoute(
//           builder: (context) => AdicionarClienteScreen(
//             onSalvar: (nome) {
//               clientProvider.addCliente(nome as String); // Adiciona o cliente ao provider
//               Navigator.pop(context); // Volta para a tela de cadastro com lista atualizada
//             },
//           ),
//         ),
//       );
//     }
//
//     // Função para desvincular um cliente
//     void desvincularCliente(String cliente) {
//       clientProvider.removeCliente(cliente); // Remove o cliente do provider
//     }
//
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('Editar Cliente'),
//         actions: [
//           IconButton(
//             icon: Icon(Icons.contacts),
//             onPressed: importarClientes,
//             tooltip: 'Importar Clientes',
//           ),
//           IconButton(
//             icon: Icon(Icons.add),
//             onPressed: adicionarNovoCliente,
//             tooltip: 'Adicionar Novo Cliente',
//           ),
//         ],
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: Column(
//           children: [
//             // Campo de pesquisa
//             TextField(
//               onChanged: pesquisarCliente,
//               decoration: InputDecoration(
//                 labelText: 'Pesquisar Cliente',
//                 prefixIcon: Icon(Icons.search),
//                 border: OutlineInputBorder(),
//               ),
//             ),
//             SizedBox(height: 20),
//
//             // Lista de clientes
//             Expanded(
//               child: ListView.builder(
//                 itemCount: clientProvider.clientes.length,
//                 itemBuilder: (context, index) {
//                   final cliente = clientProvider.clientes[index];
//                   return ListTile(
//                     title: Text(cliente),
//                     onTap: () => selecionarCliente(cliente), // Seleciona o cliente ao clicar
//                   );
//                 },
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }



import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cliente_provider.dart';
import '../models/cliente.dart'; // Certifique-se de que o modelo Cliente está importado

class EditarClienteScreen extends StatefulWidget {
  final Cliente clienteSelecionado;

  // Lista de opções de pets
  final List<String> _pets = ['Cão', 'Gato', 'Passarinho', 'Peixe', 'Coelho'];

  // Construtor
  EditarClienteScreen({required this.clienteSelecionado});

  @override
  _EditarClienteScreenState createState() => _EditarClienteScreenState();
}

class _EditarClienteScreenState extends State<EditarClienteScreen> {
  late TextEditingController _nomeController;
  late TextEditingController _celularController;
  late TextEditingController _enderecoController;
  late TextEditingController _complementoController;
  late TextEditingController _emailController;
  late TextEditingController _cpfController;
  late TextEditingController _observacaoController;
  late TextEditingController _saldoController;
  late TextEditingController _idController;

  // Lista de pets selecionados
  List<String> _petsSelecionados = [];

  @override
  void initState() {
    super.initState();

    // Inicializa os controllers com os dados do cliente selecionado
    final cliente = widget.clienteSelecionado;
    _nomeController = TextEditingController(text: cliente.nome);
    _celularController = TextEditingController(text: cliente.celular);
    _enderecoController = TextEditingController(text: cliente.endereco);
    _complementoController = TextEditingController(text: cliente.complemento);
    _emailController = TextEditingController(text: cliente.email);
    _cpfController = TextEditingController(text: cliente.cpf);
    _observacaoController = TextEditingController(text: cliente.observacao);
    _saldoController = TextEditingController(text: cliente.saldo.toString());
    _idController = TextEditingController(text: cliente.idCliente);
    _petsSelecionados = cliente.pet.toList(); // Carrega os pets selecionados
  }

  @override
  void dispose() {
    // Limpeza dos controllers quando a tela for descartada
    _nomeController.dispose();
    _celularController.dispose();
    _enderecoController.dispose();
    _complementoController.dispose();
    _emailController.dispose();
    _cpfController.dispose();
    _observacaoController.dispose();
    _saldoController.dispose();
    _idController.dispose();
    super.dispose();
  }

  // Função para salvar os dados atualizados
  void _salvarCliente() {
    final updatedCliente = Cliente(
      nome: _nomeController.text,
      celular: _celularController.text,
      endereco: _enderecoController.text,
      complemento: _complementoController.text,
      email: _emailController.text,
      cpf: _cpfController.text,
      observacao: _observacaoController.text,
      saldo: double.tryParse(_saldoController.text) ?? 0.0,
      idCliente: _idController.text,
      pet: _petsSelecionados,
    );

    // Atualiza o cliente no provider
    final clientProvider = Provider.of<ClientProvider>(context, listen: false);
    clientProvider.atualizarCliente(updatedCliente);

    // Volta para a tela anterior
    Navigator.pop(context, updatedCliente);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Editar Cliente'),
        actions: [
          IconButton(
            icon: Icon(Icons.save),
            onPressed: _salvarCliente,
            tooltip: 'Salvar',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: <Widget>[
            _buildTextField('Nome', _nomeController),
            _buildTextField('Celular', _celularController),
            _buildTextField('Endereço', _enderecoController),
            _buildTextField('Complemento', _complementoController),
            _buildTextField('Email', _emailController),
            _buildTextField('CPF', _cpfController),
            _buildTextField('Observação', _observacaoController),
            _buildTextField('Saldo', _saldoController),
            SizedBox(height: 20),
            _buildPetSelection(),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _salvarCliente,
              child: Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  // Widget reutilizável para criar campos de texto editáveis
  Widget _buildTextField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(),
        ),
      ),
    );
  }

  // Função para criar a seção de seleção de pets
  Widget _buildPetSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Selecione os pets que o cliente possui:'),
        ...widget._pets.map((pet) {
          return CheckboxListTile(
            title: Text(pet),
            value: _petsSelecionados.contains(pet),
            onChanged: (bool? value) {
              setState(() {
                if (value == true) {
                  _petsSelecionados.add(pet);
                } else {
                  _petsSelecionados.remove(pet);
                }
              });
            },
          );
        }).toList(),
      ],
    );
  }
}






// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import '../providers/cliente_provider.dart';
// import 'adicionar_cliente_screen.dart'; // Importe a tela de adicionar cliente
// import '../models/cliente.dart'; // Certifique-se de que o modelo Cliente está importado
//
// class EditarClienteScreen extends StatefulWidget {
//   @override
//   _EditarClienteScreenState createState() => _EditarClienteScreenState();
// }
//
// class _EditarClienteScreenState extends State<EditarClienteScreen> {
//   @override
//   Widget build(BuildContext context) {
//     // Obtém o ClientProvider
//     final clientProvider = Provider.of<ClientProvider>(context);
//
//     // Função para pesquisar clientes
//     void pesquisarCliente(String texto) {
//       setState(() {
//         clientProvider.pesquisarClientes(texto); // Pesquisa os clientes no provider
//       });
//     }
//
//     // Função para importar clientes da lista de contatos
//     void importarClientes() {
//       print('Importando contatos...');
//       // Aqui, você pode adicionar lógica para importar contatos, se necessário
//     }
//
//     // Função para selecionar o cliente
//     void selecionarCliente(Cliente cliente) {
//       clientProvider.setClienteSelecionado(cliente); // Define o cliente selecionado
//       Navigator.pop(context); // Volta para a tela anterior
//     }
//
//     // Função para adicionar um novo cliente
//     void adicionarNovoCliente() {
//       Navigator.push(
//         context,
//         MaterialPageRoute(
//           builder: (context) => AdicionarClienteScreen(
//             onSalvar: (Cliente novoCliente) {
//               clientProvider.addCliente(novoCliente); // Adiciona o cliente ao provider
//               Navigator.pop(context); // Volta para a tela de edição
//             },
//           ),
//         ),
//       );
//     }
//
//     // Função para desvincular um cliente
//     void desvincularCliente(Cliente cliente) {
//       clientProvider.removeCliente(cliente); // Remove o cliente do provider
//     }
//
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('Editar Cliente'),
//         actions: [
//           IconButton(
//             icon: Icon(Icons.contacts),
//             onPressed: importarClientes,
//             tooltip: 'Importar Clientes',
//           ),
//           IconButton(
//             icon: Icon(Icons.add),
//             onPressed: adicionarNovoCliente,
//             tooltip: 'Adicionar Novo Cliente',
//           ),
//         ],
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: Column(
//           children: [
//             // Campo de pesquisa
//             TextField(
//               onChanged: pesquisarCliente,
//               decoration: InputDecoration(
//                 labelText: 'Pesquisar Cliente',
//                 prefixIcon: Icon(Icons.search),
//                 border: OutlineInputBorder(),
//               ),
//             ),
//             SizedBox(height: 20),
//
//             // Lista de clientes
//             Expanded(
//               child: ListView.builder(
//                 itemCount: clientProvider.clientes.length,
//                 itemBuilder: (context, index) {
//                   final Cliente cliente = clientProvider.clientes[index];
//                   return ListTile(
//                     title: Text(cliente.nome), // Exibe o nome do cliente
//                     onTap: () => selecionarCliente(cliente), // Seleciona o cliente
//                     trailing: IconButton(
//                       icon: Icon(Icons.delete),
//                       onPressed: () => desvincularCliente(cliente), // Remove o cliente
//                     ),
//                   );
//                 },
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
