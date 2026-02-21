// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
//
// import '../models/cliente.dart';
// import '../models/pet.dart';
// import '../providers/cliente_provider.dart';
// import 'cadastro_pet_screen.dart';
//
// class AdicionarClienteScreen extends StatefulWidget {
//   final Function(Cliente) onSalvar;
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
//   final _complementoController = TextEditingController();
//   final _observacaoController = TextEditingController();
//   final _saldoController = TextEditingController();
//   final _outroCanalController = TextEditingController();
//
//   List<Pet> _pets = [];
//   DateTime? _aniversario;
//   bool _aceitaMarketing = false;
//
//   final List<String> _canais = ['WhatsApp', 'Instagram', 'Ifood', 'Outro canal'];
//   String? _canalSelecionado;
//
//   void _selecionarAniversario() async {
//     final selecionada = await showDatePicker(
//       context: context,
//       initialDate: DateTime(2000, 1, 1),
//       firstDate: DateTime(1900),
//       lastDate: DateTime.now(),
//     );
//     if (selecionada != null) {
//       setState(() => _aniversario = selecionada);
//     }
//   }
//
//   void _salvarCliente() {
//     final idGerado = DateTime.now().millisecondsSinceEpoch.toString();
//     String canalOrigem;
//
//     if (_canalSelecionado == 'Outro canal') {
//       canalOrigem = _outroCanalController.text.trim();
//
//       // ✅ Salvar como nova opção se for válido e ainda não existir
//       if (canalOrigem.isNotEmpty && !_canais.contains(canalOrigem)) {
//         setState(() {
//           _canais.insert(_canais.length - 1, canalOrigem); // adiciona antes de "Outro canal"
//         });
//       }
//     } else {
//       canalOrigem = _canalSelecionado ?? '';
//     }
//
//     final cliente = Cliente(
//       idCliente: idGerado,
//       nome: _nomeController.text,
//       celular: _celularController.text,
//       email: _emailController.text,
//       endereco: _enderecoController.text,
//       complemento: _complementoController.text,
//       cpf: _cpfController.text,
//       observacao: _observacaoController.text,
//       saldo: double.tryParse(_saldoController.text) ?? 0.0,
//       pets: _pets,
//       dataCadastro: DateTime.now(),
//       aniversario: _aniversario,
//       canalOrigem: canalOrigem,
//       aceitaMarketing: _aceitaMarketing,
//     );
//
//     Provider.of<ClientProvider>(context, listen: false).addCliente(cliente);
//     Navigator.pop(context);
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: Text('Adicionar Cliente')),
//       body: SingleChildScrollView(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             _buildTextField('Nome', _nomeController),
//             _buildTextField('Celular', _celularController),
//             _buildTextField('Endereço', _enderecoController),
//             _buildTextField('Complemento', _complementoController),
//             _buildTextField('Email', _emailController),
//             _buildTextField('CPF', _cpfController),
//             _buildTextField('Observação', _observacaoController),
//             _buildTextField('Saldo', _saldoController),
//
//             SizedBox(height: 16),
//             DropdownButtonFormField<String>(
//               value: _canalSelecionado,
//               items: _canais.map((c) {
//                 return DropdownMenuItem(value: c, child: Text(c));
//               }).toList(),
//               onChanged: (valor) {
//                 setState(() {
//                   _canalSelecionado = valor;
//                   if (valor != 'Outro canal') _outroCanalController.clear();
//                 });
//               },
//               decoration: InputDecoration(labelText: 'Canal de Origem', border: OutlineInputBorder()),
//             ),
//
//             if (_canalSelecionado == 'Outro canal')
//               Padding(
//                 padding: const EdgeInsets.only(top: 8),
//                 child: TextField(
//                   controller: _outroCanalController,
//                   decoration: InputDecoration(labelText: 'Digite o canal', border: OutlineInputBorder()),
//                 ),
//               ),
//
//             SizedBox(height: 16),
//             ListTile(
//               title: Text(_aniversario != null
//                   ? 'Aniversário: ${_aniversario!.day}/${_aniversario!.month}/${_aniversario!.year}'
//                   : 'Selecionar aniversário'),
//               trailing: Icon(Icons.calendar_today),
//               onTap: _selecionarAniversario,
//             ),
//
//             SwitchListTile(
//               title: Text('Aceita receber promoções?'),
//               value: _aceitaMarketing,
//               onChanged: (v) => setState(() => _aceitaMarketing = v),
//             ),
//
//             SizedBox(height: 20),
//             ElevatedButton.icon(
//               icon: Icon(Icons.pets),
//               label: Text('Cadastrar Pet'),
//               onPressed: () async {
//                 final pet = await Navigator.push<Pet>(
//                   context,
//                   MaterialPageRoute(builder: (_) => CadastroPetScreen()),
//                 );
//                 if (pet != null) {
//                   setState(() => _pets.add(pet));
//                 }
//               },
//             ),
//
//             SizedBox(height: 20),
//             Text('Pets cadastrados:', style: TextStyle(fontWeight: FontWeight.bold)),
//             ..._pets.map((pet) => ListTile(
//               leading: pet.imagemUrl.isNotEmpty
//                   ? Image.network(pet.imagemUrl, width: 40, height: 40, fit: BoxFit.cover)
//                   : Icon(Icons.pets),
//               title: Text(pet.nome),
//               subtitle: Text('${pet.especie} - ${pet.raca}'),
//             )),
//             SizedBox(height: 24),
//
//             SizedBox(
//               width: double.infinity,
//               child: ElevatedButton(
//                 onPressed: _salvarCliente,
//                 style: ElevatedButton.styleFrom(
//                   padding: EdgeInsets.symmetric(vertical: 16),
//                   textStyle: TextStyle(fontSize: 18),
//                 ),
//                 child: Text('Salvar'),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget _buildTextField(String label, TextEditingController controller) {
//     return Padding(
//       padding: const EdgeInsets.symmetric(vertical: 8),
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
import '../models/pet.dart';
import '../providers/cliente_provider.dart';
import 'cadastro_pet_screen.dart';

class AdicionarClienteScreen extends StatefulWidget {
  final Function(Cliente) onSalvar;

  AdicionarClienteScreen({required this.onSalvar});

  @override
  _AdicionarClienteScreenState createState() => _AdicionarClienteScreenState();
}

class _AdicionarClienteScreenState extends State<AdicionarClienteScreen> {
  final _nomeController = TextEditingController();
  final _celularController = TextEditingController();
  final _enderecoController = TextEditingController();
  final _complementoController = TextEditingController();
  final _emailController = TextEditingController();
  final _cpfController = TextEditingController();
  final _observacaoController = TextEditingController();
  final _saldoController = TextEditingController();
  final _outroCanalController = TextEditingController();

  final _rangeController = TextEditingController(); // Range de distância
  final _estimativaController = TextEditingController(); // Estimativa de entrega

  List<Pet> _pets = [];
  DateTime? _aniversario;
  bool _aceitaMarketing = false;

  final List<String> _canais = ['WhatsApp', 'Instagram', 'Ifood', 'Outro canal'];
  String? _canalSelecionado;

  void _selecionarAniversario() async {
    final selecionada = await showDatePicker(
      context: context,
      initialDate: DateTime(2000, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (selecionada != null) {
      setState(() => _aniversario = selecionada);
    }
  }

  void _abrirGoogleMaps(String endereco) async {
    if (endereco.isEmpty) return;
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(endereco)}');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir o Google Maps')),
      );
    }
  }

  void _salvarCliente() {
    final idGerado = DateTime.now().millisecondsSinceEpoch.toString();
    String canalOrigem;

    if (_canalSelecionado == 'Outro canal') {
      canalOrigem = _outroCanalController.text.trim();
      if (canalOrigem.isNotEmpty && !_canais.contains(canalOrigem)) {
        setState(() {
          _canais.insert(_canais.length - 1, canalOrigem);
        });
      }
    } else {
      canalOrigem = _canalSelecionado ?? '';
    }

    final cliente = Cliente(
      idCliente: idGerado,
      nome: _nomeController.text,
      celular: _celularController.text,
      email: _emailController.text,
      endereco: _enderecoController.text,
      complemento: _complementoController.text,
      cpf: _cpfController.text,
      observacao: _observacaoController.text,
      saldo: double.tryParse(_saldoController.text) ?? 0.0,
      pets: _pets,
      dataCadastro: DateTime.now(),
      aniversario: _aniversario,
      canalOrigem: canalOrigem,
      aceitaMarketing: _aceitaMarketing,
      rangeDistancia: double.tryParse(_rangeController.text) ?? 0.0,
      estimativaEntrega: int.tryParse(_estimativaController.text) ?? 0,
    );

    Provider.of<ClientProvider>(context, listen: false).addCliente(cliente);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Adicionar Cliente')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTextField('Nome', _nomeController),
            _buildTextField('Celular', _celularController),

            // Campo de endereço com botão de mapa
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _enderecoController,
                      decoration: InputDecoration(
                        labelText: 'Endereço',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.map),
                    onPressed: () => _abrirGoogleMaps(_enderecoController.text),
                  ),
                ],
              ),
            ),
            _buildTextField('Range de distância (km)', _rangeController),
            _buildTextField('Estimativa de entrega (min)', _estimativaController),
            _buildTextField('Complemento', _complementoController),
            _buildTextField('Email', _emailController),
            _buildTextField('CPF', _cpfController),
            _buildTextField('Observação', _observacaoController),
            _buildTextField('Saldo', _saldoController),

            // Novos campos


            SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _canalSelecionado,
              items: _canais.map((c) {
                return DropdownMenuItem(value: c, child: Text(c));
              }).toList(),
              onChanged: (valor) {
                setState(() {
                  _canalSelecionado = valor;
                  if (valor != 'Outro canal') _outroCanalController.clear();
                });
              },
              decoration: InputDecoration(labelText: 'Canal de Origem', border: OutlineInputBorder()),
            ),

            if (_canalSelecionado == 'Outro canal')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextField(
                  controller: _outroCanalController,
                  decoration: InputDecoration(labelText: 'Digite o canal', border: OutlineInputBorder()),
                ),
              ),

            SizedBox(height: 16),
            ListTile(
              title: Text(_aniversario != null
                  ? 'Aniversário: ${_aniversario!.day}/${_aniversario!.month}/${_aniversario!.year}'
                  : 'Selecionar aniversário'),
              trailing: Icon(Icons.calendar_today),
              onTap: _selecionarAniversario,
            ),

            SwitchListTile(
              title: Text('Aceita receber promoções?'),
              value: _aceitaMarketing,
              onChanged: (v) => setState(() => _aceitaMarketing = v),
            ),

            SizedBox(height: 20),
            ElevatedButton.icon(
              icon: Icon(Icons.pets),
              label: Text('Cadastrar Pet'),
              onPressed: () async {
                final pet = await Navigator.push<Pet>(
                  context,
                  MaterialPageRoute(builder: (_) => CadastroPetScreen()),
                );
                if (pet != null) {
                  setState(() => _pets.add(pet));
                }
              },
            ),

            SizedBox(height: 20),
            Text('Pets cadastrados:', style: TextStyle(fontWeight: FontWeight.bold)),
            ..._pets.map((pet) => ListTile(
              leading: pet.imagemUrl.isNotEmpty
                  ? Image.network(pet.imagemUrl, width: 40, height: 40, fit: BoxFit.cover)
                  : Icon(Icons.pets),
              title: Text(pet.nome),
              subtitle: Text('${pet.especie} - ${pet.raca}'),
            )),
            SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _salvarCliente,
                style: ElevatedButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  textStyle: TextStyle(fontSize: 18),
                ),
                child: Text('Salvar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(),
        ),
      ),
    );
  }
}
