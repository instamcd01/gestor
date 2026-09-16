import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/despesa_veiculo.dart';
import '../models/veiculo.dart';
import '../providers/auth_provider.dart';
import '../repositories/despesa_veiculo_repository.dart';
import '../utils/formatadores_input.dart';
import '../utils/produto_validators.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _data = DateFormat('dd/MM/yyyy');

/// Histórico real de gastos de UM veículo (combustível/manutenção/pneu/
/// seguro/outro) + km do odômetro quando souber — quanto mais completo,
/// mais preciso fica o custo/km calculado (`calcular_custo_por_km_veiculo`),
/// que substitui a estimativa estática de Custos Operacionais assim que
/// houver dado real suficiente (pelo menos 2 leituras de km no período).
class DespesasVeiculoScreen extends StatefulWidget {
  final Veiculo veiculo;
  const DespesasVeiculoScreen({super.key, required this.veiculo});

  @override
  State<DespesasVeiculoScreen> createState() => _DespesasVeiculoScreenState();
}

class _DespesasVeiculoScreenState extends State<DespesasVeiculoScreen> {
  final _repo = DespesaVeiculoRepository();
  List<DespesaVeiculo> _despesas = [];
  double? _custoPorKm30dias;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final agora = DateTime.now();
      final results = await Future.wait([
        _repo.listarPorVeiculo(widget.veiculo.id!),
        _repo.calcularCustoPorKm(widget.veiculo.id!, desde: agora.subtract(const Duration(days: 30)), ate: agora),
      ]);
      if (!mounted) return;
      setState(() {
        _despesas = results[0] as List<DespesaVeiculo>;
        _custoPorKm30dias = results[1] as double?;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao carregar histórico: $e')));
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _lancarDespesa() async {
    final valorController = TextEditingController();
    final kmController = TextEditingController();
    final observacaoController = TextEditingController();
    var tipo = 'combustivel';
    var data = DateTime.now();

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Lançar despesa'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: tipo,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: [for (final t in tiposDespesaVeiculo) DropdownMenuItem(value: t, child: Text(rotuloTipoDespesaVeiculo(t)))],
                  onChanged: (v) => setDialogState(() => tipo = v ?? 'combustivel'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: valorController,
                  decoration: const InputDecoration(labelText: 'Valor (R\$)', prefixText: 'R\$ '),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [MoedaInputFormatter()],
                  autofocus: true,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: kmController,
                  decoration: const InputDecoration(
                    labelText: 'Km do odômetro (Opcional)',
                    helperText: 'Preenchendo sempre que souber, o custo/km fica mais preciso',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [DecimalInputFormatter()],
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Data'),
                  subtitle: Text(_data.format(data)),
                  trailing: const Icon(Icons.calendar_today_outlined, size: 18),
                  onTap: () async {
                    final escolhida = await showDatePicker(
                      context: ctx,
                      initialDate: data,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                    );
                    if (escolhida != null) setDialogState(() => data = escolhida);
                  },
                ),
                TextField(
                  controller: observacaoController,
                  decoration: const InputDecoration(labelText: 'Observação (Opcional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );

    if (confirmou != true || !mounted) return;
    final valor = ProdutoValidators.parseNumero(valorController.text);
    if (valor == null || valor <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Valor inválido.')));
      return;
    }
    final km = ProdutoValidators.parseNumero(kmController.text);

    try {
      final empresaId = context.read<AuthProvider>().empresaId;
      if (empresaId == null) return;
      await _repo.criar(
        DespesaVeiculo(
          veiculoId: widget.veiculo.id!,
          data: data,
          tipo: tipo,
          valor: valor,
          kmAtual: km,
          observacao: observacaoController.text.trim().isEmpty ? null : observacaoController.text.trim(),
        ),
        empresaId: empresaId,
      );
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao lançar: $e')));
    }
  }

  Future<void> _remover(DespesaVeiculo despesa) async {
    try {
      await _repo.remover(despesa.id!);
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao remover: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.veiculo.nome)),
      floatingActionButton: FloatingActionButton(onPressed: _lancarDespesa, child: const Icon(Icons.add)),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Custo por km (últimos 30 dias)', style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(
                          _custoPorKm30dias != null ? '${_moeda.format(_custoPorKm30dias)}/km' : 'Sem dado suficiente ainda',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        if (_custoPorKm30dias == null)
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Text(
                              'Precisa de pelo menos 2 lançamentos com km do odômetro preenchido nos últimos 30 dias.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Histórico', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (_despesas.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('Nenhuma despesa lançada ainda.')),
                  )
                else
                  for (final despesa in _despesas)
                    Card(
                      child: ListTile(
                        title: Text('${rotuloTipoDespesaVeiculo(despesa.tipo)} — ${_moeda.format(despesa.valor)}'),
                        subtitle: Text(
                          '${_data.format(despesa.data)}'
                          '${despesa.kmAtual != null ? ' • ${despesa.kmAtual!.toStringAsFixed(0)} km' : ''}'
                          '${despesa.observacao != null ? '\n${despesa.observacao}' : ''}',
                        ),
                        isThreeLine: despesa.observacao != null,
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _remover(despesa),
                        ),
                      ),
                    ),
              ],
            ),
    );
  }
}
