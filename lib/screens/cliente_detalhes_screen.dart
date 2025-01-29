// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import '../providers/cliente_provider.dart';
//
// class ClienteDetalhesScreen extends StatefulWidget {
//   final String clienteNome;
//
//   ClienteDetalhesScreen({required this.clienteNome});
//
//   @override
//   _ClienteDetalhesScreenState createState() => _ClienteDetalhesScreenState();
// }
//
// class _ClienteDetalhesScreenState extends State<ClienteDetalhesScreen> {
//   String _selectedTab = 'Dados'; // Tab selecionada inicial
//   late String _nome, _celular, _email, _endereco, _complemento, _cpfCnpj, _observacao;
//
//   @override
//   void initState() {
//     super.initState();
//     // Inicializando os dados do cliente (normalmente isso viria do Provider ou de um banco de dados)
//     final clientProvider = Provider.of<ClientProvider>(context, listen: false);
//     final cliente = clientProvider.clientes.firstWhere((cliente) => cliente == widget.clienteNome);
//     _nome = cliente;
//     _celular = '123456789';
//     _email = 'cliente@exemplo.com';
//     _endereco = 'Rua Exemplo, 123';
//     _complemento = 'Apto 101';
//     _cpfCnpj = '123.456.789-00';
//     _observacao = 'Nenhuma observação';
//   }
//
//   // Função para deletar cliente
//   void _deletarCliente() {
//     final clientProvider = Provider.of<ClientProvider>(context, listen: false);
//     clientProvider.removeCliente(widget.clienteNome);
//     Navigator.pop(context);
//   }
//
//   // Função para editar dados do cliente
//   void _editarCliente() {
//     // Exemplo de lógica para editar o cliente
//     // Poderia abrir um formulário para editar os dados
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text(widget.clienteNome),
//         actions: <Widget>[
//           IconButton(
//             icon: Icon(Icons.delete),
//             onPressed: _deletarCliente,
//           ),
//         ],
//       ),
//       body: Column(
//         children: <Widget>[
//           // Seleção entre Dados, Vendas, Pedidos, Conta
//           DefaultTabController(
//             length: 4,
//             child: Column(
//               children: <Widget>[
//                 TabBar(
//                   onTap: (index) {
//                     setState(() {
//                       _selectedTab = ['Dados', 'Vendas', 'Pedidos', 'Conta'][index];
//                     });
//                   },
//                   tabs: [
//                     Tab(text: 'Dados'),
//                     Tab(text: 'Vendas'),
//                     Tab(text: 'Pedidos'),
//                     Tab(text: 'Conta'),
//                   ],
//                 ),
//                 Container(
//                   height: 500, // Ajuste conforme necessário
//                   child: TabBarView(
//                     children: [
//                       // Dados do cliente
//                       _selectedTab == 'Dados' ? _buildDadosTab() : Container(),
//                       // Vendas
//                       _selectedTab == 'Vendas' ? _buildVendasTab() : Container(),
//                       // Pedidos
//                       _selectedTab == 'Pedidos' ? _buildPedidosTab() : Container(),
//                       // Conta
//                       _selectedTab == 'Conta' ? _buildContaTab() : Container(),
//                     ],
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildDadosTab() {
//     return Padding(
//       padding: const EdgeInsets.all(16.0),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: <Widget>[
//           // Imagem do cliente
//           Row(
//             children: <Widget>[
//               CircleAvatar(
//                 radius: 40,
//                 backgroundColor: Colors.grey[300],
//                 child: Icon(Icons.camera_alt, size: 40),
//               ),
//               IconButton(
//                 icon: Icon(Icons.add_a_photo),
//                 onPressed: () {
//                   // Ação para adicionar ou remover a imagem
//                 },
//               ),
//             ],
//           ),
//           // Botões de WhatsApp, E-mail e Endereço
//           Row(
//             mainAxisAlignment: MainAxisAlignment.spaceBetween,
//             children: <Widget>[
//               IconButton(
//                 icon: Icon(Icons.message),
//                 onPressed: () {
//                   // Redirecionar para o WhatsApp
//                 },
//               ),
//               IconButton(
//                 icon: Icon(Icons.email),
//                 onPressed: () {
//                   // Redirecionar para o E-mail
//                 },
//               ),
//               IconButton(
//                 icon: Icon(Icons.location_on),
//                 onPressed: () {
//                   // Redirecionar para o Endereço
//                 },
//               ),
//             ],
//           ),
//           // Dados do cliente com opção de editar
//           _buildClienteInfo('Nome', _nome),
//           _buildClienteInfo('Celular/WhatsApp', _celular),
//           _buildClienteInfo('Endereço', _endereco),
//           _buildClienteInfo('Complemento', _complemento),
//           _buildClienteInfo('E-mail', _email),
//           _buildClienteInfo('CPF/CNPJ', _cpfCnpj),
//           _buildClienteInfo('Observação', _observacao),
//           SizedBox(height: 20),
//           ElevatedButton(
//             onPressed: _editarCliente,
//             child: Text('Salvar'),
//           ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildClienteInfo(String label, String value) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(vertical: 8.0),
//       child: Row(
//         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//         children: <Widget>[
//           Text(label),
//           Text(value),
//           IconButton(
//             icon: Icon(Icons.edit),
//             onPressed: () {
//               // Lógica para editar o campo
//             },
//           ),
//         ],
//       ),
//     );
//   }
//
//   // Placeholder para as outras abas
//   Widget _buildVendasTab() {
//     return Center(child: Text('Vendas'));
//   }
//
//   Widget _buildPedidosTab() {
//     return Center(child: Text('Pedidos'));
//   }
//
//   Widget _buildContaTab() {
//     return Center(child: Text('Conta'));
//   }
// }



// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
// import '../providers/cliente_provider.dart';
// import '../models/cliente.dart'; // Certifique-se de que o modelo Cliente está importado
//
// class EditarClienteScreen extends StatefulWidget {
//   final Cliente? clienteSelecionado;
//
//   // Adiciona o cliente selecionado no construtor
//   EditarClienteScreen({this.clienteSelecionado});
//
//   @override
//   _EditarClienteScreenState createState() => _EditarClienteScreenState();
// }
//
// class _EditarClienteScreenState extends State<EditarClienteScreen> {
//   late TextEditingController _nomeController;
//   late TextEditingController _celularController;
//   late TextEditingController _enderecoController;
//   late TextEditingController _complementoController;
//   late TextEditingController _emailController;
//   late TextEditingController _cpfController;
//   late TextEditingController _observacaoController;
//   late TextEditingController _saldoController; // Novo campo de saldo
//   late TextEditingController _idController; // Novo campo de ID
//   late TextEditingController _petController; // Novo campo de pet
//
//   @override
//   void initState() {
//     super.initState();
//     // Inicializa os controllers com os dados do cliente selecionado
//     if (widget.clienteSelecionado != null) {
//       _nomeController = TextEditingController(text: widget.clienteSelecionado!.nome);
//       _celularController = TextEditingController(text: widget.clienteSelecionado!.celular);
//       _enderecoController = TextEditingController(text: widget.clienteSelecionado!.endereco);
//       _complementoController = TextEditingController(text: widget.clienteSelecionado!.complemento);
//       _emailController = TextEditingController(text: widget.clienteSelecionado!.email);
//       _cpfController = TextEditingController(text: widget.clienteSelecionado!.cpf);
//       _observacaoController = TextEditingController(text: widget.clienteSelecionado!.observacao);
//       _saldoController = TextEditingController(text: widget.clienteSelecionado!.saldo.toString());
//       _idController = TextEditingController(text: widget.clienteSelecionado!.id);
//       _petController = TextEditingController(text: widget.clienteSelecionado!.pet.join(', ')); // Supondo que `pet` seja uma lista
//     } else {
//       // Caso nenhum cliente tenha sido passado, inicializa os controllers vazios
//       _nomeController = TextEditingController();
//       _celularController = TextEditingController();
//       _enderecoController = TextEditingController();
//       _complementoController = TextEditingController();
//       _emailController = TextEditingController();
//       _cpfController = TextEditingController();
//       _observacaoController = TextEditingController();
//       _saldoController = TextEditingController();
//       _idController = TextEditingController();
//       _petController = TextEditingController();
//     }
//   }
//
//   @override
//   void dispose() {
//     // Limpeza dos controllers quando a tela for descartada
//     _nomeController.dispose();
//     _celularController.dispose();
//     _enderecoController.dispose();
//     _complementoController.dispose();
//     _emailController.dispose();
//     _cpfController.dispose();
//     _observacaoController.dispose();
//     _saldoController.dispose();
//     _idController.dispose();
//     _petController.dispose();
//     super.dispose();
//   }
//
//   // Função para salvar os dados atualizados
//   void _salvarCliente() {
//     final updatedCliente = Cliente(
//       nome: _nomeController.text,
//       celular: _celularController.text,
//       endereco: _enderecoController.text,
//       complemento: _complementoController.text,
//       email: _emailController.text,
//       cpf: _cpfController.text,
//       observacao: _observacaoController.text,
//       saldo: double.tryParse(_saldoController.text) ?? 0.0, // Novo campo de saldo
//       id: _idController.text, // Novo campo de ID
//       pet: _petController.text.split(',').map((e) => e.trim()).toList(), // Convertendo para lista de pets
//     );
//
//     // Atualiza ou adiciona o cliente no provider
//     final clientProvider = Provider.of<ClientProvider>(context, listen: false);
//
//     // Verifica se o cliente selecionado possui um ID. Se tiver, é uma atualização, caso contrário, é uma criação.
//     if (widget.clienteSelecionado != null && widget.clienteSelecionado!.id.isNotEmpty) {
//       clientProvider.atualizarCliente(updatedCliente); // Atualiza o cliente
//     } else {
//       clientProvider.addCliente(updatedCliente); // Adiciona um novo cliente
//     }
//
//     // Volta para a tela anterior
//     Navigator.pop(context);
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text(widget.clienteSelecionado != null ? 'Editar Cliente' : 'Novo Cliente'),
//         actions: [
//           IconButton(
//             icon: Icon(Icons.save),
//             onPressed: _salvarCliente,
//             tooltip: 'Salvar',
//           ),
//         ],
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: Column(
//           children: [
//             // Campos de entrada para editar os dados do cliente
//             _buildTextField('Nome', _nomeController),
//             _buildTextField('Celular/WhatsApp', _celularController),
//             _buildTextField('Endereço', _enderecoController),
//             _buildTextField('Complemento', _complementoController),
//             _buildTextField('E-mail', _emailController),
//             _buildTextField('CPF/CNPJ', _cpfController),
//             _buildTextField('Observação', _observacaoController),
//             _buildTextField('Saldo', _saldoController), // Novo campo de saldo
//             _buildTextField('ID', _idController), // Novo campo de ID
//             _buildTextField('Pets', _petController), // Novo campo de pets
//           ],
//         ),
//       ),
//     );
//   }
//
//   // Widget reutilizável para criar campos de texto editáveis
//   Widget _buildTextField(String label, TextEditingController controller) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(vertical: 8.0),
//       child: TextField(
//         controller: controller,
//         decoration: InputDecoration(
//           labelText: label,
//           border: OutlineInputBorder(),
//         ),
//       ),
//     );
//   }
// }


import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/cliente.dart';
import '../providers/cliente_provider.dart';
import 'editar_cliente_screen.dart';

class ClienteDetalhesScreen extends StatefulWidget {
  final Cliente cliente;

  ClienteDetalhesScreen({required this.cliente});

  @override
  State<ClienteDetalhesScreen> createState() => _ClienteDetalhesScreenState();
}

class _ClienteDetalhesScreenState extends State<ClienteDetalhesScreen> {
  late Cliente cliente;

  @override
  void initState() {
    super.initState();
    cliente = widget.cliente;
  }

  void _atualizarCliente(Cliente clienteAtualizado) {
    setState(() {
      cliente = clienteAtualizado;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(cliente.nome),
          actions: [
            IconButton(
              icon: Icon(Icons.delete),
              onPressed: () => _confirmarDelecao(context),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: 'Dados'),
              Tab(text: 'Vendas'),
              Tab(text: 'Pedidos'),
              Tab(text: 'Conta'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildDadosTab(context),
            Center(child: Text('Vendas')),
            Center(child: Text('Pedidos')),
            Center(child: Text('Conta')),
          ],
        ),
      ),
    );
  }

  Widget _buildDadosTab(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: CircleAvatar(
              radius: 50,
              backgroundColor: Colors.grey[300],
              child: Icon(Icons.camera_alt, size: 40),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: Icon(Icons.message, color: Colors.green),
                onPressed: () => _abrirWhatsApp(cliente.celular),
              ),
              IconButton(
                icon: Icon(Icons.email, color: Colors.blue),
                onPressed: () => _enviarEmail(cliente.email),
              ),
              IconButton(
                icon: Icon(Icons.location_on, color: Colors.red),
                onPressed: () => _abrirMapa(cliente.endereco),
              ),
            ],
          ),
          const Divider(),
          _buildClienteInfo('Nome', cliente.nome),
          _buildClienteInfo('Celular/WhatsApp', cliente.celular),
          _buildClienteInfo('Endereço', cliente.endereco),
          _buildClienteInfo('Complemento', cliente.complemento),
          _buildClienteInfo('E-mail', cliente.email),
          _buildClienteInfo('CPF/CNPJ', cliente.cpf),
          _buildClienteInfo('Observação', cliente.observacao),
          const SizedBox(height: 20),
          Text(
            'Pets:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          cliente.pet.isNotEmpty
              ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: cliente.pet
                .map((pet) => Text(
              '- $pet',
              style: TextStyle(fontSize: 16),
            ))
                .toList(),
          )
              : Text(
            'Nenhum pet registrado.',
            style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 20),
          Center(
            child: ElevatedButton(
              onPressed: () async {
                final Cliente? clienteAtualizado = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EditarClienteScreen(
                      clienteSelecionado: cliente,
                    ),
                  ),
                );

                if (clienteAtualizado != null) {
                  _atualizarCliente(clienteAtualizado);
                }
              },
              child: Text('Editar Dados'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClienteInfo(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value?.isNotEmpty == true ? value! : 'Não informado',
              style: TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmarDelecao(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Confirmar Exclusão'),
        content: Text('Tem certeza de que deseja excluir este cliente?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Provider.of<ClientProvider>(context, listen: false)
                  .removeCliente(cliente);
              Navigator.pop(ctx);
              Navigator.pop(context);
            },
            child: Text('Excluir'),
          ),
        ],
      ),
    );
  }

  void _abrirWhatsApp(String numero) async {
    final Uri uri = Uri.parse('https://wa.me/55$numero');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      throw 'Could not launch $uri';
    }
  }

  void _enviarEmail(String email) async {
    final Uri uri = Uri(scheme: 'mailto', path: email);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      throw 'Could not launch $uri';
    }
  }

  void _abrirMapa(String endereco) async {
    final Uri uri =
    Uri.parse('https://www.google.com/maps/search/?api=1&query=$endereco');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      throw 'Could not launch $uri';
    }
  }
}
