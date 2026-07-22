import 'package:flutter/material.dart';
import '../models/pet.dart';
import '../utils/cliente_validators.dart';
import '../utils/formatadores_input.dart';
import '../widgets/form_section.dart';

class EditarPetScreen extends StatefulWidget {
  final Pet pet;

  EditarPetScreen({required this.pet});

  @override
  _EditarPetScreenState createState() => _EditarPetScreenState();
}

class _EditarPetScreenState extends State<EditarPetScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nome;
  late TextEditingController _raca;
  late TextEditingController _peso;
  late TextEditingController _alergias;
  late TextEditingController _observacoes;
  late TextEditingController _nascimento;

  bool _vacinado = false;
  bool _castrado = false;
  String _imagemUrl = '';
  String? _especieSelecionada;
  String? _porteSelecionado;

  final List<String> _especiesDisponiveis = ['Cão', 'Gato', 'Passarinho', 'Peixe', 'Coelho'];
  final List<String> _portesDisponiveis = ['Pequeno', 'Médio', 'Grande'];

  @override
  void initState() {
    super.initState();
    final pet = widget.pet;

    _nome = TextEditingController(text: pet.nome);
    _raca = TextEditingController(text: pet.raca);
    _peso = TextEditingController(text: ClienteValidators.formatarMoeda(pet.peso));
    _alergias = TextEditingController(text: pet.alergias);
    _observacoes = TextEditingController(text: pet.observacoes);
    _nascimento = TextEditingController(text: ClienteValidators.formatarData(pet.nascimento));

    _vacinado = pet.vacinado;
    _castrado = pet.castrado;
    _imagemUrl = pet.imagemUrl;
    _especieSelecionada = pet.especie;
    _porteSelecionado = pet.porte.isNotEmpty ? pet.porte : null;
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

  void _salvar() {
    final nascimento = ClienteValidators.parseData(_nascimento.text);
    if (!_formKey.currentState!.validate() || nascimento == null || _especieSelecionada == null) return;

    final petAtualizado = Pet(
      id: widget.pet.id,
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

    Navigator.pop(context, petAtualizado);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Editar Pet')),
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
                  value: _especieSelecionada,
                  items: _especiesDisponiveis.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (value) => setState(() => _especieSelecionada = value),
                  decoration: const InputDecoration(labelText: 'Espécie'),
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
              onPressed: _salvar,
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
            ),
          ],
        ),
      ),
    );
  }
}
