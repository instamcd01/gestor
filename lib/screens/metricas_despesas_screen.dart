import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/despesa.dart';
import '../providers/despesa_provider.dart';
import '../repositories/entrada_repository.dart';
import '../widgets/metric_card.dart';
import 'despesas_screen.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

// Evita `DateFormat('MMM', 'pt_BR')` de propósito — precisaria de
// `initializeDateFormatting('pt_BR')`, que este app nunca chama em
// lugar nenhum (todo `DateFormat` existente usa padrão numérico, sem
// nome de mês, exatamente pra não depender disso). Uma lista fixa evita
// adicionar essa inicialização só pra isso.
const _mesesAbreviados = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
String _formatarMes(DateTime data) => _mesesAbreviados[data.month - 1];

// Paleta categórica validada (dataviz skill: script de validação rodado nos
// 5 primeiros slots, light e dark — todos os checks passam). Ordem fixa,
// nunca ciclada — cada fornecedor sempre usa o mesmo slot enquanto estiver
// entre os top 5, independente de reordenação por valor.
const _paletaCategorica = [
  Color(0xFF2A78D6), // blue
  Color(0xFFEB6834), // orange
  Color(0xFF1BAF7A), // aqua
  Color(0xFFEDA100), // yellow
  Color(0xFFE87BA4), // magenta
];
const _corBoa = Color(0xFF0CA30C); // status "good" — pago
const _corAlerta = Color(0xFFFAB219); // status "warning" — em aberto

/// Painel de métricas de contas a pagar — pensado pra decisão de
/// estratégia, não só leitura passiva: além do estado atual (pendente,
/// atrasado, vence em 7 dias), mostra tendência (volume de contas por mês
/// de vencimento, projeção de saída de caixa nas próximas semanas) e
/// custo médio por fornecedor ao longo do tempo, pra notar se algum
/// fornecedor está ficando mais caro. Complementa o Fluxo de Caixa (que só
/// olha o que já foi pago/vendido num período).
class MetricasDespesasScreen extends StatefulWidget {
  const MetricasDespesasScreen({super.key});

  @override
  State<MetricasDespesasScreen> createState() => _MetricasDespesasScreenState();
}

class _MetricasDespesasScreenState extends State<MetricasDespesasScreen> {
  late DateTimeRange _periodo;
  String _filtroRotulo = 'Este mês';

  bool _carregandoCustos = true;
  List<({String fornecedorId, String fornecedorNome, DateTime dataEntrada, double custoUnitario, double quantidade})>
      _custosBrutos = [];

  @override
  void initState() {
    super.initState();
    final hoje = DateTime.now();
    _periodo = DateTimeRange(start: DateTime(hoje.year, hoje.month, 1), end: hoje);
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<DespesaProvider>().carregar());
    _carregarCustosPorFornecedor();
  }

  Future<void> _carregarCustosPorFornecedor() async {
    final desde = DateTime(DateTime.now().year, DateTime.now().month - 5, 1);
    try {
      final dados = await EntradaRepository().buscarCustosPorFornecedor(desde: desde);
      if (!mounted) return;
      setState(() {
        _custosBrutos = dados;
        _carregandoCustos = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregandoCustos = false);
    }
  }

  Future<void> _escolherPeriodo(String rotulo) async {
    final hoje = DateTime.now();
    DateTimeRange novoPeriodo;
    switch (rotulo) {
      case 'Este mês':
        novoPeriodo = DateTimeRange(start: DateTime(hoje.year, hoje.month, 1), end: hoje);
        break;
      case 'Mês passado':
        novoPeriodo = DateTimeRange(start: DateTime(hoje.year, hoje.month - 1, 1), end: DateTime(hoje.year, hoje.month, 0));
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

  bool _dentroDoPeriodo(DateTime data) {
    final inicio = DateTime(_periodo.start.year, _periodo.start.month, _periodo.start.day);
    final fim = DateTime(_periodo.end.year, _periodo.end.month, _periodo.end.day, 23, 59, 59);
    return !data.isBefore(inicio) && !data.isAfter(fim);
  }

  double _somar(List<Despesa> lista) => lista.fold(0.0, (soma, d) => soma + d.valor);

  void _abrir(String filtro) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => DespesasScreen(filtroInicial: filtro)));
  }

  /// Top 5 por valor + "Outros" agregando o resto — sem isso, uma lista
  /// com muitas categorias/fornecedores vira uma parede de valores pequenos.
  Map<String, double> _top5MaisOutros(Map<String, double> valores) {
    final entradas = valores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    if (entradas.length <= 5) return valores;
    final top5 = entradas.take(5);
    final outros = entradas.skip(5).fold<double>(0, (soma, e) => soma + e.value);
    return {for (final e in top5) e.key: e.value, 'Outros': outros};
  }

  Map<String, double> _porCategoria(List<Despesa> despesas) {
    final mapa = <String, double>{};
    for (final d in despesas) {
      mapa[d.categoria] = (mapa[d.categoria] ?? 0) + d.valor;
    }
    return mapa;
  }

  Map<String, double> _porFornecedor(List<Despesa> despesas) {
    final mapa = <String, double>{};
    for (final d in despesas) {
      final nome = d.fornecedor?.nome ?? 'Sem fornecedor';
      mapa[nome] = (mapa[nome] ?? 0) + d.valor;
    }
    return mapa;
  }

  List<DateTime> _ultimosMeses(int n) {
    final hoje = DateTime.now();
    return List.generate(n, (i) => DateTime(hoje.year, hoje.month - (n - 1 - i), 1));
  }

  int _indiceDoMes(List<DateTime> meses, DateTime data) {
    final mesRef = DateTime(data.year, data.month, 1);
    return meses.indexWhere((m) => m.year == mesRef.year && m.month == mesRef.month);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<DespesaProvider>();
    final despesas = provider.despesas;
    final hoje = DateTime.now();

    final pendentes = despesas.where((d) => d.status == StatusDespesa.pendente).toList();
    final atrasadas = pendentes.where((d) => d.atrasada).toList();
    final venceEm7Dias =
        pendentes.where((d) => !d.atrasada && d.dataVencimento.isBefore(hoje.add(const Duration(days: 8)))).toList();
    final aVencer = pendentes.where((d) => !d.atrasada).toList();
    final pagasNoPeriodo = despesas.where((d) => d.paga && d.dataPagamento != null && _dentroDoPeriodo(d.dataPagamento!)).toList();
    final canceladasNoPeriodo =
        despesas.where((d) => d.cancelada && d.dataCancelamento != null && _dentroDoPeriodo(d.dataCancelamento!)).toList();

    DateTime? proximoVencimento;
    for (final d in pendentes) {
      if (proximoVencimento == null || d.dataVencimento.isBefore(proximoVencimento)) {
        proximoVencimento = d.dataVencimento;
      }
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Métricas de Contas a Pagar')),
      body: provider.carregando && despesas.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await provider.carregar();
                await _carregarCustosPorFornecedor();
              },
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text('Agora', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  MetricGrid(
                    cartoes: [
                      MetricCard(
                        icone: Icons.pending_actions_outlined,
                        titulo: 'Total pendente',
                        valor: _moeda.format(_somar(pendentes)),
                        subtitulo: '${pendentes.length} conta(s)',
                        onTap: () => _abrir('Pendentes'),
                      ),
                      MetricCard(
                        icone: Icons.warning_amber_outlined,
                        titulo: 'Atrasadas',
                        valor: _moeda.format(_somar(atrasadas)),
                        subtitulo: '${atrasadas.length} conta(s)',
                        corIcone: atrasadas.isNotEmpty ? Colors.red : null,
                        onTap: () => _abrir('Atrasadas'),
                      ),
                      MetricCard(
                        icone: Icons.event_busy_outlined,
                        titulo: 'Vence em 7 dias',
                        valor: _moeda.format(_somar(venceEm7Dias)),
                        subtitulo: '${venceEm7Dias.length} conta(s)',
                        corIcone: venceEm7Dias.isNotEmpty ? Colors.orange : null,
                        onTap: () => _abrir('Pendentes'),
                      ),
                      MetricCard(
                        icone: Icons.event_outlined,
                        titulo: 'A vencer (total)',
                        valor: _moeda.format(_somar(aVencer)),
                        subtitulo: proximoVencimento != null ? 'Próxima em ${DateFormat('dd/MM').format(proximoVencimento)}' : null,
                        onTap: () => _abrir('Pendentes'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Text('No período', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _seletorPeriodo(),
                  const SizedBox(height: 8),
                  MetricGrid(
                    cartoes: [
                      MetricCard(
                        icone: Icons.check_circle_outline,
                        titulo: 'Pagas',
                        valor: _moeda.format(_somar(pagasNoPeriodo)),
                        subtitulo: '${pagasNoPeriodo.length} conta(s)',
                        corIcone: Colors.green,
                        onTap: () => _abrir('Pagas'),
                      ),
                      MetricCard(
                        icone: Icons.cancel_outlined,
                        titulo: 'Canceladas',
                        valor: '${canceladasNoPeriodo.length}',
                        subtitulo: canceladasNoPeriodo.isNotEmpty ? _moeda.format(_somar(canceladasNoPeriodo)) : null,
                        corIcone: Colors.grey,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _card(
                    titulo: 'Volume de contas por mês de vencimento',
                    subtitulo: 'Pago vs. ainda em aberto hoje, por mês em que a conta venceu — últimos 6 meses.',
                    child: SizedBox(height: 220, child: _graficoEvolucaoMensal(despesas)),
                  ),
                  _card(
                    titulo: 'Projeção de saída de caixa',
                    subtitulo: 'Soma das contas pendentes por semana de vencimento — próximas 8 semanas.',
                    child: SizedBox(height: 220, child: _graficoProjecao(pendentes)),
                  ),
                  _card(
                    titulo: 'Custo médio por fornecedor ao longo do tempo',
                    subtitulo: 'Top 5 fornecedores por volume comprado — só considera compras já importadas por NF-e.',
                    child: _carregandoCustos
                        ? const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()))
                        : SizedBox(height: 240, child: _graficoCustoPorFornecedor()),
                  ),
                  const SizedBox(height: 12),
                  Text('Pendentes por categoria', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _cardProporcao(_top5MaisOutros(_porCategoria(pendentes)), _somar(pendentes)),
                  const SizedBox(height: 20),
                  Text('Pendentes por fornecedor', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  _cardProporcao(_top5MaisOutros(_porFornecedor(pendentes)), _somar(pendentes)),
                ],
              ),
            ),
    );
  }

  Widget _seletorPeriodo() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: ['Este mês', 'Mês passado', 'Personalizado'].map((rotulo) {
          return Padding(
            padding: const EdgeInsets.only(left: 8),
            child: ChoiceChip(
              label: Text(rotulo, style: const TextStyle(fontSize: 12)),
              visualDensity: VisualDensity.compact,
              selected: _filtroRotulo == rotulo,
              onSelected: (_) => _escolherPeriodo(rotulo),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _card({required String titulo, String? subtitulo, required Widget child}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            if (subtitulo != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(subtitulo, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
              ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _cardProporcao(Map<String, double> valores, double total) {
    final entradas = valores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: entradas.isEmpty
            ? Text('Nada pendente por aqui.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
            : Column(
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
                            Expanded(child: Text(entrada.key, maxLines: 1, overflow: TextOverflow.ellipsis)),
                            const SizedBox(width: 8),
                            Text('${_moeda.format(entrada.value)} (${pct.toStringAsFixed(0)}%)',
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
                            color: Colors.orange,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
      ),
    );
  }

  // --- Gráfico 1: volume de contas por mês de vencimento (2 séries) ---

  Widget _graficoEvolucaoMensal(List<Despesa> despesas) {
    final meses = _ultimosMeses(6);
    final pago = List<double>.filled(6, 0);
    final emAberto = List<double>.filled(6, 0);

    for (final d in despesas) {
      final i = _indiceDoMes(meses, d.dataVencimento);
      if (i == -1) continue;
      if (d.paga) {
        pago[i] += d.valor;
      } else if (!d.cancelada) {
        emAberto[i] += d.valor;
      }
    }

    final maior = [...pago, ...emAberto].fold<double>(0, (m, v) => v > m ? v : m);
    if (maior <= 0) {
      return Center(child: Text('Sem dados nos últimos 6 meses.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)));
    }

    Widget legendaItem(Color cor, IconData icone, String rotulo) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 14, color: cor),
            const SizedBox(width: 4),
            Text(rotulo, style: const TextStyle(fontSize: 12)),
          ],
        );

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            legendaItem(_corBoa, Icons.check_circle, 'Pago'),
            const SizedBox(width: 16),
            legendaItem(_corAlerta, Icons.pending, 'Em aberto'),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maior * 1.2,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => spots.map((s) {
                    final rotulo = s.barIndex == 0 ? 'Pago' : 'Em aberto';
                    return LineTooltipItem('$rotulo\n${_moeda.format(s.y)}', const TextStyle(color: Colors.white, fontSize: 12));
                  }).toList(),
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= meses.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(_formatarMes(meses[i]), style: const TextStyle(fontSize: 10)),
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: [for (var i = 0; i < meses.length; i++) FlSpot(i.toDouble(), pago[i])],
                  color: _corBoa,
                  barWidth: 2,
                  dotData: const FlDotData(show: true),
                  isCurved: false,
                ),
                LineChartBarData(
                  spots: [for (var i = 0; i < meses.length; i++) FlSpot(i.toDouble(), emAberto[i])],
                  color: _corAlerta,
                  barWidth: 2,
                  dotData: const FlDotData(show: true),
                  isCurved: false,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- Gráfico 2: projeção de saída de caixa (próximas 8 semanas) ---

  Widget _graficoProjecao(List<Despesa> pendentes) {
    final hoje = DateTime.now();
    final inicioSemana = DateTime(hoje.year, hoje.month, hoje.day).subtract(Duration(days: hoje.weekday - 1));
    final semanas = List.generate(8, (i) => inicioSemana.add(Duration(days: 7 * i)));
    final valores = List<double>.filled(8, 0);

    for (final d in pendentes) {
      for (var i = 0; i < semanas.length; i++) {
        final fim = semanas[i].add(const Duration(days: 7));
        if (!d.dataVencimento.isBefore(semanas[i]) && d.dataVencimento.isBefore(fim)) {
          valores[i] += d.valor;
          break;
        }
      }
    }

    final maior = valores.fold<double>(0, (m, v) => v > m ? v : m);
    if (maior <= 0) {
      return Center(child: Text('Nenhuma conta pendente nas próximas 8 semanas.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)));
    }

    final dateFormat = DateFormat('dd/MM');
    return BarChart(
      BarChartData(
        maxY: maior * 1.2,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
              'Semana de ${dateFormat.format(semanas[group.x.toInt()])}\n${_moeda.format(rod.toY)}',
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
                if (i < 0 || i >= semanas.length || i % 2 != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(dateFormat.format(semanas[i]), style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < semanas.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [BarChartRodData(toY: valores[i], color: Theme.of(context).colorScheme.primary, width: 14, borderRadius: BorderRadius.circular(2))],
            ),
        ],
      ),
    );
  }

  // --- Gráfico 3: custo médio por fornecedor ao longo do tempo (top 5) ---

  Widget _graficoCustoPorFornecedor() {
    if (_custosBrutos.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            'Ainda não há dados suficientes — esse gráfico usa o histórico de importações de Nota Fiscal. '
            'Quanto mais notas importadas, mais preciso fica.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    final meses = _ultimosMeses(6);
    // fornecedorId -> (nome, soma custo*qtd por mês, soma qtd por mês, qtd total no período)
    final porFornecedor = <String, ({String nome, List<double> somaCustoQtd, List<double> somaQtd, double totalQtd})>{};

    for (final linha in _custosBrutos) {
      final i = _indiceDoMes(meses, linha.dataEntrada);
      if (i == -1) continue;
      final atual = porFornecedor[linha.fornecedorId] ??
          (nome: linha.fornecedorNome, somaCustoQtd: List<double>.filled(6, 0), somaQtd: List<double>.filled(6, 0), totalQtd: 0.0);
      atual.somaCustoQtd[i] += linha.custoUnitario * linha.quantidade;
      atual.somaQtd[i] += linha.quantidade;
      porFornecedor[linha.fornecedorId] = (
        nome: atual.nome,
        somaCustoQtd: atual.somaCustoQtd,
        somaQtd: atual.somaQtd,
        totalQtd: atual.totalQtd + linha.quantidade,
      );
    }

    final top5 = porFornecedor.entries.toList()..sort((a, b) => b.value.totalQtd.compareTo(a.value.totalQtd));
    final selecionados = top5.take(5).toList();

    if (selecionados.isEmpty) {
      return Center(child: Text('Sem dados nos últimos 6 meses.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)));
    }

    double maior = 0;
    final series = <(String nome, Color cor, List<FlSpot>)>[];
    for (var f = 0; f < selecionados.length; f++) {
      final dados = selecionados[f].value;
      final spots = <FlSpot>[];
      for (var i = 0; i < meses.length; i++) {
        if (dados.somaQtd[i] <= 0) continue;
        final media = dados.somaCustoQtd[i] / dados.somaQtd[i];
        if (media > maior) maior = media;
        spots.add(FlSpot(i.toDouble(), media));
      }
      if (spots.isNotEmpty) series.add((dados.nome, _paletaCategorica[f], spots));
    }

    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 12,
          runSpacing: 4,
          children: series
              .map((s) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: s.$2, shape: BoxShape.circle)),
                      const SizedBox(width: 4),
                      Text(s.$1, style: const TextStyle(fontSize: 12)),
                    ],
                  ))
              .toList(),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: maior * 1.2,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => spots.map((s) {
                    final nome = series[s.barIndex].$1;
                    return LineTooltipItem('$nome\n${_moeda.format(s.y)}', const TextStyle(color: Colors.white, fontSize: 12));
                  }).toList(),
                ),
              ),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final i = value.toInt();
                      if (i < 0 || i >= meses.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(_formatarMes(meses[i]), style: const TextStyle(fontSize: 10)),
                      );
                    },
                  ),
                ),
              ),
              lineBarsData: [
                for (final s in series)
                  LineChartBarData(spots: s.$3, color: s.$2, barWidth: 2, dotData: const FlDotData(show: true), isCurved: false),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
