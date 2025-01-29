import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/cliente.dart';
import '../providers/cliente_provider.dart';

class AdicionarClienteScreen extends StatefulWidget {
  final Function(Cliente) onSalvar; // Callback para salvar o cliente

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
  final _idController = TextEditingController();
  final _complementoController = TextEditingController();
  final _observacaoController = TextEditingController();
  final _saldoController = TextEditingController();

  // Lista de opções de pets
  final List<String> _pets = ['Cão', 'Gato', 'Passarinho', 'Peixe', 'Coelho'];
  // Lista para armazenar os pets selecionados
  List<String> _petsSelecionados = [];

  // void salvarCliente() {
  //   final nome = _nomeController.text;
  //   final celular = _celularController.text;
  //   final endereco = _enderecoController.text;
  //   final email = _emailController.text;
  //   final cpf = _cpfController.text;
  //   final id = _idController.text;
  //   final complemento = _complementoController.text;
  //   final observacao = _observacaoController.text;
  //   final saldo = _saldoController.text;
  //
  //   if (nome.isEmpty || celular.isEmpty) return; // Verifica se nome e celular foram preenchidos
  //
  //   // Cria o objeto Cliente com os dados
  //   final novoCliente = Cliente(
  //     nome: nome,
  //     celular: celular,
  //     endereco: endereco,
  //     email: email,
  //     cpf: cpf,
  //     pet: _petsSelecionados,
  //     id: id,
  //     complemento: complemento,
  //     observacao: observacao,
  //     saldo: double.tryParse(saldo) ?? 0.0,
  //   );
  //
  //   widget.onSalvar(novoCliente); // Passa o Cliente para o callback
  //
  //   Navigator.pop(context); // Volta para a tela anterior
  // }

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

    // Atualiza ou adiciona o cliente no provider
    final clientProvider = Provider.of<ClientProvider>(context, listen: false);

    // Verifica se o cliente selecionado possui um ID. Se tiver, é uma atualização, caso contrário, é uma criação.
    // if (widget.clienteSelecionado != null && widget.clienteSelecionado!.id.isNotEmpty) {
    //   clientProvider.atualizarCliente(updatedCliente); // Atualiza o cliente
    // } else {
      clientProvider.addCliente(updatedCliente); // Adiciona um novo cliente


    // Volta para a tela anterior
    Navigator.pop(context);
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Adicionar Cliente'),
      ),
      body: SingleChildScrollView(
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
              controller: _complementoController,
              decoration: InputDecoration(labelText: 'Complemento'),
            ),
            TextField(
              controller: _emailController,
              decoration: InputDecoration(labelText: 'Email'),
            ),
            TextField(
              controller: _cpfController,
              decoration: InputDecoration(labelText: 'CPF'),
            ),
            TextField(
              controller: _observacaoController,
              decoration: InputDecoration(labelText: 'Observação'),
            ),
            TextField(
              controller: _saldoController,
              decoration: InputDecoration(labelText: 'Saldo'),
            ),
            TextField(
              controller: _idController,
              decoration: InputDecoration(labelText: 'Id'),
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
            Center(
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _salvarCliente,
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 16.0),
                    textStyle: TextStyle(fontSize: 18),
                  ),
                  child: Text('Salvar'),
                ),
              ),
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
//       saldo: 0.0, complemento: '', observacao: '', // Define saldo como 0.0
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
