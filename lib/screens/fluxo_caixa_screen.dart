import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/despesa.dart';
import '../models/venda.dart';
import '../providers/despesa_provider.dart';
import '../providers/historico_vendas_provider.dart';
import '../widgets/valor_destaque_card.dart';

class FluxoCaixaScreen extends StatefulWidget {
  const FluxoCaixaScreen({super.key});

  @override
  State<FluxoCaixaScreen> createState() => _FluxoCaixaScreenState();
}

class _FluxoCaixaScreenState extends State<FluxoCaixaScreen> {
  late DateTimeRange _periodo;
  String _filtroRotulo = 'Este mês';

  @override
  void initState() {
    super.initState();
    final hoje = DateTime.now();
    _periodo = DateTimeRange(start: DateTime(hoje.year, hoje.month, 1), end: hoje);
    Provider.of<HistoricoVendasProvider>(context, listen: false).carregarVendas();
    Provider.of<DespesaProvider>(context, listen: false).carregar();
  }

  bool _dentroDoPeriodo(DateTime data) {
    final inicio = DateTime(_periodo.start.year, _periodo.start.month, _periodo.start.day);
    final fim = DateTime(_periodo.end.year, _periodo.end.month, _periodo.end.day, 23, 59, 59);
    return !data.isBefore(inicio) && !data.isAfter(fim);
  }

  List<Venda> _entradasNoPeriodo(List<Venda> todas) =>
      todas.where((v) => v.finalizada && _dentroDoPeriodo(v.dataVenda)).toList();

  List<Despesa> _saidasNoPeriodo(List<Despesa> todas) =>
      todas.where((d) => d.paga && d.dataPagamento != null && _dentroDoPeriodo(d.dataPagamento!)).toList();

  Future<void> _escolherPeriodo(String rotulo) async {
    final hoje = DateTime.now();
    DateTimeRange novoPeriodo;
    switch (rotulo) {
      case 'Este mês':
        novoPeriodo = DateTimeRange(start: DateTime(hoje.year, hoje.month, 1), end: hoje);
        break;
      case 'Mês passado':
        final mesPassado = DateTime(hoje.year, hoje.month - 1, 1);
        novoPeriodo = DateTimeRange(
          start: mesPassado,
          end: DateTime(hoje.year, hoje.month, 0),
        );
        break;
      case 'Este ano':
        novoPeriodo = DateTimeRange(start: DateTime(hoje.year, 1, 1), end: hoje);
        break;
      case 'Personalizado':
        final escolhido = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: hoje,
          initialDateRange: _periodo,
        );
        if (escolhido == null) return;
        novoPeriodo = escolhido;
        break;
      default:
        return;
    }
    setState(() {
      _periodo = novoPeriodo;
      _filtroRotulo = rotulo;
    });
  }

  Map<String, double> _saidasPorCategoria(List<Despesa> saidas) {
    final mapa = <String, double>{};
    for (final d in saidas) {
      mapa[d.categoria] = (mapa[d.categoria] ?? 0) + d.valor;
    }
    return mapa;
  }

  @override
  Widget build(BuildContext context) {
    final historicoProvider = context.watch<HistoricoVendasProvider>();
    final despesaProvider = context.watch<DespesaProvider>();
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final dateFormat = DateFormat('dd/MM');

    final entradas = _entradasNoPeriodo(historicoProvider.vendas);
    final saidas = _saidasNoPeriodo(despesaProvider.despesas);
    final totalEntradas = entradas.fold<double>(0, (soma, v) => soma + v.valorTotal);
    final totalSaidas = saidas.fold<double>(0, (soma, d) => soma + d.valor);
    final saldo = totalEntradas - totalSaidas;
    final carregando = historicoProvider.carregando || despesaProvider.carregando;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fluxo de Caixa'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              historicoProvider.carregarVendas();
              despesaProvider.carregar();
            },
          ),
        ],
      ),
      body: carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ...['Este mês', 'Mês passado', 'Este ano', 'Personalizado'].map((rotulo) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text(rotulo),
                              selected: _filtroRotulo == rotulo,
                              onSelected: (_) => _escolherPeriodo(rotulo),
                            ),
                          )),
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text(
                          '${dateFormat.format(_periodo.start)} - ${dateFormat.format(_periodo.end)}',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                ValorDestaqueCard(
                  rotulo: 'Saldo do período',
                  valor: currencyFormat.format(saldo),
                  positivo: saldo >= 0,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _cardResumo('Entradas', currencyFormat.format(totalEntradas), Colors.green,
                          '${entradas.length} venda${entradas.length != 1 ? 's' : ''}'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _cardResumo('Saídas', currencyFormat.format(totalSaidas), Colors.red,
                          '${saidas.length} despesa${saidas.length != 1 ? 's' : ''} paga${saidas.length != 1 ? 's' : ''}'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _card(
                  titulo: 'Saídas por Categoria',
                  child: _listaProporcao(_saidasPorCategoria(saidas), totalSaidas, currencyFormat),
                ),
              ],
            ),
    );
  }

  Widget _cardResumo(String titulo, String valor, Color cor, String subtitulo) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(valor, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cor)),
          ),
          const SizedBox(height: 2),
          Text(subtitulo, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _card({String? titulo, required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (titulo != null) ...[
            Text(titulo, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
  }

  Widget _listaProporcao(Map<String, double> valores, double total, NumberFormat format) {
    final entradas = valores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    if (entradas.isEmpty) {
      return Text(
        'Nenhuma saída paga no período.',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      );
    }
    return Column(
      children: entradas.map((entrada) {
        final pct = total > 0 ? (entrada.value / total * 100) : 0.0;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(entrada.key),
                  Text('${format.format(entrada.value)} (${pct.toStringAsFixed(0)}%)',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (pct / 100).clamp(0, 1),
                  minHeight: 6,
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  color: Colors.red,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
