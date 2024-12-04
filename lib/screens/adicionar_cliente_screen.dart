import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AdicionarClienteScreen extends StatefulWidget {
  final Function(String) onSalvar; // Callback para salvar o cliente

  AdicionarClienteScreen({required this.onSalvar});

  @override
  _AdicionarClienteScreenState createState() => _AdicionarClienteScreenState();
}

class _AdicionarClienteScreenState extends State<AdicionarClienteScreen> {
  final _nomeController = TextEditingController();
  final _celularController = TextEditingController();
  final _enderecoController = TextEditingController();
  final _emailController = TextEditingController();
  final _cpfController = TextEditingController();

  // Lista de opções de pets
  final List<String> _pets = ['Cão', 'Gato', 'Passarinho', 'Peixe', 'Coelho'];
  // Lista para armazenar os pets selecionados
  List<String> _petsSelecionados = [];

  void salvarCliente() {
    final nome = _nomeController.text;
    if (nome.isEmpty) return; // Verifica se o nome foi preenchido
    // Adiciona a informação dos pets ao nome antes de salvar
    // final petsInfo = _petsSelecionados.isNotEmpty
    //     ? 'Pets: ${_petsSelecionados.join(', ')}'
    //     : 'Sem pets';

    widget.onSalvar('$nome '
        // '- $petsInfo'
    ); // Chama a função de salvar com o nome e pets

    Navigator.pop(context); // Volta para a tela anterior
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Adicionar Cliente'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: _nomeController,
              decoration: InputDecoration(labelText: 'Nome'),
            ),
            TextField(
              controller: _celularController,
              decoration: InputDecoration(labelText: 'Celular'),
            ),
            TextField(
              controller: _enderecoController,
              decoration: InputDecoration(labelText: 'Endereço'),
            ),
            TextField(
              controller: _emailController,
              decoration: InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: _cpfController,
              decoration: InputDecoration(labelText: 'CPF'),
            ),
            SizedBox(height: 20),
            // Seção de seleção de pets
            Text('Selecione os pets que o cliente possui:'),
            ..._pets.map((pet) => CheckboxListTile(
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
            )),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: salvarCliente,
              child: Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}

// import 'package:flutter/material.dart';
// import 'package:uuid/uuid.dart';
// import '../banco de dados/cliente_dao.dart';
// import '../models/cliente.dart';
//
// class AdicionarClienteScreen extends StatefulWidget {
//   final Function(Cliente) onSalvar; // Callback para salvar o cliente
//
//   AdicionarClienteScreen({required this.onSalvar});
//
//   @override
//   _AdicionarClienteScreenState createState() => _AdicionarClienteScreenState();
// }
//
// class _AdicionarClienteScreenState extends State<AdicionarClienteScreen> {
//   final _nomeController = TextEditingController();
//   final _celularController = TextEditingController();
//   final _enderecoController = TextEditingController();
//   final _emailController = TextEditingController();
//   final _cpfController = TextEditingController();
//
//   // Lista de opções de pets
//   final List<String> _pets = ['Cão', 'Gato', 'Passarinho', 'Peixe', 'Coelho'];
//   List<String> _petsSelecionados = [];
//
//   void salvarCliente() async {
//     final nome = _nomeController.text.trim();
//     final celular = _celularController.text.trim();
//     final endereco = _enderecoController.text.trim();
//     final email = _emailController.text.trim();
//     final cpf = _cpfController.text.trim();
//     final pet = _petsSelecionados.join(', '); // Junta os pets selecionados
//
//     // Verifica se os campos obrigatórios foram preenchidos
//     if (nome.isEmpty || celular.isEmpty || endereco.isEmpty) {
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text('Por favor, preencha todos os campos obrigatórios.')),
//       );
//       return;
//     }
//
//     // Cria o cliente com um ID único
//     final cliente = Cliente(
//       id: Uuid().v4(),
//       nome: nome,
//       celular: celular,
//       email: email,
//       endereco: endereco,
//       cpf: cpf,
//       pet: pet,
//       saldo: 0.0, // Define saldo como 0.0
//     );
//
//     // Salva no banco de dados
//     final clienteDao = ClienteDao();
//     await clienteDao.inserirCliente(cliente);
//
//     // Chama o callback para atualizar a lista na tela anterior
//     widget.onSalvar(cliente);
//
//     // Volta para a tela anterior
//     Navigator.pop(context);
//   }
//
//   @override
//   void dispose() {
//     _nomeController.dispose();
//     _celularController.dispose();
//     _enderecoController.dispose();
//     _emailController.dispose();
//     _cpfController.dispose();
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('Adicionar Cliente'),
//       ),
//       body: SingleChildScrollView(
//         padding: const EdgeInsets.all(16.0),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: <Widget>[
//             TextField(
//               controller: _nomeController,
//               decoration: InputDecoration(
//                 labelText: 'Nome *',
//                 border: OutlineInputBorder(),
//               ),
//             ),
//             SizedBox(height: 10),
//             TextField(
//               controller: _celularController,
//               decoration: InputDecoration(
//                 labelText: 'Celular *',
//                 border: OutlineInputBorder(),
//               ),
//               keyboardType: TextInputType.phone,
//             ),
//             SizedBox(height: 10),
//             TextField(
//               controller: _enderecoController,
//               decoration: InputDecoration(
//                 labelText: 'Endereço *',
//                 border: OutlineInputBorder(),
//               ),
//             ),
//             SizedBox(height: 10),
//             TextField(
//               controller: _emailController,
//               decoration: InputDecoration(
//                 labelText: 'Email',
//                 border: OutlineInputBorder(),
//               ),
//               keyboardType: TextInputType.emailAddress,
//             ),
//             SizedBox(height: 10),
//             TextField(
//               controller: _cpfController,
//               decoration: InputDecoration(
//                 labelText: 'CPF',
//                 border: OutlineInputBorder(),
//               ),
//               keyboardType: TextInputType.number,
//             ),
//             SizedBox(height: 20),
//             // Seção de seleção de pets
//             Text('Selecione os pets que o cliente possui:'),
//             ..._pets.map((pet) => CheckboxListTile(
//               title: Text(pet),
//               value: _petsSelecionados.contains(pet),
//               onChanged: (bool? value) {
//                 setState(() {
//                   if (value == true) {
//                     _petsSelecionados.add(pet);
//                   } else {
//                     _petsSelecionados.remove(pet);
//                   }
//                 });
//               },
//             )),
//             SizedBox(height: 20),
//             ElevatedButton(
//               onPressed: salvarCliente,
//               child: Text('Salvar'),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }
