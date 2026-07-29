import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/venda.dart';
import '../providers/historico_vendas_provider.dart';
import '../widgets/valor_destaque_card.dart';
import 'venda_detalhes_screen.dart';

/// "Entradas" no menu de Finanças = receita real das vendas finalizadas
/// (mesma fonte de dados do Histórico de Vendas/Estatísticas), só que numa
/// visão focada em "quanto entrou" por período, sem os filtros de busca.
class EntradasScreen extends StatefulWidget {
  const EntradasScreen({super.key});

  @override
  State<EntradasScreen> createState() => _EntradasScreenState();
}

class _EntradasScreenState extends State<EntradasScreen> {
  late DateTimeRange _periodo;
  String _filtroRotulo = 'Este mês';

  @override
  void initState() {
    super.initState();
    final hoje = DateTime.now();
    _periodo = DateTimeRange(start: DateTime(hoje.year, hoje.month, 1), end: hoje);
    Provider.of<HistoricoVendasProvider>(context, listen: false).carregarVendas();
  }

  List<Venda> _noPeriodo(List<Venda> todas) {
    final inicio = DateTime(_periodo.start.year, _periodo.start.month, _periodo.start.day);
    final fim = DateTime(_periodo.end.year, _periodo.end.month, _periodo.end.day, 23, 59, 59);
    final filtradas = todas.where((v) {
      if (!v.finalizada) return false;
      return !v.dataVenda.isBefore(inicio) && !v.dataVenda.isAfter(fim);
    }).toList();
    filtradas.sort((a, b) => b.dataVenda.compareTo(a.dataVenda));
    return filtradas;
  }

  Future<void> _escolherPeriodo(String rotulo) async {
    final hoje = DateTime.now();
    DateTimeRange novoPeriodo;
    switch (rotulo) {
      case 'Hoje':
        novoPeriodo = DateTimeRange(start: DateTime(hoje.year, hoje.month, hoje.day), end: hoje);
        break;
      case 'Últimos 7 dias':
        novoPeriodo = DateTimeRange(start: hoje.subtract(const Duration(days: 6)), end: hoje);
        break;
      case 'Este mês':
        novoPeriodo = DateTimeRange(start: DateTime(hoje.year, hoje.month, 1), end: hoje);
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

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HistoricoVendasProvider>();
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');
    final vendas = _noPeriodo(provider.vendas);
    final total = vendas.fold<double>(0, (soma, v) => soma + v.valorTotal);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Entradas'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: provider.carregarVendas),
        ],
      ),
      body: provider.carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: provider.carregarVendas,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: ['Hoje', 'Últimos 7 dias', 'Este mês', 'Personalizado'].map((rotulo) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(rotulo),
                            selected: _filtroRotulo == rotulo,
                            onSelected: (_) => _escolherPeriodo(rotulo),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ValorDestaqueCard(
                    rotulo: 'Total de entradas no período',
                    valor: currencyFormat.format(total),
                    subtitulo: '${vendas.length} venda${vendas.length != 1 ? 's' : ''}',
                  ),
                  const SizedBox(height: 12),
                  if (vendas.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.arrow_downward, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            const SizedBox(height: 12),
                            Text(
                              'Nenhuma entrada nesse período.',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    ...vendas.map((venda) => Card(
                          child: ListTile(
                            title: Text(venda.cliente.nome),
                            subtitle: Text('${dateFormat.format(venda.dataVenda)} • ${venda.metodoPagamento}'),
                            trailing: Text(currencyFormat.format(venda.valorTotal),
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => VendaDetalhesScreen(venda: venda)),
                            ),
                          ),
                        )),
                ],
              ),
            ),
    );
  }
}
