import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../repositories/qualidade_ifood_repository.dart';
import '../widgets/metric_card.dart';

/// "Qualidade iFood" — nota de avaliação, NPS e reclamação por pedido,
/// nunca capturados antes (campos `nps`, `nota_da_avaliacao`, `teve_contato`,
/// `qtd_chamados_pedido_errado` do relatório "Vendas e Pedidos" — ver
/// `registrar_qualidade_pedido_ifood` no banco).
class QualidadeIfoodScreen extends StatefulWidget {
  const QualidadeIfoodScreen({super.key});

  @override
  State<QualidadeIfoodScreen> createState() => _QualidadeIfoodScreenState();
}

class _QualidadeIfoodScreenState extends State<QualidadeIfoodScreen> {
  final _repository = QualidadeIfoodRepository();

  late DateTimeRange _periodo;
  String _filtroRotulo = 'Últimos 30 dias';
  bool _carregando = true;
  ResumoQualidadeIfood _resumo = ResumoQualidadeIfood.vazio();
  List<PedidoQualidadeIfood> _pedidosProblematicos = [];

  @override
  void initState() {
    super.initState();
    final hoje = DateTime.now();
    _periodo = DateTimeRange(start: hoje.subtract(const Duration(days: 29)), end: hoje);
    _carregar();
  }

  Future<void> _carregar() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;
    setState(() => _carregando = true);
    try {
      final resumo = await _repository.buscarResumo(empresaId: empresaId, dataInicio: _periodo.start, dataFim: _periodo.end);
      final problematicos =
          await _repository.buscarPedidosProblematicos(empresaId: empresaId, dataInicio: _periodo.start, dataFim: _periodo.end);
      if (mounted) setState(() { _resumo = resumo; _pedidosProblematicos = problematicos; });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao carregar qualidade: $e')));
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _escolherPeriodo(String rotulo) async {
    final hoje = DateTime.now();
    DateTimeRange novoPeriodo;
    switch (rotulo) {
      case 'Últimos 7 dias':
        novoPeriodo = DateTimeRange(start: hoje.subtract(const Duration(days: 6)), end: hoje);
        break;
      case 'Últimos 30 dias':
        novoPeriodo = DateTimeRange(start: hoje.subtract(const Duration(days: 29)), end: hoje);
        break;
      case 'Últimos 90 dias':
        novoPeriodo = DateTimeRange(start: hoje.subtract(const Duration(days: 89)), end: hoje);
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
    _carregar();
  }

  Widget _seletorPeriodo() {
    const opcoes = ['Últimos 7 dias', 'Últimos 30 dias', 'Últimos 90 dias', 'Personalizado'];
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

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final dateFormat = DateFormat('dd/MM HH:mm');
    final pctReclamacao =
        _resumo.totalPedidos > 0 ? (_resumo.totalComReclamacao / _resumo.totalPedidos * 100) : 0.0;

    return Scaffold(
      appBar: AppBar(title: const Text('Qualidade iFood')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _seletorPeriodo(),
                  const SizedBox(height: 12),
                  if (_resumo.totalPedidos == 0)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Nenhum pedido do iFood entregue nesse período.',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  else ...[
                    MetricGrid(cartoes: [
                      MetricCard(
                        icone: Icons.star_outline,
                        titulo: 'Nota média',
                        valor: _resumo.notaMedia != null ? _resumo.notaMedia!.toStringAsFixed(1) : '-',
                        subtitulo: '${_resumo.totalAvaliados} avaliado(s)',
                        corIcone: Colors.amber,
                      ),
                      MetricCard(
                        icone: Icons.report_problem_outlined,
                        titulo: 'Com reclamação',
                        valor: '${_resumo.totalComReclamacao}',
                        subtitulo: '${pctReclamacao.toStringAsFixed(1)}% dos pedidos',
                        corIcone: pctReclamacao > 0 ? Colors.red : null,
                      ),
                      MetricCard(
                        icone: Icons.receipt_long,
                        titulo: 'Pedidos no período',
                        valor: '${_resumo.totalPedidos}',
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: Text('Pedidos com reclamação ou nota baixa', style: Theme.of(context).textTheme.titleSmall),
                    ),
                    if (_pedidosProblematicos.isEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('Nenhum pedido com reclamação nesse período.',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                        ),
                      )
                    else
                      Card(
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _pedidosProblematicos.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final p = _pedidosProblematicos[index];
                            final subtitulo = [
                              if (p.notaAvaliacao != null) 'Nota ${p.notaAvaliacao!.toStringAsFixed(0)}',
                              if (p.qtdChamados > 0) '${p.qtdChamados} chamado(s)',
                              if (p.motivoContato != null && p.motivoContato!.isNotEmpty) p.motivoContato!,
                            ].join(' • ');
                            return ListTile(
                              leading: const Icon(Icons.report_problem_outlined, color: Colors.red),
                              title: Text(p.numeroExibicao != null ? 'Pedido #${p.numeroExibicao}' : 'Pedido iFood'),
                              subtitle: Text(subtitulo.isEmpty ? dateFormat.format(p.data) : subtitulo),
                              trailing: Text(currencyFormat.format(p.valorTotal)),
                            );
                          },
                        ),
                      ),
                  ],
                  const SizedBox(height: 12),
                ],
              ),
            ),
    );
  }
}
