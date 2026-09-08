import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../repositories/cancelamentos_ifood_repository.dart';
import '../widgets/metric_card.dart';

/// "Cancelamentos iFood" — motivo real de cada pedido cancelado (loja,
/// cliente ou iFood), nunca capturado antes (campos `motivo_do_cancelamento`,
/// `origem_cancelamento_ifood`, `estagio_do_cancelamento` do relatório
/// "Vendas e Pedidos" — ver `registrar_cancelamento_pedido_ifood` no banco).
class CancelamentosIfoodScreen extends StatefulWidget {
  const CancelamentosIfoodScreen({super.key});

  @override
  State<CancelamentosIfoodScreen> createState() => _CancelamentosIfoodScreenState();
}

class _CancelamentosIfoodScreenState extends State<CancelamentosIfoodScreen> {
  final _repository = CancelamentosIfoodRepository();

  late DateTimeRange _periodo;
  String _filtroRotulo = 'Últimos 30 dias';
  bool _carregando = true;
  ResumoCancelamentosIfood _resumo = ResumoCancelamentosIfood.vazio();
  List<CancelamentoIfood> _lista = [];

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
      final lista = await _repository.buscarLista(empresaId: empresaId, dataInicio: _periodo.start, dataFim: _periodo.end);
      if (mounted) setState(() { _resumo = resumo; _lista = lista; });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao carregar cancelamentos: $e')));
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
    final dateFormat = DateFormat('dd/MM');

    return Scaffold(
      appBar: AppBar(title: const Text('Cancelamentos iFood')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _seletorPeriodo(),
                  const SizedBox(height: 12),
                  if (_resumo.totalCancelamentos == 0)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Nenhum cancelamento do iFood nesse período.',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  else ...[
                    MetricGrid(cartoes: [
                      MetricCard(
                        icone: Icons.cancel_outlined,
                        titulo: 'Cancelamentos',
                        valor: '${_resumo.totalCancelamentos}',
                        corIcone: Colors.red,
                      ),
                      MetricCard(
                        icone: Icons.trending_down,
                        titulo: 'Valor perdido',
                        valor: currencyFormat.format(_resumo.valorTotalPerdido),
                        corIcone: Colors.red,
                      ),
                      MetricCard(
                        icone: Icons.priority_high,
                        titulo: 'Motivo mais comum',
                        valor: _resumo.motivoMaisComum ?? '-',
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Card(
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _lista.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final c = _lista[index];
                          final data = c.dtCancelamento ?? c.dtPedido;
                          final subtitulo = [
                            if (c.motivoCancelamento != null && c.motivoCancelamento!.isNotEmpty) c.motivoCancelamento!,
                            if (c.origemCancelamento != null && c.origemCancelamento!.isNotEmpty) c.origemCancelamento!,
                          ].join(' • ');
                          return ListTile(
                            leading: const Icon(Icons.cancel_outlined, color: Colors.red),
                            title: Text(c.codigoExibicao != null ? 'Pedido #${c.codigoExibicao}' : 'Pedido iFood'),
                            subtitle: Text(subtitulo.isEmpty ? 'Motivo não informado' : subtitulo),
                            trailing: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(currencyFormat.format(c.valorPedido), style: const TextStyle(fontWeight: FontWeight.w600)),
                                if (data != null) Text(dateFormat.format(data), style: Theme.of(context).textTheme.bodySmall),
                              ],
                            ),
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
