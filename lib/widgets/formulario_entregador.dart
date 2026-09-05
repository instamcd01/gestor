import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/entregador.dart';
import '../providers/entregador_provider.dart';
import '../utils/cliente_validators.dart';

const _rotulosModoCustoEntregador = {
  ModoCustoEntregador.fixo: 'Valor fixo por entrega',
  ModoCustoEntregador.km: 'Valor por km rodado',
  ModoCustoEntregador.salarioMensal: 'Salário mensal',
  ModoCustoEntregador.salarioDiaria: 'Salário diária',
  ModoCustoEntregador.rota: 'Por rota (múltiplas entregas)',
};

/// Formulário de cadastro/edição de entregador — bottom sheet aberto a
/// partir da tela de Usuários (gestão de pessoas centralizada ali: equipe +
/// entregadores + convites dos dois).
class FormularioEntregador extends StatefulWidget {
  final Entregador? existente;

  const FormularioEntregador({super.key, this.existente});

  @override
  State<FormularioEntregador> createState() => _FormularioEntregadorState();
}

class _FormularioEntregadorState extends State<FormularioEntregador> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nomeController;
  late final TextEditingController _telefoneController;
  late final TextEditingController _veiculoController;
  late final TextEditingController _placaController;
  late final TextEditingController _custoPorEntregaController;
  late final TextEditingController _custoPorKmController;
  late final TextEditingController _custoPorParadaController;
  late final TextEditingController _custoSalarioMensalController;
  late final TextEditingController _custoSalarioDiariaController;
  late bool _ativo;
  late bool _veiculoDaLoja;
  String? _custoModo;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existente;
    _nomeController = TextEditingController(text: e?.nome ?? '');
    _telefoneController = TextEditingController(text: e?.telefone ?? '');
    _veiculoController = TextEditingController(text: e?.tipoVeiculo ?? '');
    _placaController = TextEditingController(text: e?.placaVeiculo ?? '');
    _custoPorEntregaController = TextEditingController(text: ClienteValidators.formatarMoeda(e?.custoPorEntrega));
    _custoPorKmController = TextEditingController(text: ClienteValidators.formatarMoeda(e?.custoPorKm));
    _custoPorParadaController = TextEditingController(text: ClienteValidators.formatarMoeda(e?.custoPorParadaRota));
    _custoSalarioMensalController = TextEditingController(text: ClienteValidators.formatarMoeda(e?.custoSalarioMensal));
    _custoSalarioDiariaController = TextEditingController(text: ClienteValidators.formatarMoeda(e?.custoSalarioDiaria));
    _ativo = e?.ativo ?? true;
    _veiculoDaLoja = e?.veiculoDaLoja ?? false;
    _custoModo = e?.custoModo;
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _telefoneController.dispose();
    _veiculoController.dispose();
    _placaController.dispose();
    _custoPorEntregaController.dispose();
    _custoPorKmController.dispose();
    _custoPorParadaController.dispose();
    _custoSalarioMensalController.dispose();
    _custoSalarioDiariaController.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _salvando = true);
    final entregador = Entregador(
      id: widget.existente?.id,
      nome: _nomeController.text.trim(),
      telefone: _telefoneController.text.trim().isEmpty ? null : _telefoneController.text.trim(),
      tipoVeiculo: _veiculoController.text.trim().isEmpty ? null : _veiculoController.text.trim(),
      placaVeiculo: _placaController.text.trim().isEmpty ? null : _placaController.text.trim(),
      ativo: _ativo,
      veiculoDaLoja: _veiculoDaLoja,
      custoModo: _custoModo,
      custoPorEntrega: ClienteValidators.parseNumero(_custoPorEntregaController.text),
      custoPorKm: ClienteValidators.parseNumero(_custoPorKmController.text),
      custoPorParadaRota: ClienteValidators.parseNumero(_custoPorParadaController.text),
      custoSalarioMensal: ClienteValidators.parseNumero(_custoSalarioMensalController.text),
      custoSalarioDiaria: ClienteValidators.parseNumero(_custoSalarioDiariaController.text),
    );

    try {
      final provider = context.read<EntregadorProvider>();
      if (widget.existente != null) {
        await provider.atualizar(entregador);
      } else {
        await provider.criar(entregador);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Widget _chipModo(String modo) {
    return ChoiceChip(
      label: Text(_rotulosModoCustoEntregador[modo]!),
      selected: _custoModo == modo,
      onSelected: (_) => setState(() => _custoModo = modo),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.existente != null ? 'Editar Entregador' : 'Novo Entregador',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _nomeController,
                decoration: const InputDecoration(labelText: 'Nome'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _telefoneController,
                decoration: const InputDecoration(labelText: 'Telefone (opcional)'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _veiculoController,
                      decoration: const InputDecoration(labelText: 'Veículo (opcional)', hintText: 'Moto, carro...'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      controller: _placaController,
                      decoration: const InputDecoration(labelText: 'Placa (opcional)'),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Veículo é da loja'),
                subtitle: const Text('Informativo por enquanto — não muda o cálculo'),
                value: _veiculoDaLoja,
                onChanged: (v) => setState(() => _veiculoDaLoja = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Ativo'),
                value: _ativo,
                onChanged: (v) => setState(() => _ativo = v),
              ),
              const SizedBox(height: 8),
              const Text('Como calcular o custo da entrega', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chipModo(ModoCustoEntregador.fixo),
                  _chipModo(ModoCustoEntregador.km),
                  _chipModo(ModoCustoEntregador.rota),
                  _chipModo(ModoCustoEntregador.salarioMensal),
                  _chipModo(ModoCustoEntregador.salarioDiaria),
                ],
              ),
              if (_custoModo == ModoCustoEntregador.fixo) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _custoPorEntregaController,
                  decoration: const InputDecoration(labelText: 'Valor por entrega (R\$)', prefixText: 'R\$ '),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
              if (_custoModo == ModoCustoEntregador.km) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _custoPorKmController,
                  decoration: const InputDecoration(labelText: 'Valor por km (R\$)', prefixText: 'R\$ '),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
              if (_custoModo == ModoCustoEntregador.rota) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _custoPorKmController,
                  decoration: const InputDecoration(labelText: 'Valor por km total da rota (R\$)', prefixText: 'R\$ '),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _custoPorParadaController,
                  decoration: const InputDecoration(
                    labelText: 'Valor fixo adicional por parada (R\$)',
                    prefixText: 'R\$ ',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
              if (_custoModo == ModoCustoEntregador.salarioMensal) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _custoSalarioMensalController,
                  decoration: const InputDecoration(
                    labelText: 'Salário mensal (R\$)',
                    prefixText: 'R\$ ',
                    helperText: 'Rateado pelas entregas do dia quando cada rota é finalizada — é uma estimativa',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
              if (_custoModo == ModoCustoEntregador.salarioDiaria) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _custoSalarioDiariaController,
                  decoration: const InputDecoration(
                    labelText: 'Diária (R\$)',
                    prefixText: 'R\$ ',
                    helperText: 'Rateada pelas entregas do dia quando cada rota é finalizada — é uma estimativa',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _salvando ? null : _salvar,
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                child: _salvando
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Salvar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
