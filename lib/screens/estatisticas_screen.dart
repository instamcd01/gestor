import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/venda.dart';
import '../providers/historico_vendas_provider.dart';
import '../utils/canal_venda_utils.dart';
import '../widgets/metric_card.dart';

class _AgregadoProduto {
  final String nome;
  final int quantidade;
  final double valor;
  _AgregadoProduto({required this.nome, required this.quantidade, required this.valor});
}

class _AgregadoCliente {
  final String nome;
  final int qtdCompras;
  final double valor;
  _AgregadoCliente({required this.nome, required this.qtdCompras, required this.valor});
}

/// Painel de estatísticas reais da empresa (Supabase), calculado em cima
/// das vendas já carregadas pelo HistoricoVendasProvider. Substitui a
/// versão antiga que mostrava números fixos no código.
class EstatisticasScreen extends StatefulWidget {
  const EstatisticasScreen({super.key});

  @override
  State<EstatisticasScreen> createState() => _EstatisticasScreenState();
}

class _EstatisticasScreenState extends State<EstatisticasScreen> {
  late DateTimeRange _periodo;
  String _filtroRotulo = 'Este mês';

  @override
  void initState() {
    super.initState();
    final hoje = DateTime.now();
    _periodo = DateTimeRange(start: DateTime(hoje.year, hoje.month, 1), end: hoje);
    Provider.of<HistoricoVendasProvider>(context, listen: false).carregarVendas();
  }

  List<Venda> _filtrarPeriodo(List<Venda> todas) {
    final inicio = DateTime(_periodo.start.year, _periodo.start.month, _periodo.start.day);
    final fim = DateTime(_periodo.end.year, _periodo.end.month, _periodo.end.day, 23, 59, 59);
    return todas.where((v) {
      if (!v.finalizada) return false;
      return !v.dataVenda.isBefore(inicio) && !v.dataVenda.isAfter(fim);
    }).toList();
  }

  Map<String, double> _somaPor(List<Venda> vendas, String Function(Venda) chave) {
    final mapa = <String, double>{};
    for (final v in vendas) {
      final k = chave(v);
      mapa[k] = (mapa[k] ?? 0) + v.valorTotal;
    }
    return mapa;
  }

  List<_AgregadoProduto> _rankingProdutos(List<Venda> vendas, {int top = 10}) {
    final mapa = <String, _AgregadoProduto>{};
    for (final v in vendas) {
      for (final item in v.itens) {
        final chave = item.produto.id ?? item.produto.nome;
        final atual = mapa[chave];
        mapa[chave] = _AgregadoProduto(
          nome: item.produto.nome,
          quantidade: (atual?.quantidade ?? 0) + item.quantidade,
          valor: (atual?.valor ?? 0) + item.precoTotal,
        );
      }
    }
    final lista = mapa.values.toList()..sort((a, b) => b.valor.compareTo(a.valor));
    return lista.take(top).toList();
  }

  List<_AgregadoCliente> _rankingClientes(List<Venda> vendas, {int top = 10}) {
    final mapa = <String, _AgregadoCliente>{};
    for (final v in vendas) {
      final chave = v.cliente.idCliente ?? v.cliente.nome;
      final atual = mapa[chave];
      mapa[chave] = _AgregadoCliente(
        nome: v.cliente.nome,
        qtdCompras: (atual?.qtdCompras ?? 0) + 1,
        valor: (atual?.valor ?? 0) + v.valorTotal,
      );
    }
    final lista = mapa.values.toList()..sort((a, b) => b.valor.compareTo(a.valor));
    return lista.take(top).toList();
  }

  Map<DateTime, double> _faturamentoPorDia(List<Venda> vendas) {
    final mapa = <DateTime, double>{};
    for (final v in vendas) {
      final dia = DateTime(v.dataVenda.year, v.dataVenda.month, v.dataVenda.day);
      mapa[dia] = (mapa[dia] ?? 0) + v.valorTotal;
    }
    return mapa;
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
    final vendas = _filtrarPeriodo(provider.vendas);

    final faturamento = vendas.fold<double>(0, (soma, v) => soma + v.valorTotal);
    final lucro = vendas.fold<double>(0, (soma, v) => soma + v.lucroTotal);
    final numVendas = vendas.length;
    final ticketMedio = numVendas > 0 ? faturamento / numVendas : 0.0;
    final margem = faturamento > 0 ? (lucro / faturamento * 100) : 0.0;
    final comEntrega = vendas.where((v) => v.temEntrega).length;
    final pctComEntrega = numVendas > 0 ? (comEntrega / numVendas * 100) : 0.0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Estatísticas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: provider.carregarVendas,
          ),
        ],
      ),
      body: provider.carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: provider.carregarVendas,
              // Center + maxWidth: mesmo ajuste do painel Início — em tela
              // larga (barra lateral sempre visível) o conteúdo não deve
              // esticar até a borda, senão fica "colado" no canto esquerdo
              // com um vão vazio grande à direita.
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                  _seletorPeriodo(),
                  const SizedBox(height: 12),
                  if (numVendas == 0)
                    _card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Nenhuma venda finalizada nesse período.',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  else ...[
                    _gradeKpis(currencyFormat, faturamento, numVendas, ticketMedio, lucro, margem, pctComEntrega),
                    const SizedBox(height: 12),
                    _card(
                      titulo: 'Faturamento por dia',
                      child: SizedBox(height: 200, child: _graficoFaturamento(_faturamentoPorDia(vendas))),
                    ),
                    _card(
                      titulo: 'Meios de Pagamento',
                      child: _listaProporcao(_somaPor(vendas, (v) => v.metodoPagamento), faturamento, currencyFormat),
                    ),
                    _card(
                      titulo: 'Vendas por Canal',
                      child: _listaProporcao(
                        _somaPor(vendas, (v) => rotuloCanalVenda(v.canalVenda)),
                        faturamento,
                        currencyFormat,
                      ),
                    ),
                    _card(
                      titulo: 'Ranking de Produtos',
                      child: _listaRankingProdutos(context, _rankingProdutos(vendas), currencyFormat),
                    ),
                    _card(
                      titulo: 'Ranking de Clientes',
                      child: _listaRankingClientes(context, _rankingClientes(vendas), currencyFormat),
                    ),
                  ],
                  const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _seletorPeriodo() {
    const opcoes = ['Hoje', 'Últimos 7 dias', 'Este mês', 'Personalizado'];
    final dateFormat = DateFormat('dd/MM');
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ...opcoes.map((rotulo) => Padding(
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
    );
  }

  Widget _gradeKpis(NumberFormat format, double faturamento, int numVendas, double ticketMedio, double lucro,
      double margem, double pctComEntrega) {
    // Cartões de largura fixa que refluem via Wrap, em vez de GridView.count
    // com childAspectRatio fixo — numa coluna estreita (ex: barra lateral
    // sempre visível tirando espaço da tela) um rótulo mais longo quebrava
    // em 2 linhas e estourava a altura fixa da célula (bottom overflow).
    final itens = <(IconData, String, String, Color?)>[
      (Icons.payments_outlined, 'Faturamento', format.format(faturamento), null),
      (Icons.receipt_long_outlined, 'Vendas', '$numVendas', null),
      (Icons.confirmation_number_outlined, 'Ticket Médio', format.format(ticketMedio), null),
      (Icons.trending_up, 'Lucro Bruto', format.format(lucro), Colors.green),
      (Icons.percent, 'Margem', '${margem.toStringAsFixed(1)}%', Colors.green),
      (Icons.delivery_dining_outlined, 'Com entrega', '${pctComEntrega.toStringAsFixed(0)}%', Colors.orange),
    ];

    return MetricGrid(
      cartoes: itens
          .map((item) => MetricCard(icone: item.$1, titulo: item.$2, valor: item.$3, corIcone: item.$4))
          .toList(),
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

  Widget _graficoFaturamento(Map<DateTime, double> porDia) {
    if (porDia.isEmpty) {
      return Center(
        child: Text('Sem dados no período.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }

    final dias = porDia.keys.toList()..sort();
    final maiorValor = porDia.values.fold<double>(0, (m, v) => v > m ? v : m);
    final dateFormat = DateFormat('dd/MM');
    final passoRotulo = (dias.length / 6).ceil().clamp(1, dias.length);

    return BarChart(
      BarChartData(
        maxY: maiorValor <= 0 ? 1 : maiorValor * 1.2,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
              '${dateFormat.format(dias[group.x.toInt()])}\n${NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$').format(rod.toY)}',
              const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= dias.length || i % passoRotulo != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(dateFormat.format(dias[i]), style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < dias.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [BarChartRodData(toY: porDia[dias[i]] ?? 0, color: Theme.of(context).colorScheme.primary, width: 10, borderRadius: BorderRadius.circular(2))],
            ),
        ],
      ),
    );
  }

  Widget _listaProporcao(Map<String, double> valores, double total, NumberFormat format) {
    final entradas = valores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    if (entradas.isEmpty) {
      return Text('Sem dados no período.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant));
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
                  Text(entrada.key.isEmpty ? 'Não informado' : entrada.key),
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
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _listaRankingProdutos(BuildContext context, List<_AgregadoProduto> ranking, NumberFormat format) {
    if (ranking.isEmpty) {
      return Text('Sem dados no período.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant));
    }
    return Column(
      children: ranking.asMap().entries.map((entry) {
        final posicao = entry.key + 1;
        final produto = entry.value;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(width: 24, child: Text('$posicao°', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
              Expanded(child: Text(produto.nome, overflow: TextOverflow.ellipsis)),
              Text('${produto.quantidade}x', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
              const SizedBox(width: 8),
              Text(format.format(produto.valor), style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _listaRankingClientes(BuildContext context, List<_AgregadoCliente> ranking, NumberFormat format) {
    if (ranking.isEmpty) {
      return Text('Sem dados no período.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant));
    }
    return Column(
      children: ranking.asMap().entries.map((entry) {
        final posicao = entry.key + 1;
        final cliente = entry.value;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(width: 24, child: Text('$posicao°', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
              Expanded(child: Text(cliente.nome, overflow: TextOverflow.ellipsis)),
              Text('${cliente.qtdCompras} compra${cliente.qtdCompras > 1 ? 's' : ''}',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
              const SizedBox(width: 8),
              Text(format.format(cliente.valor), style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        );
      }).toList(),
    );
  }
}
