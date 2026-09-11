import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/produto_provider.dart';
import '../repositories/ruptura_ifood_repository.dart';
import '../widgets/metric_card.dart';
import 'editar_produto_screen.dart';

/// "Ruptura iFood" — quais produtos mais faltaram/foram recusados nos
/// pedidos do iFood, e quanto de venda isso representou. Fonte: campo
/// `indisponivel`/`desistencia` do relatório "Itens por pedido", capturado
/// pela reconciliação em `registrar_ruptura_relatorio_ifood` — antes desse
/// campo era só descartado, sem deixar rastro nenhum.
class RupturaIfoodScreen extends StatefulWidget {
  const RupturaIfoodScreen({super.key});

  @override
  State<RupturaIfoodScreen> createState() => _RupturaIfoodScreenState();
}

class _RupturaIfoodScreenState extends State<RupturaIfoodScreen> {
  final _repository = RupturaIfoodRepository();

  late DateTimeRange _periodo;
  String _filtroRotulo = 'Últimos 30 dias';
  bool _carregando = true;
  List<RankingRupturaItem> _ranking = [];

  @override
  void initState() {
    super.initState();
    final hoje = DateTime.now();
    _periodo = DateTimeRange(start: hoje.subtract(const Duration(days: 29)), end: hoje);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ProdutoProvider>().carregarProdutos();
    });
    _carregar();
  }

  Future<void> _carregar() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;
    setState(() => _carregando = true);
    try {
      final ranking = await _repository.buscarRanking(
        empresaId: empresaId,
        dataInicio: _periodo.start,
        dataFim: _periodo.end,
      );
      if (mounted) setState(() => _ranking = ranking);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao carregar ruptura: $e')));
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  // Mesmo padrão de período de estatisticas_screen.dart — chips de atalho +
  // showDateRangePicker pra período personalizado.
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

  void _abrirProduto(RankingRupturaItem item) {
    final produtoId = item.produtoId;
    if (produtoId == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Esse item não bateu com nenhum produto do catálogo (EAN não cadastrado).')));
      return;
    }
    final produto = context.read<ProdutoProvider>().produtos.where((p) => p.id == produtoId).firstOrNull;
    if (produto == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Produto não encontrado (pode ter sido excluído).')));
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => EditarProdutoScreen(produto: produto)));
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final totalEventos = _ranking.fold<int>(0, (soma, r) => soma + r.qtdEventos);
    final totalValorPerdido = _ranking.fold<double>(0, (soma, r) => soma + r.valorPerdido);
    final produtoMaisAfetado = _ranking.isNotEmpty ? _ranking.first.produtoNome : '-';

    return Scaffold(
      appBar: AppBar(title: const Text('Ruptura iFood')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _seletorPeriodo(),
                  const SizedBox(height: 12),
                  if (_ranking.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Nenhum evento de ruptura (item indisponível/recusado) nesse período.',
                          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  else ...[
                    MetricGrid(cartoes: [
                      MetricCard(
                        icone: Icons.remove_shopping_cart_outlined,
                        titulo: 'Eventos de ruptura',
                        valor: '$totalEventos',
                        corIcone: Colors.orange,
                      ),
                      MetricCard(
                        icone: Icons.trending_down,
                        titulo: 'Valor perdido estimado',
                        valor: currencyFormat.format(totalValorPerdido),
                        corIcone: Colors.red,
                      ),
                      MetricCard(
                        icone: Icons.priority_high,
                        titulo: 'Produto mais afetado',
                        valor: produtoMaisAfetado,
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Card(
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _ranking.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = _ranking[index];
                          return ListTile(
                            title: Text(item.produtoNome, maxLines: 2, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${item.qtdEventos} evento(s)'),
                            trailing: Text(
                              currencyFormat.format(item.valorPerdido),
                              style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.red),
                            ),
                            onTap: () => _abrirProduto(item),
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
