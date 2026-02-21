import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/pet.dart';

class CadastroPetScreen extends StatefulWidget {
  @override
  _CadastroPetScreenState createState() => _CadastroPetScreenState();
}

class _CadastroPetScreenState extends State<CadastroPetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nome = TextEditingController();
  final _raca = TextEditingController();
  final _peso = TextEditingController();
  final _observacoes = TextEditingController();

  DateTime? _nascimento;
  bool _vacinado = false;
  bool _castrado = false;
  String _imagemUrl = '';

  final List<String> _especiesDisponiveis = ['Cão', 'Gato', 'Passarinho', 'Peixe', 'Coelho'];
  String? _especieSelecionada;

  void _salvarPet() {
    if (!_formKey.currentState!.validate() || _nascimento == null || _especieSelecionada == null) return;

    final pet = Pet(
      id: Uuid().v4(),
      nome: _nome.text.trim(),
      especie: _especieSelecionada!,
      raca: _raca.text.trim(),
      nascimento: _nascimento!,
      peso: double.tryParse(_peso.text) ?? 0,
      vacinado: _vacinado,
      castrado: _castrado,
      observacoes: _observacoes.text.trim(),
      imagemUrl: _imagemUrl,
    );

    Navigator.pop(context, pet);
  }

  Future<void> _selecionarNascimento() async {
    final data = await showDatePicker(
      context: context,
      initialDate: DateTime.now().subtract(Duration(days: 365)),
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (data != null) setState(() => _nascimento = data);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Cadastro de Pet')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              TextFormField(controller: _nome, decoration: InputDecoration(labelText: 'Nome'), validator: (v) => v!.isEmpty ? 'Obrigatório' : null),

              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: 'Espécie'),
                value: _especieSelecionada,
                items: _especiesDisponiveis
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (value) => setState(() => _especieSelecionada = value),
                validator: (v) => v == null ? 'Selecione uma espécie' : null,
              ),

              TextFormField(controller: _raca, decoration: InputDecoration(labelText: 'Raça')),
              TextFormField(controller: _peso, decoration: InputDecoration(labelText: 'Peso (kg)'), keyboardType: TextInputType.number),

              ListTile(
                title: Text(_nascimento == null
                    ? 'Selecionar Nascimento'
                    : 'Nascimento: ${_nascimento!.day}/${_nascimento!.month}/${_nascimento!.year}'),
                trailing: Icon(Icons.calendar_today),
                onTap: _selecionarNascimento,
              ),

              SwitchListTile(
                title: Text('Vacinado'),
                value: _vacinado,
                onChanged: (v) => setState(() => _vacinado = v),
              ),

              SwitchListTile(
                title: Text('Castrado'),
                value: _castrado,
                onChanged: (v) => setState(() => _castrado = v),
              ),

              TextFormField(
                controller: _observacoes,
                decoration: InputDecoration(labelText: 'Observações'),
                maxLines: 3,
              ),

              SizedBox(height: 24),
              ElevatedButton.icon(
                icon: Icon(Icons.save),
                label: Text('Salvar Pet'),
                onPressed: _salvarPet,

              ),

            ],
          ),
        ),
      ),
    );
  }
}
