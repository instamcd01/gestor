import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/cupom_provider.dart';
import '../repositories/cupom_repository.dart';
import '../widgets/metric_card.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

/// Painel simples de métricas de cupons — quantos ativos, quanto foi
/// dado de desconto no período e o ranking de código mais usado. Mais
/// enxuto que MetricasDespesasScreen de propósito (sem gráfico de
/// tendência mensal) — cupom é um recurso novo aqui, sem histórico
/// suficiente ainda pra uma série temporal ser útil.
class MetricasCuponsScreen extends StatefulWidget {
  const MetricasCuponsScreen({super.key});

  @override
  State<MetricasCuponsScreen> createState() => _MetricasCuponsScreenState();
}

class _MetricasCuponsScreenState extends State<MetricasCuponsScreen> {
  bool _carregando = true;
  List<({String cupomId, String codigo, double valorDesconto, DateTime data})> _usos = [];
  String _filtroRotulo = 'Este mês';
  late DateTime _desde;

  @override
  void initState() {
    super.initState();
    final hoje = DateTime.now();
    _desde = DateTime(hoje.year, hoje.month, 1);
    WidgetsBinding.instance.addPostFrameCallback((_) => context.read<CupomProvider>().carregar());
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final usos = await CupomRepository().buscarUsos(desde: _desde);
      if (!mounted) return;
      setState(() => _usos = usos);
    } catch (e) {
      debugPrint('Erro ao carregar métricas de cupons: $e');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _escolherPeriodo(String rotulo) {
    final hoje = DateTime.now();
    setState(() {
      _filtroRotulo = rotulo;
      _desde = switch (rotulo) {
        'Este mês' => DateTime(hoje.year, hoje.month, 1),
        'Últimos 3 meses' => DateTime(hoje.year, hoje.month - 2, 1),
        'Este ano' => DateTime(hoje.year, 1, 1),
        _ => DateTime(hoje.year, hoje.month, 1),
      };
    });
    _carregar();
  }

  Map<String, ({int usos, double valor})> get _porCodigo {
    final mapa = <String, ({int usos, double valor})>{};
    for (final u in _usos) {
      final atual = mapa[u.codigo] ?? (usos: 0, valor: 0.0);
      mapa[u.codigo] = (usos: atual.usos + 1, valor: atual.valor + u.valorDesconto);
    }
    return mapa;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CupomProvider>();
    final cupons = provider.cupons;
    final ativos = cupons.where((c) => c.ativo).length;
    final totalDesconto = _usos.fold<double>(0, (soma, u) => soma + u.valorDesconto);
    final ranking = _porCodigo.entries.toList()..sort((a, b) => b.value.usos.compareTo(a.value.usos));

    return Scaffold(
      appBar: AppBar(title: const Text('Métricas de Cupons')),
      body: RefreshIndicator(
        onRefresh: () async {
          await provider.carregar();
          await _carregar();
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Agora', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            MetricGrid(
              cartoes: [
                MetricCard(
                  icone: Icons.local_offer_outlined,
                  titulo: 'Cupons ativos',
                  valor: '$ativos',
                  subtitulo: '${cupons.length} no total',
                ),
                MetricCard(
                  icone: Icons.groups_outlined,
                  titulo: 'Exclusivos de cliente',
                  valor: '${cupons.where((c) => c.origem == 'auto_cliente').length}',
                  subtitulo: 'gerados automaticamente',
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text('No período', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _seletorPeriodo(),
            const SizedBox(height: 8),
            if (_carregando)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else ...[
              MetricGrid(
                cartoes: [
                  MetricCard(
                    icone: Icons.check_circle_outline,
                    titulo: 'Usos',
                    valor: '${_usos.length}',
                    corIcone: Colors.green,
                  ),
                  MetricCard(
                    icone: Icons.payments_outlined,
                    titulo: 'Desconto total dado',
                    valor: _moeda.format(totalDesconto),
                    corIcone: Colors.orange,
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Text('Cupons mais usados', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ranking.isEmpty
                      ? Text(
                          'Nenhum cupom usado nesse período.',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        )
                      : Column(
                          children: ranking.map((e) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w600))),
                                  Text('${e.value.usos} uso${e.value.usos == 1 ? '' : 's'}'),
                                  const SizedBox(width: 12),
                                  Text(_moeda.format(e.value.valor)),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _seletorPeriodo() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: ['Este mês', 'Últimos 3 meses', 'Este ano'].map((rotulo) {
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
}
