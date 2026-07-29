import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/marketplace_pedido_financeiro.dart';
import '../repositories/dashboard_marketplace_repository.dart';
import '../widgets/aviso_banner.dart';
import '../widgets/metric_card.dart';

const _rotulosStatusMarketplace = {
  'PLACED': 'Recebido',
  'CONFIRMED': 'Confirmado',
  'PREPARATION_STARTED': 'Em preparo',
  'READY_TO_PICKUP': 'Pronto p/ retirada',
  'DISPATCHED': 'Saiu p/ entrega',
  'CONCLUDED': 'Concluído',
  'CANCELLED': 'Cancelado',
};

class _AgregadoCanal {
  final String nome;
  int pedidos = 0;
  double faturamentoBruto = 0;
  double taxaServicoCliente = 0;
  double taxasConhecidas = 0;
  int comTaxaComissao = 0;
  Duration somaTempoConfirmacao = Duration.zero;
  int comTempoConfirmacao = 0;

  _AgregadoCanal(this.nome);
}

/// Painel financeiro consolidado dos pedidos vindos de marketplace (iFood
/// e, no futuro, outros canais), lendo `marketplace_pedidos` por trás de
/// [DashboardMarketplaceRepository]. Complementa a Estatísticas (que olha
/// vendas em geral) com os campos específicos de marketplace: taxa de
/// serviço do cliente, tempo de confirmação, e o que a Financial API da
/// iFood ainda não libera pra lojas em sandbox (comissão/repasse).
class DashboardMarketplaceScreen extends StatefulWidget {
  const DashboardMarketplaceScreen({super.key});

  @override
  State<DashboardMarketplaceScreen> createState() => _DashboardMarketplaceScreenState();
}

class _DashboardMarketplaceScreenState extends State<DashboardMarketplaceScreen> {
  final _repository = DashboardMarketplaceRepository();

  late DateTimeRange _periodo;
  String _filtroRotulo = 'Este mês';
  bool _carregando = true;
  List<MarketplacePedidoFinanceiro> _pedidos = [];

  @override
  void initState() {
    super.initState();
    final hoje = DateTime.now();
    _periodo = DateTimeRange(start: DateTime(hoje.year, hoje.month, 1), end: hoje);
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final inicio = DateTime(_periodo.start.year, _periodo.start.month, _periodo.start.day);
      final fim = DateTime(_periodo.end.year, _periodo.end.month, _periodo.end.day, 23, 59, 59);
      final pedidos = await _repository.listarPorPeriodo(inicio: inicio, fim: fim);
      if (mounted) setState(() => _pedidos = pedidos);
    } catch (e) {
      debugPrint('Erro ao carregar dashboard de marketplace: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível carregar os dados financeiros de marketplace.')),
        );
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
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
    await _carregar();
  }

  Map<String, _AgregadoCanal> _agregarPorCanal(List<MarketplacePedidoFinanceiro> pedidos) {
    final mapa = <String, _AgregadoCanal>{};
    for (final p in pedidos) {
      final agregado = mapa.putIfAbsent(p.marketplaceNome, () => _AgregadoCanal(p.marketplaceNome));
      agregado.pedidos++;
      agregado.faturamentoBruto += p.valorBrutoMarketplace ?? p.valorTotalPedido;
      agregado.taxaServicoCliente += p.taxaServicoCliente ?? 0;
      agregado.taxasConhecidas += p.taxasConhecidas;
      if (p.taxaComissao != null) agregado.comTaxaComissao++;
      if (p.tempoConfirmacao != null) {
        agregado.somaTempoConfirmacao += p.tempoConfirmacao!;
        agregado.comTempoConfirmacao++;
      }
    }
    return mapa;
  }

  Map<String, int> _contarPorStatus(List<MarketplacePedidoFinanceiro> pedidos) {
    final mapa = <String, int>{};
    for (final p in pedidos) {
      final chave = _rotulosStatusMarketplace[p.statusMarketplace] ?? (p.statusMarketplace ?? 'Desconhecido');
      mapa[chave] = (mapa[chave] ?? 0) + 1;
    }
    return mapa;
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final porCanal = _agregarPorCanal(_pedidos);

    final faturamentoBruto = _pedidos.fold<double>(0, (s, p) => s + (p.valorBrutoMarketplace ?? p.valorTotalPedido));
    final taxaServicoTotal = _pedidos.fold<double>(0, (s, p) => s + (p.taxaServicoCliente ?? 0));
    final numPedidos = _pedidos.length;
    final ticketMedio = numPedidos > 0 ? faturamentoBruto / numPedidos : 0.0;
    final temComissaoConhecida = _pedidos.any((p) => p.taxaComissao != null);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Financeiro por Marketplace'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _carregar),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              // Center + maxWidth: mesmo ajuste do painel Início/Estatísticas
              // — sem isso, em tela larga (barra lateral sempre visível) o
              // conteúdo esticava até a borda e ficava "colado" à esquerda.
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                  _seletorPeriodo(),
                  const SizedBox(height: 12),
                  if (_pedidos.isEmpty)
                    _card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Nenhum pedido de marketplace nesse período.',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  else ...[
                    _gradeKpis(currencyFormat, faturamentoBruto, numPedidos, ticketMedio, taxaServicoTotal, porCanal),
                    const SizedBox(height: 12),
                    if (!temComissaoConhecida) _calloutComissaoBloqueada(),
                    _card(
                      titulo: 'Faturamento bruto por canal',
                      child: SizedBox(height: 180, child: _graficoPorCanal(porCanal)),
                    ),
                    _card(
                      titulo: 'Detalhe por canal',
                      child: _listaPorCanal(porCanal, currencyFormat),
                    ),
                    _card(
                      titulo: 'Pedidos por status',
                      child: _listaProporcaoContagem(_contarPorStatus(_pedidos), numPedidos),
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

  Widget _gradeKpis(NumberFormat format, double faturamentoBruto, int numPedidos, double ticketMedio,
      double taxaServicoTotal, Map<String, _AgregadoCanal> porCanal) {
    final tempos = porCanal.values.where((c) => c.comTempoConfirmacao > 0);
    final somaTempos = tempos.fold<Duration>(Duration.zero, (s, c) => s + c.somaTempoConfirmacao);
    final qtdTempos = tempos.fold<int>(0, (s, c) => s + c.comTempoConfirmacao);
    final tempoMedioConfirmacao = qtdTempos > 0 ? Duration(seconds: somaTempos.inSeconds ~/ qtdTempos) : null;

    // Wrap de cartões de largura fixa, não GridView.count com childAspectRatio
    // fixo — mesmo ajuste feito em estatisticas_screen.dart (rótulos longos
    // como "Taxa de serviço (cliente)" quebravam em 2 linhas numa coluna
    // estreita e estouravam a altura fixa da célula).
    final itens = <(IconData, String, String, Color?)>[
      (Icons.payments_outlined, 'Faturamento bruto', format.format(faturamentoBruto), null),
      (Icons.receipt_long_outlined, 'Pedidos', '$numPedidos', null),
      (Icons.confirmation_number_outlined, 'Ticket médio', format.format(ticketMedio), null),
      (Icons.percent, 'Taxa de serviço (cliente)', format.format(taxaServicoTotal), Colors.orange),
      (
        Icons.timer_outlined,
        'Tempo médio p/ confirmar',
        tempoMedioConfirmacao != null ? _formatarDuracao(tempoMedioConfirmacao) : '—',
        Colors.blueGrey,
      ),
    ];

    return MetricGrid(
      cartoes: itens
          .map((item) => MetricCard(icone: item.$1, titulo: item.$2, valor: item.$3, corIcone: item.$4))
          .toList(),
    );
  }

  Widget _calloutComissaoBloqueada() {
    return const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: AvisoBanner(
        tipo: TipoAviso.alerta,
        texto: 'Comissão e valor repassado ainda não aparecem aqui: a iFood não libera esses dados '
            'enquanto a loja estiver em sandbox/verificação de CNPJ pendente. Assim que for liberado, '
            'os valores passam a entrar automaticamente.',
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

  Widget _graficoPorCanal(Map<String, _AgregadoCanal> porCanal) {
    if (porCanal.isEmpty) {
      return Center(
        child: Text('Sem dados no período.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }

    final canais = porCanal.values.toList()..sort((a, b) => b.faturamentoBruto.compareTo(a.faturamentoBruto));
    final maiorValor = canais.fold<double>(0, (m, c) => c.faturamentoBruto > m ? c.faturamentoBruto : m);
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return BarChart(
      BarChartData(
        maxY: maiorValor <= 0 ? 1 : maiorValor * 1.2,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
              '${canais[group.x.toInt()].nome}\n${currencyFormat.format(rod.toY)}',
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
                if (i < 0 || i >= canais.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(canais[i].nome, style: const TextStyle(fontSize: 11)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < canais.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: canais[i].faturamentoBruto,
                  color: Theme.of(context).colorScheme.primary,
                  width: 28,
                  borderRadius: BorderRadius.circular(4),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _listaPorCanal(Map<String, _AgregadoCanal> porCanal, NumberFormat format) {
    final canais = porCanal.values.toList()..sort((a, b) => b.faturamentoBruto.compareTo(a.faturamentoBruto));
    if (canais.isEmpty) {
      return Text('Sem dados no período.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant));
    }

    return Column(
      children: canais.map((canal) {
        final tempoMedio = canal.comTempoConfirmacao > 0
            ? _formatarDuracao(Duration(seconds: canal.somaTempoConfirmacao.inSeconds ~/ canal.comTempoConfirmacao))
            : '—';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(canal.nome, style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text('${canal.pedidos} pedido${canal.pedidos > 1 ? 's' : ''}',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _metrica('Bruto', format.format(canal.faturamentoBruto)),
                  _metrica('Taxa serviço cliente', format.format(canal.taxaServicoCliente)),
                  _metrica(
                    'Comissão',
                    canal.comTaxaComissao > 0 ? format.format(canal.taxasConhecidas) : 'aguardando iFood',
                  ),
                  _metrica('Confirmação média', tempoMedio),
                ],
              ),
              const Divider(height: 20),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _metrica(String rotulo, String valor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(rotulo, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        Text(valor, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _listaProporcaoContagem(Map<String, int> contagens, int total) {
    final entradas = contagens.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
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
                  Text(entrada.key),
                  Text('${entrada.value} (${pct.toStringAsFixed(0)}%)',
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

  String _formatarDuracao(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    if (d.inHours < 1) return '${d.inMinutes}min';
    return '${d.inHours}h${d.inMinutes.remainder(60)}min';
  }
}
