import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/usuario.dart';
import '../models/venda.dart';
import '../providers/historico_vendas_provider.dart';
import '../providers/usuario_provider.dart';
import '../widgets/metric_card.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

enum _Periodo { hoje, semana, mes }

/// Métricas da equipe (só dono/gerente) — quanto cada pessoa vendeu, pra
/// comparar desempenho entre vendedores. Mostra valor vendido, não lucro/
/// margem (isso já fica só na análise financeira geral, não por pessoa).
class DesempenhoEquipeScreen extends StatefulWidget {
  const DesempenhoEquipeScreen({super.key});

  @override
  State<DesempenhoEquipeScreen> createState() => _DesempenhoEquipeScreenState();
}

class _DesempenhoEquipeScreenState extends State<DesempenhoEquipeScreen> {
  _Periodo _periodo = _Periodo.mes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HistoricoVendasProvider>().carregarVendas();
      context.read<UsuarioProvider>().carregar();
    });
  }

  bool _mesmoDia(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  List<Venda> _filtrarPorPeriodo(List<Venda> vendas) {
    final hoje = DateTime.now();
    switch (_periodo) {
      case _Periodo.hoje:
        return vendas.where((v) => _mesmoDia(v.dataVenda, hoje)).toList();
      case _Periodo.semana:
        final inicioSemana = hoje.subtract(Duration(days: hoje.weekday - 1));
        final inicioSemanaData = DateTime(inicioSemana.year, inicioSemana.month, inicioSemana.day);
        return vendas.where((v) => !v.dataVenda.isBefore(inicioSemanaData)).toList();
      case _Periodo.mes:
        return vendas.where((v) => v.dataVenda.year == hoje.year && v.dataVenda.month == hoje.month).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final usuarios = context.watch<UsuarioProvider>().usuarios.where((u) => u.ativo).toList();
    final todasVendas = context.watch<HistoricoVendasProvider>().vendas.where((v) => v.finalizada).toList();
    final carregando =
        context.watch<HistoricoVendasProvider>().carregando || context.watch<UsuarioProvider>().carregando;

    final vendasPeriodo = _filtrarPorPeriodo(todasVendas);

    final porVendedor = <String, List<Venda>>{};
    var vendasSemVendedor = 0;
    for (final v in vendasPeriodo) {
      final id = v.vendedorId;
      if (id == null) {
        vendasSemVendedor++;
        continue;
      }
      porVendedor.putIfAbsent(id, () => []).add(v);
    }

    final linhas = usuarios.map((usuario) {
      final vendasDele = porVendedor[usuario.id] ?? const <Venda>[];
      final total = vendasDele.fold(0.0, (soma, v) => soma + v.valorTotal);
      return (usuario: usuario, vendas: vendasDele.length, total: total);
    }).toList()
      ..sort((a, b) => b.total.compareTo(a.total));

    final totalEquipe = linhas.fold(0.0, (soma, l) => soma + l.total);
    final vendasEquipe = linhas.fold(0, (soma, l) => soma + l.vendas);
    final ticketMedioEquipe = vendasEquipe == 0 ? 0.0 : totalEquipe / vendasEquipe;

    return Scaffold(
      appBar: AppBar(title: const Text('Desempenho da Equipe')),
      body: carregando && usuarios.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => context.read<HistoricoVendasProvider>().carregarVendas(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _seletorPeriodo(),
                  const SizedBox(height: 16),
                  MetricGrid(
                    cartoes: [
                      MetricCard(
                        icone: Icons.groups_outlined,
                        titulo: 'Vendido pela equipe',
                        valor: _moeda.format(totalEquipe),
                        subtitulo: '$vendasEquipe venda(s)',
                      ),
                      MetricCard(
                        icone: Icons.receipt_long_outlined,
                        titulo: 'Ticket médio',
                        valor: _moeda.format(ticketMedioEquipe),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Por vendedor',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (linhas.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'Nenhum usuário cadastrado na equipe ainda.',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  else
                    ...linhas.indexed.map((par) => _cartaoVendedor(par.$1, par.$2.usuario, par.$2.vendas, par.$2.total,
                        maiorTotal: linhas.first.total)),
                  if (vendasSemVendedor > 0) ...[
                    const SizedBox(height: 12),
                    Text(
                      '$vendasSemVendedor venda(s) do período sem vendedor identificado '
                      '(ex: pedidos de marketplace ou registradas antes desse controle).',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _seletorPeriodo() {
    const opcoes = {_Periodo.hoje: 'Hoje', _Periodo.semana: 'Esta semana', _Periodo.mes: 'Este mês'};
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: opcoes.entries
            .map((entry) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(entry.value),
                    selected: _periodo == entry.key,
                    onSelected: (_) => setState(() => _periodo = entry.key),
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _cartaoVendedor(int posicao, Usuario usuario, int vendas, double total, {required double maiorTotal}) {
    final colorScheme = Theme.of(context).colorScheme;
    final proporcao = maiorTotal <= 0 ? 0.0 : (total / maiorTotal).clamp(0.0, 1.0);
    final semVendas = vendas == 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: posicao == 0 && !semVendas
                      ? colorScheme.primaryContainer
                      : colorScheme.surfaceContainerHighest,
                  child: Text(
                    '${posicao + 1}º',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: posicao == 0 && !semVendas ? colorScheme.primary : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        (usuario.nome?.isNotEmpty == true ? usuario.nome! : usuario.email) ?? 'Usuário',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        usuario.rotuloPapel,
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _moeda.format(total),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '$vendas venda(s)',
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ],
            ),
            if (!semVendas) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: proporcao,
                  minHeight: 6,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
