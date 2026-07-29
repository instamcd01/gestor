import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/venda.dart';
import '../providers/auth_provider.dart';
import '../providers/historico_vendas_provider.dart';
import '../widgets/metric_card.dart';
import 'venda_detalhes_screen.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _dataHora = DateFormat('dd/MM/yyyy HH:mm');

/// Métricas individuais de vendas — cada usuário vê só as próprias vendas
/// (filtradas por `vendedor_id`), nunca as de outra pessoa. Mostra valor
/// vendido, não lucro/margem — isso continua fora do alcance do vendedor,
/// igual ao resto do app.
class MeuDesempenhoScreen extends StatefulWidget {
  const MeuDesempenhoScreen({super.key});

  @override
  State<MeuDesempenhoScreen> createState() => _MeuDesempenhoScreenState();
}

class _MeuDesempenhoScreenState extends State<MeuDesempenhoScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HistoricoVendasProvider>().carregarVendas();
    });
  }

  bool _mesmoDia(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  @override
  Widget build(BuildContext context) {
    final meuId = context.watch<AuthProvider>().usuarioAtual?.id;
    final todasVendas = context.watch<HistoricoVendasProvider>().vendas;
    final carregando = context.watch<HistoricoVendasProvider>().carregando;

    final minhasVendas = todasVendas.where((v) => v.vendedorId == meuId && v.finalizada).toList()
      ..sort((a, b) => b.dataVenda.compareTo(a.dataVenda));

    final hoje = DateTime.now();
    final inicioSemana = hoje.subtract(Duration(days: hoje.weekday - 1));

    final vendasHoje = minhasVendas.where((v) => _mesmoDia(v.dataVenda, hoje)).toList();
    final vendasSemana = minhasVendas
        .where((v) => !v.dataVenda.isBefore(DateTime(inicioSemana.year, inicioSemana.month, inicioSemana.day)))
        .toList();
    final vendasMes =
        minhasVendas.where((v) => v.dataVenda.year == hoje.year && v.dataVenda.month == hoje.month).toList();

    double somar(List<Venda> lista) => lista.fold(0.0, (soma, v) => soma + v.valorTotal);
    final valorMes = somar(vendasMes);
    final ticketMedioMes = vendasMes.isEmpty ? 0.0 : valorMes / vendasMes.length;

    return Scaffold(
      appBar: AppBar(title: const Text('Meu Desempenho')),
      body: carregando && minhasVendas.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => context.read<HistoricoVendasProvider>().carregarVendas(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  MetricGrid(
                    cartoes: [
                      MetricCard(
                        icone: Icons.today,
                        titulo: 'Hoje',
                        valor: _moeda.format(somar(vendasHoje)),
                        subtitulo: '${vendasHoje.length} venda(s)',
                      ),
                      MetricCard(
                        icone: Icons.calendar_view_week,
                        titulo: 'Esta semana',
                        valor: _moeda.format(somar(vendasSemana)),
                        subtitulo: '${vendasSemana.length} venda(s)',
                      ),
                      MetricCard(
                        icone: Icons.calendar_month,
                        titulo: 'Este mês',
                        valor: _moeda.format(valorMes),
                        subtitulo: '${vendasMes.length} venda(s)',
                      ),
                      MetricCard(
                        icone: Icons.receipt_long_outlined,
                        titulo: 'Ticket médio (mês)',
                        valor: _moeda.format(ticketMedioMes),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Minhas vendas recentes',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  if (minhasVendas.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'Nenhuma venda registrada por você ainda.',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  else
                    ...minhasVendas.take(30).map((venda) => Card(
                          child: ListTile(
                            leading: Icon(Icons.receipt, color: Theme.of(context).colorScheme.primary),
                            title: Text(
                              _moeda.format(venda.valorTotal),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text('${venda.cliente.nome} • ${_dataHora.format(venda.dataVenda)}'),
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
