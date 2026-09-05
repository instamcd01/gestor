import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/entregador.dart';
import '../providers/entregador_provider.dart';
import '../utils/cliente_validators.dart';
import '../widgets/estado_erro_lista.dart';

const _rotulosModo = {
  ModoCustoEntregador.fixo: 'Valor fixo por entrega',
  ModoCustoEntregador.km: 'Valor por km rodado',
  ModoCustoEntregador.salarioMensal: 'Salário mensal',
  ModoCustoEntregador.salarioDiaria: 'Salário diária',
  ModoCustoEntregador.rota: 'Por rota (múltiplas entregas)',
};

/// Cadastro de entregadores (Configurações > Vendas, dono/gerente) — cada
/// um com seu próprio jeito de custar a entrega (Fase 2 do custo real por
/// venda, ver [[gestor_custo_real_venda]]). Usado por "Rotas de Entrega"
/// (`rotas_entrega_screen.dart`) pra montar as rotas do dia.
class EntregadoresScreen extends StatefulWidget {
  const EntregadoresScreen({super.key});

  @override
  State<EntregadoresScreen> createState() => _EntregadoresScreenState();
}

class _EntregadoresScreenState extends State<EntregadoresScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EntregadorProvider>().carregar();
    });
  }

  Future<void> _abrirFormulario({Entregador? existente}) async {
    final salvo = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FormularioEntregador(existente: existente),
    );
    if (salvo == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(existente != null ? 'Entregador atualizado!' : 'Entregador cadastrado!')),
      );
    }
  }

  Future<void> _excluir(Entregador entregador) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover entregador'),
        content: Text('Remover "${entregador.nome}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remover')),
        ],
      ),
    );
    if (confirmar != true || entregador.id == null || !mounted) return;

    try {
      await context.read<EntregadorProvider>().excluir(entregador.id!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao remover: $e')));
      }
    }
  }

  String _resumoCusto(Entregador e) {
    switch (e.custoModo) {
      case ModoCustoEntregador.fixo:
        return 'R\$ ${e.custoPorEntrega?.toStringAsFixed(2) ?? '-'} por entrega';
      case ModoCustoEntregador.km:
        return 'R\$ ${e.custoPorKm?.toStringAsFixed(2) ?? '-'} por km';
      case ModoCustoEntregador.rota:
        return 'R\$ ${e.custoPorKm?.toStringAsFixed(2) ?? '-'}/km + '
            'R\$ ${e.custoPorParadaRota?.toStringAsFixed(2) ?? '-'} por parada';
      case ModoCustoEntregador.salarioMensal:
        return 'Salário R\$ ${e.custoSalarioMensal?.toStringAsFixed(2) ?? '-'}/mês (rateado por entrega)';
      case ModoCustoEntregador.salarioDiaria:
        return 'Diária R\$ ${e.custoSalarioDiaria?.toStringAsFixed(2) ?? '-'} (rateada por entrega)';
      default:
        return 'Custo de entrega não configurado';
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EntregadorProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Entregadores')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.add),
        label: const Text('Novo'),
      ),
      body: provider.carregando
          ? const Center(child: CircularProgressIndicator())
          : provider.erro != null
              ? EstadoErroLista(mensagem: provider.erro!, onTentarNovamente: provider.carregar)
              : provider.entregadores.isEmpty
                  ? const Center(child: Text('Nenhum entregador cadastrado ainda.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: provider.entregadores.length,
                      itemBuilder: (context, index) {
                        final entregador = provider.entregadores[index];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(entregador.nome, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_resumoCusto(entregador)),
                                Text(
                                  entregador.veiculoDaLoja ? 'Veículo da loja' : 'Veículo do próprio entregador',
                                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                ),
                                if (!entregador.ativo)
                                  const Text('Inativo', style: TextStyle(color: Colors.red, fontSize: 12)),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _abrirFormulario(existente: entregador),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _excluir(entregador),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
    );
  }
}

class _FormularioEntregador extends StatefulWidget {
  final Entregador? existente;

  const _FormularioEntregador({this.existente});

  @override
  State<_FormularioEntregador> createState() => _FormularioEntregadorState();
}

class _FormularioEntregadorState extends State<_FormularioEntregador> {
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
      label: Text(_rotulosModo[modo]!),
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
