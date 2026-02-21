import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/cliente.dart';
import '../models/pet.dart';
import '../providers/cliente_provider.dart';
import 'cadastro_pet_screen.dart';
import 'editar_pet_screen.dart';

class EditarClienteScreen extends StatefulWidget {
  final Cliente clienteSelecionado;

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
  final TextEditingController _outroCanalController = TextEditingController();
  late TextEditingController _distanciaController;
  late TextEditingController _estimativaController;

  List<Pet> _pets = [];
  DateTime? _aniversario;
  bool _aceitaMarketing = false;
  final List<String> _canais = ['WhatsApp', 'Instagram', 'Ifood', 'Outro canal'];
  String? _canalSelecionado;

  @override
  void initState() {
    super.initState();
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
    // _canalOrigemController = TextEditingController(text: cliente.canalOrigem ?? '');
    _aniversario = cliente.aniversario;
    _aceitaMarketing = cliente.aceitaMarketing ?? false;
    _pets = cliente.pets.toList();
    _distanciaController = TextEditingController(
        text: cliente.rangeDistancia != null ? cliente.rangeDistancia!.toString() : '');
    _estimativaController = TextEditingController(
        text: cliente.estimativaEntrega != null ? cliente.estimativaEntrega!.toString() : '');
    if (_canais.contains(cliente.canalOrigem)) {
      _canalSelecionado = cliente.canalOrigem;
    } else if (cliente.canalOrigem!.isNotEmpty) {
      _canalSelecionado = 'Outro canal';
      _outroCanalController.text = cliente.canalOrigem!;
    }
    }

  void _selecionarAniversario() async {
    final data = await showDatePicker(
      context: context,
      initialDate: _aniversario ?? DateTime(2000, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );
    if (data != null) setState(() => _aniversario = data);
  }

  void _salvarCliente() {
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
    final clienteAtualizado = Cliente(
      idCliente: _idController.text,
      nome: _nomeController.text,
      celular: _celularController.text,
      email: _emailController.text,
      endereco: _enderecoController.text,
      complemento: _complementoController.text,
      cpf: _cpfController.text,
      observacao: _observacaoController.text,
      saldo: double.tryParse(_saldoController.text) ?? 0.0,
      pets: _pets,
      canalOrigem: canalOrigem,
      aniversario: _aniversario,
      aceitaMarketing: _aceitaMarketing,
      dataCadastro: widget.clienteSelecionado.dataCadastro,
      quantidadeCompras: widget.clienteSelecionado.quantidadeCompras,
      rangeDistancia: double.tryParse(_distanciaController.text),
      estimativaEntrega: int.tryParse(_estimativaController.text),
    );

    Provider.of<ClientProvider>(context, listen: false).atualizarCliente(clienteAtualizado);
    Navigator.pop(context, clienteAtualizado);
  }
  @override
  void dispose() {
    _outroCanalController.dispose();
    _distanciaController.dispose();
    _estimativaController.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Editar Cliente'),
        actions: [
          IconButton(icon: Icon(Icons.save), onPressed: _salvarCliente),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            _buildTextField('Nome', _nomeController),
            _buildTextField('Celular', _celularController),
            _buildTextField('Endereço', _enderecoController),
            _buildTextField('Distância (km)', _distanciaController),
            _buildTextField('Estimativa de entrega (min)', _estimativaController),
            _buildTextField('Complemento', _complementoController),
            _buildTextField('Email', _emailController),
            _buildTextField('CPF', _cpfController),
            _buildTextField('Observação', _observacaoController),
            _buildTextField('Saldo', _saldoController),
            SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _canalSelecionado,
              items: _canais.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
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
              label: Text('Adicionar Pet'),
              onPressed: () async {
                final pet = await Navigator.push<Pet>(
                  context,
                  MaterialPageRoute(builder: (_) => CadastroPetScreen()),
                );
                if (pet != null) {
                  setState(() => _pets.add(pet));
                  _salvarCliente();
                }
              },
            ),
            SizedBox(height: 16),
            Text('Pets cadastrados:', style: TextStyle(fontWeight: FontWeight.bold)),
            ..._pets.asMap().entries.map((entry) {
              final i = entry.key;
              final pet = entry.value;
              return ListTile(
                leading: pet.imagemUrl.isNotEmpty
                    ? Image.network(pet.imagemUrl, width: 40, height: 40, fit: BoxFit.cover)
                    : Icon(Icons.pets),
                title: Text(pet.nome),
                subtitle: Text('${pet.especie} - ${pet.raca}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.edit),
                      onPressed: () async {
                        final petEditado = await Navigator.push<Pet>(
                          context,
                          MaterialPageRoute(builder: (_) => EditarPetScreen(pet: pet)),
                        );
                        if (petEditado != null) {
                          setState(() => _pets[i] = petEditado);
                          _salvarCliente();
                        }
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.delete, color: Colors.red),
                      onPressed: () {
                        setState(() => _pets.removeAt(i));
                        _salvarCliente();
                      },
                    ),
                  ],
                ),
              );
            }),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: _salvarCliente,
              child: Text('Salvar Cliente'),
            ),
          ],
        ),
      ),
    );
  }

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
}
