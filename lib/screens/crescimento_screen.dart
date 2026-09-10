import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/auth_provider.dart';

/// Trajetória real de faturamento mês a mês, decomposta por canal — não
/// uma taxa de crescimento única (pesquisa real mostrou que isso esconde
/// mais do que ajuda quando o negócio tem canal entrando em momentos
/// diferentes, ver [[gestor_pedido_compra_fornecedor]]). Mostra os
/// valores absolutos por canal lado a lado, pro dono ver com os próprios
/// olhos o que é crescimento real e o que é composição de canal mudando.
class CrescimentoScreen extends StatefulWidget {
  const CrescimentoScreen({super.key});

  @override
  State<CrescimentoScreen> createState() => _CrescimentoScreenState();
}

class _MesCanal {
  final int ano;
  final int mes;
  final String canal;
  final double faturamento;
  final double lucroBruto;
  final int pedidos;
  _MesCanal({
    required this.ano,
    required this.mes,
    required this.canal,
    required this.faturamento,
    required this.lucroBruto,
    required this.pedidos,
  });
}

const _corPorCanal = {
  'ifood': Color(0xFFEA1D2C),
  'kyte_historico': Color(0xFF9E9E9E),
  'site_proprio': Color(0xFF2E7D32),
  'whatsapp': Color(0xFF25D366),
  'loja_fisica': Color(0xFF1565C0),
  'sem_canal': Color(0xFFBDBDBD),
};

const _nomePorCanal = {
  'ifood': 'iFood',
  'kyte_historico': 'Histórico (site/WhatsApp/loja, pré-Gestor)',
  'site_proprio': 'Site próprio',
  'whatsapp': 'WhatsApp',
  'loja_fisica': 'Loja física',
  'sem_canal': 'Sem canal',
};

class _CrescimentoScreenState extends State<CrescimentoScreen> {
  bool _carregando = true;
  String? _erro;
  List<_MesCanal> _dados = [];

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final resultado = await Supabase.instance.client
          .rpc('crescimento_mensal_por_canal', params: {'p_empresa_id': empresaId});
      if (!mounted) return;
      setState(() {
        _dados = (resultado as List)
            .map((l) => _MesCanal(
                  ano: l['ano'] as int,
                  mes: l['mes'] as int,
                  canal: l['canal'] as String,
                  faturamento: (l['faturamento'] as num).toDouble(),
                  lucroBruto: (l['lucro_bruto'] as num?)?.toDouble() ?? 0,
                  pedidos: l['pedidos'] as int,
                ))
            .toList();
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar: $e';
        _carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Crescimento por canal'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _carregar)],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_erro!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _carregar, child: const Text('Tentar de novo')),
                      ],
                    ),
                  ),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        _cardExplicacao(),
                        const SizedBox(height: 12),
                        _cardRentabilidadePorCanal(),
                        const SizedBox(height: 12),
                        _cardGrafico(),
                        const SizedBox(height: 12),
                        _cardTabela(),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _cardExplicacao() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Text(
        'Faturamento real por mês, separado por canal — de propósito, sem uma "taxa de crescimento" '
        'única resumindo tudo: um número só esconderia quando o crescimento é orgânico (mesmo canal '
        'vendendo mais) de quando é só composição mudando (canal novo entrando). Compare as barras pra '
        'ver isso com seus próprios olhos.',
        style: TextStyle(fontSize: 12.5),
      ),
    );
  }

  /// Faturamento é só metade da história — um canal pode vender mais e
  /// dar menos lucro (comissão/taxa consomem margem de forma diferente
  /// por canal). Soma o período inteiro visível, não só o mês corrente.
  Widget _cardRentabilidadePorCanal() {
    final porCanal = <String, ({double faturamento, double lucro})>{};
    for (final d in _dados) {
      final atual = porCanal[d.canal] ?? (faturamento: 0.0, lucro: 0.0);
      porCanal[d.canal] = (faturamento: atual.faturamento + d.faturamento, lucro: atual.lucro + d.lucroBruto);
    }
    final canais = porCanal.keys.toList()
      ..sort((a, b) => porCanal[b]!.faturamento.compareTo(porCanal[a]!.faturamento));
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

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
          const Text('Rentabilidade por canal (período inteiro)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          const Text('Faturamento maior não significa margem maior — compare os dois.',
              style: TextStyle(fontSize: 11.5, color: Colors.grey)),
          const SizedBox(height: 10),
          for (final c in canais) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Container(width: 10, height: 10, decoration: BoxDecoration(color: _corPorCanal[c] ?? Colors.grey, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_nomePorCanal[c] ?? c, style: const TextStyle(fontSize: 13))),
                  Text(currencyFormat.format(porCanal[c]!.faturamento), style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 10),
                  Text(
                    '${(porCanal[c]!.lucro / (porCanal[c]!.faturamento == 0 ? 1 : porCanal[c]!.faturamento) * 100).toStringAsFixed(1)}% margem',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            if (c != canais.last) const Divider(height: 1),
          ],
        ],
      ),
    );
  }

  Widget _cardGrafico() {
    final meses = <String>[];
    final porMesCanal = <String, Map<String, double>>{};
    for (final d in _dados) {
      final chave = '${d.ano}-${d.mes.toString().padLeft(2, '0')}';
      if (!meses.contains(chave)) meses.add(chave);
      (porMesCanal[chave] ??= {})[d.canal] = d.faturamento;
    }
    meses.sort();
    final canais = _dados.map((d) => d.canal).toSet().toList()
      ..sort((a, b) => (_nomePorCanal[a] ?? a).compareTo(_nomePorCanal[b] ?? b));

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
          const Text('Faturamento mensal por canal', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final c in canais)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 10, height: 10, color: _corPorCanal[c] ?? Colors.grey),
                    const SizedBox(width: 4),
                    Text(_nomePorCanal[c] ?? c, style: const TextStyle(fontSize: 11)),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 260,
            child: meses.isEmpty
                ? const Center(child: Text('Sem dados suficientes ainda.'))
                : BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      titlesData: FlTitlesData(
                        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            interval: (meses.length / 8).ceil().clamp(1, meses.length).toDouble(),
                            getTitlesWidget: (value, meta) {
                              final i = value.toInt();
                              if (i < 0 || i >= meses.length) return const SizedBox.shrink();
                              final partes = meses[i].split('-');
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text('${partes[1]}/${partes[0].substring(2)}', style: const TextStyle(fontSize: 9)),
                              );
                            },
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 48,
                            getTitlesWidget: (value, meta) => Text(
                              value >= 1000 ? '${(value / 1000).toStringAsFixed(0)}k' : value.toStringAsFixed(0),
                              style: const TextStyle(fontSize: 9),
                            ),
                          ),
                        ),
                      ),
                      gridData: const FlGridData(drawVerticalLine: false),
                      borderData: FlBorderData(show: false),
                      barGroups: [
                        for (var i = 0; i < meses.length; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: canais.fold<double>(0, (soma, c) => soma + (porMesCanal[meses[i]]?[c] ?? 0)),
                                rodStackItems: () {
                                  var acumulado = 0.0;
                                  final itens = <BarChartRodStackItem>[];
                                  for (final c in canais) {
                                    final v = porMesCanal[meses[i]]?[c] ?? 0;
                                    itens.add(BarChartRodStackItem(acumulado, acumulado + v, _corPorCanal[c] ?? Colors.grey));
                                    acumulado += v;
                                  }
                                  return itens;
                                }(),
                                width: 12,
                                borderRadius: BorderRadius.zero,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _cardTabela() {
    final meses = <String>[];
    final totalPorMes = <String, double>{};
    for (final d in _dados) {
      final chave = '${d.ano}-${d.mes.toString().padLeft(2, '0')}';
      if (!meses.contains(chave)) meses.add(chave);
      totalPorMes[chave] = (totalPorMes[chave] ?? 0) + d.faturamento;
    }
    meses.sort();
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

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
          const Text('Faturamento total por mês', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          for (var i = 0; i < meses.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_rotuloMes(meses[i])),
                  Row(
                    children: [
                      Text(currencyFormat.format(totalPorMes[meses[i]] ?? 0),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (i > 0) ...[
                        const SizedBox(width: 8),
                        _variacaoChip(totalPorMes[meses[i - 1]] ?? 0, totalPorMes[meses[i]] ?? 0),
                      ],
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _rotuloMes(String chave) {
    const nomes = [
      'jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'
    ];
    final partes = chave.split('-');
    final mes = int.parse(partes[1]);
    return '${nomes[mes - 1]}/${partes[0]}';
  }

  Widget _variacaoChip(double anterior, double atual) {
    if (anterior <= 0) return const SizedBox.shrink();
    final variacao = (atual - anterior) / anterior * 100;
    final cor = variacao >= 0 ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: cor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
      child: Text(
        '${variacao >= 0 ? '▲' : '▼'} ${variacao.abs().toStringAsFixed(0)}%',
        style: TextStyle(fontSize: 11, color: cor, fontWeight: FontWeight.w600),
      ),
    );
  }
}
