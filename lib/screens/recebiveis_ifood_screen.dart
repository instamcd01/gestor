import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../repositories/recebiveis_ifood_repository.dart';
import '../widgets/metric_card.dart';

/// "Recebíveis iFood" — quanto e quando o dinheiro do iFood cai na conta
/// (Extrato Financeiro real, capturado por `registrar_lancamentos_financeiros_ifood`),
/// mais uma conferência lado a lado com o valor estimado no checkout. Não
/// existe pedido conciliável ainda porque o extrato só libera 3-4 semanas
/// depois do pedido, e a reconciliação diária só entrou no ar em 06/09.
class RecebiveisIfoodScreen extends StatefulWidget {
  const RecebiveisIfoodScreen({super.key});

  @override
  State<RecebiveisIfoodScreen> createState() => _RecebiveisIfoodScreenState();
}

class _RecebiveisIfoodScreenState extends State<RecebiveisIfoodScreen> {
  final _repository = RecebiveisIfoodRepository();

  late DateTimeRange _periodo;
  String _filtroRotulo = 'Últimos 90 dias';
  bool _carregando = true;
  ResumoRecebiveisIfood _resumo = ResumoRecebiveisIfood.vazio();
  List<RepasseIfood> _repasses = [];
  List<ComparacaoFinanceiraIfood> _comparacao = [];

  @override
  void initState() {
    super.initState();
    final hoje = DateTime.now();
    // Recebíveis olham pra frente (data esperada de pagamento pode ser
    // semanas depois do pedido) — período maior por padrão que as outras
    // telas do iFood.
    _periodo = DateTimeRange(start: hoje.subtract(const Duration(days: 89)), end: hoje.add(const Duration(days: 30)));
    _carregar();
  }

  Future<void> _carregar() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;
    setState(() => _carregando = true);
    try {
      final resumo = await _repository.buscarResumo(empresaId: empresaId, dataInicio: _periodo.start, dataFim: _periodo.end);
      final repasses = await _repository.buscarRepasses(empresaId: empresaId, dataInicio: _periodo.start, dataFim: _periodo.end);
      final comparacao = await _repository.buscarComparacao(empresaId: empresaId, dataInicio: _periodo.start, dataFim: _periodo.end);
      if (mounted) setState(() { _resumo = resumo; _repasses = repasses; _comparacao = comparacao; });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao carregar recebíveis: $e')));
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _escolherPeriodo(String rotulo) async {
    final hoje = DateTime.now();
    DateTimeRange novoPeriodo;
    switch (rotulo) {
      case 'Últimos 30 dias':
        novoPeriodo = DateTimeRange(start: hoje.subtract(const Duration(days: 29)), end: hoje.add(const Duration(days: 30)));
        break;
      case 'Últimos 90 dias':
        novoPeriodo = DateTimeRange(start: hoje.subtract(const Duration(days: 89)), end: hoje.add(const Duration(days: 30)));
        break;
      case 'Personalizado':
        final escolhido = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: hoje.add(const Duration(days: 90)),
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
    const opcoes = ['Últimos 30 dias', 'Últimos 90 dias', 'Personalizado'];
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
      appBar: AppBar(title: const Text('Recebíveis iFood')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _seletorPeriodo(),
                  const SizedBox(height: 12),
                  if (_repasses.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Nenhum lançamento do Extrato Financeiro nesse período. Envie o relatório em "Integração iFood → Enviar relatório do iFood → Extrato Financeiro".',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  else ...[
                    MetricGrid(cartoes: [
                      MetricCard(
                        icone: Icons.hourglass_top,
                        titulo: 'A receber',
                        valor: currencyFormat.format(_resumo.totalAReceber),
                        corIcone: Colors.orange,
                      ),
                      MetricCard(
                        icone: Icons.check_circle_outline,
                        titulo: 'Já recebido',
                        valor: currencyFormat.format(_resumo.totalRecebido),
                        corIcone: Colors.green,
                      ),
                      MetricCard(
                        icone: Icons.receipt_long,
                        titulo: 'Lotes de repasse',
                        valor: '${_repasses.length}',
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      child: Text('Repasses', style: Theme.of(context).textTheme.titleSmall),
                    ),
                    Card(
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _repasses.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final r = _repasses[index];
                          return ListTile(
                            leading: Icon(
                              r.jaCaiu ? Icons.check_circle_outline : Icons.schedule,
                              color: r.jaCaiu ? Colors.green : Colors.orange,
                            ),
                            title: Text(currencyFormat.format(r.valor), style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(r.jaCaiu
                                ? 'Recebido em ${dateFormat.format(r.dataEfetivada!)} • ${r.qtdLancamentos} lançamento(s)'
                                : 'Esperado em ${r.dataEsperada != null ? dateFormat.format(r.dataEsperada!) : '-'} • ${r.qtdLancamentos} lançamento(s)'),
                            trailing: r.titulo != null ? Text('#${r.titulo}', style: Theme.of(context).textTheme.bodySmall) : null,
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Text('Conferência com o Gestor', style: Theme.of(context).textTheme.titleSmall),
                  ),
                  if (_comparacao.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Nenhum pedido apareceu nos dois relatórios ainda — o Extrato Financeiro só libera 3-4 semanas depois do pedido, e a reconciliação diária começou em 06/09. Isso é esperado, não é erro.',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  else
                    Card(
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _comparacao.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final c = _comparacao[index];
                          final diferencaOk = c.diferenca.abs() < 0.05;
                          return ListTile(
                            title: Text(c.codigoExibicao != null ? 'Pedido #${c.codigoExibicao}' : 'Pedido iFood'),
                            subtitle: Text('Estimado: ${currencyFormat.format(c.valorTotalEstimado - c.taxasEstimadas + c.incentivoIfoodEstimado)} • Real: ${currencyFormat.format(c.valorLiquidoReal)}'),
                            trailing: Text(
                              '${diferencaOk ? '' : (c.diferenca > 0 ? '+' : '')}${currencyFormat.format(c.diferenca)}',
                              style: TextStyle(fontWeight: FontWeight.w600, color: diferencaOk ? Colors.green : Colors.red),
                            ),
                          );
                        },
                      ),
                    ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
    );
  }
}
