import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/pet.dart';
import '../utils/cliente_validators.dart';
import '../utils/formatadores_input.dart';
import '../widgets/form_section.dart';

class CadastroPetScreen extends StatefulWidget {
  @override
  _CadastroPetScreenState createState() => _CadastroPetScreenState();
}

class _CadastroPetScreenState extends State<CadastroPetScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nome = TextEditingController();
  final _raca = TextEditingController();
  final _peso = TextEditingController();
  final _alergias = TextEditingController();
  final _observacoes = TextEditingController();
  final _nascimento = TextEditingController();

  bool _vacinado = false;
  bool _castrado = false;
  String _imagemUrl = '';

  final List<String> _especiesDisponiveis = ['Cão', 'Gato', 'Passarinho', 'Peixe', 'Coelho'];
  String? _especieSelecionada;

  final List<String> _portesDisponiveis = ['Pequeno', 'Médio', 'Grande'];
  String? _porteSelecionado;

  void _salvarPet() {
    final nascimento = ClienteValidators.parseData(_nascimento.text);
    if (!_formKey.currentState!.validate() || nascimento == null || _especieSelecionada == null) return;

    final pet = Pet(
      id: Uuid().v4(),
      nome: _nome.text.trim(),
      especie: _especieSelecionada!,
      raca: _raca.text.trim(),
      porte: _porteSelecionado ?? '',
      nascimento: nascimento,
      peso: ClienteValidators.parseNumero(_peso.text) ?? 0,
      vacinado: _vacinado,
      castrado: _castrado,
      alergias: _alergias.text.trim(),
      observacoes: _observacoes.text.trim(),
      imagemUrl: _imagemUrl,
    );

    Navigator.pop(context, pet);
  }

  @override
  void dispose() {
    _nome.dispose();
    _raca.dispose();
    _peso.dispose();
    _alergias.dispose();
    _observacoes.dispose();
    _nascimento.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Cadastro de Pet')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FormSection(
              titulo: 'Dados do pet',
              children: [
                TextFormField(
                  controller: _nome,
                  decoration: const InputDecoration(labelText: 'Nome'),
                  validator: (v) => v!.isEmpty ? 'Obrigatório' : null,
                ),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Espécie'),
                  value: _especieSelecionada,
                  items: _especiesDisponiveis.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (value) => setState(() => _especieSelecionada = value),
                  validator: (v) => v == null ? 'Selecione uma espécie' : null,
                ),
                TextFormField(controller: _raca, decoration: const InputDecoration(labelText: 'Raça')),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Porte (Opcional)'),
                  value: _porteSelecionado,
                  items: _portesDisponiveis.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                  onChanged: (value) => setState(() => _porteSelecionado = value),
                ),
                TextFormField(
                  controller: _peso,
                  decoration: const InputDecoration(labelText: 'Peso (kg)'),
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [DecimalInputFormatter()],
                  validator: ClienteValidators.pesoPet,
                ),
                TextFormField(
                  controller: _nascimento,
                  decoration: const InputDecoration(labelText: 'Nascimento (DD/MM/AAAA)'),
                  keyboardType: TextInputType.datetime,
                  inputFormatters: [DataInputFormatter()],
                  validator: (v) => ClienteValidators.data(v, obrigatoria: true),
                ),
              ],
            ),
            const SizedBox(height: 16),

            FormSection(
              titulo: 'Saúde',
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Vacinado'),
                  value: _vacinado,
                  onChanged: (v) => setState(() => _vacinado = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Castrado'),
                  value: _castrado,
                  onChanged: (v) => setState(() => _castrado = v),
                ),
                TextFormField(
                  controller: _alergias,
                  decoration: const InputDecoration(labelText: 'Alergias (Opcional)'),
                  maxLines: 2,
                ),
                TextFormField(
                  controller: _observacoes,
                  decoration: const InputDecoration(labelText: 'Observações'),
                  maxLines: 3,
                ),
              ],
            ),
            const SizedBox(height: 24),

            ElevatedButton.icon(
              icon: Icon(Icons.save),
              label: Text('Salvar Pet'),
              onPressed: _salvarPet,
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
            ),
          ],
        ),
      ),
    );
  }
}
