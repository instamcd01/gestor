import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/historico_vendas_provider.dart';
import '../models/venda.dart';
import 'venda_detalhes_screen.dart';

class HistoricoVendasScreen extends StatefulWidget {
  const HistoricoVendasScreen({super.key});

  @override
  State<HistoricoVendasScreen> createState() => _HistoricoVendasScreenState();
}

class _HistoricoVendasScreenState extends State<HistoricoVendasScreen> {
  final _searchController = TextEditingController();
  DateTimeRange? _filtroPeriodo;
  String? _filtroPagamento;

  @override
  void initState() {
    super.initState();
    _carregarVendas();
    _searchController.addListener(() => setState(() {}));
  }

  Future<void> _carregarVendas() async {
    await Provider.of<HistoricoVendasProvider>(context, listen: false).carregarVendas();
  }

  bool get _temFiltroAtivo => _filtroPeriodo != null || _filtroPagamento != null;

  List<Venda> _aplicarFiltros(List<Venda> vendas) {
    final termo = _searchController.text.toLowerCase();

    return vendas.where((venda) {
      if (termo.isNotEmpty) {
        final nome = venda.cliente.nome.toLowerCase();
        final id = (venda.idVenda ?? '').toLowerCase();
        if (!nome.contains(termo) && !id.contains(termo)) return false;
      }

      if (_filtroPeriodo != null) {
        final dia = DateTime(venda.dataVenda.year, venda.dataVenda.month, venda.dataVenda.day);
        final inicio = DateTime(
            _filtroPeriodo!.start.year, _filtroPeriodo!.start.month, _filtroPeriodo!.start.day);
        final fim = DateTime(_filtroPeriodo!.end.year, _filtroPeriodo!.end.month, _filtroPeriodo!.end.day);
        if (dia.isBefore(inicio) || dia.isAfter(fim)) return false;
      }

      if (_filtroPagamento != null && venda.metodoPagamento != _filtroPagamento) {
        return false;
      }

      return true;
    }).toList();
  }

  List<String> _metodosPagamentoDisponiveis(List<Venda> vendas) {
    final metodos = vendas.map((v) => v.metodoPagamento).where((m) => m.isNotEmpty).toSet().toList();
    metodos.sort();
    return metodos;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Map<String, List<Venda>> _agruparVendasPorData(List<Venda> vendas) {
    final Map<String, List<Venda>> agrupadas = {};
    final dateFormat = DateFormat('dd/MM/yyyy');

    for (final venda in vendas) {
      final dataString = dateFormat.format(venda.dataVenda);
      agrupadas.putIfAbsent(dataString, () => []).add(venda);
    }

    // Ordenar as datas da mais recente para a mais antiga
    final sortedKeys = agrupadas.keys.toList()
      ..sort((a, b) => dateFormat.parse(b).compareTo(dateFormat.parse(a)));

    return Map.fromEntries(
      sortedKeys.map((key) => MapEntry(key, agrupadas[key]!)),
    );
  }

  Map<String, dynamic> _calcularTotais(List<Venda> vendas) {
    final hoje = DateTime.now();
    double valorTotalMes = 0.0;
    int qtdVendasMes = 0;

    for (final venda in vendas) {
      if (venda.finalizada &&
          venda.dataVenda.month == hoje.month &&
          venda.dataVenda.year == hoje.year) {
        valorTotalMes += venda.valorTotal;
        qtdVendasMes++;
      }
    }

    return {
      'valorTotalMes': valorTotalMes,
      'qtdVendasMes': qtdVendasMes,
    };
  }

  @override
  Widget build(BuildContext context) {
    final historicoProvider = Provider.of<HistoricoVendasProvider>(context);
    final auth = context.watch<AuthProvider>();
    // Vendedor vê só as próprias vendas — lista E resumo (calculado a
    // partir do que sobra aqui, então já sai correto pros dois em vez de
    // esconder o resumo inteiro). Dono/gerente continuam vendo tudo, igual
    // sempre foi.
    final todasVendas = auth.isVendedor
        ? historicoProvider.vendas.where((v) => v.vendedorId == auth.usuarioAtual?.id).toList()
        : historicoProvider.vendas;
    final vendas = _aplicarFiltros(todasVendas);
    final vendasAgrupadas = _agruparVendasPorData(vendas);
    final totaisMes = _calcularTotais(todasVendas);
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final carregando = historicoProvider.carregando;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico de Vendas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregarVendas,
          ),
          IconButton(
            icon: Icon(_temFiltroAtivo ? Icons.filter_alt : Icons.filter_list),
            color: _temFiltroAtivo ? Theme.of(context).colorScheme.primary : null,
            onPressed: () => _mostrarFiltros(context, todasVendas),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Pesquisar por nome do cliente ou ID da venda...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: _searchController.clear,
                ),
              ),
            ),
          ),
          if (carregando)
            const LinearProgressIndicator()
          else if (vendas.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(height: 16),
                    Text(
                      todasVendas.isEmpty ? 'Nenhuma venda registrada' : 'Nenhuma venda encontrada para os filtros aplicados',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    TextButton(
                      onPressed: _carregarVendas,
                      child: const Text('Recarregar'),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _carregarVendas,
                child: ListView(
                  children: [
                    _buildResumoMensal(context, totaisMes, currencyFormat),
                    ...vendasAgrupadas.entries.map((entry) {
                      final valorTotalDia = entry.value
                          .where((venda) => venda.finalizada)
                          .fold(0.0, (sum, venda) => sum + venda.valorTotal);

                      return _buildDiaVendas(
                        context,
                        entry.key,
                        entry.value,
                        valorTotalDia,
                        currencyFormat,
                      );
                    }),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResumoMensal(BuildContext context, Map<String, dynamic> totais, NumberFormat format) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'RESUMO DO MÊS',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total de vendas:'),
                Text(
                  totais['qtdVendasMes'].toString(),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Valor total:'),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    format.format(totais['valorTotalMes']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiaVendas(
      BuildContext context,
      String data,
      List<Venda> vendasDoDia,
      double valorTotalDia,
      NumberFormat format,
      ) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ExpansionTile(
        title: Text(
          DateFormat('EEEE, dd/MM/yyyy').format(DateFormat('dd/MM/yyyy').parse(data)),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${vendasDoDia.length} venda${vendasDoDia.length > 1 ? 's' : ''} • Total: ${format.format(valorTotalDia)}',
        ),
        children: vendasDoDia.map((venda) => _buildItemVenda(context, venda, format)).toList(),
      ),
    );
  }

  Widget _buildItemVenda(BuildContext context, Venda venda, NumberFormat format) {
    final timeFormat = DateFormat('HH:mm');
    final cancelada = venda.cancelada;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: cancelada ? Colors.grey[300] : Theme.of(context).colorScheme.primaryContainer,
        child: Icon(
          cancelada ? Icons.block : Icons.receipt,
          color: cancelada ? Colors.grey[600] : Theme.of(context).colorScheme.primary,
        ),
      ),
      title: Text(
        venda.cliente.nome,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          decoration: cancelada ? TextDecoration.lineThrough : null,
          color: cancelada ? Colors.grey[600] : null,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(timeFormat.format(venda.dataVenda)),
          Text('${venda.itens.length} itens • ${venda.metodoPagamento}'),
          if (cancelada)
            const Text('CANCELADA', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 12))
          else if (venda.emAndamento)
            Text(
              StatusPedido.rotulo(venda.status).toUpperCase(),
              style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12),
            ),
        ],
      ),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            format.format(venda.valorTotal),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              decoration: cancelada ? TextDecoration.lineThrough : null,
              color: cancelada ? Colors.grey[600] : null,
            ),
          ),
          Text(
            (venda.idVenda ?? '').length >= 6
                ? venda.idVenda!.substring(0, 6)
                : (venda.idVenda ?? ''),
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VendaDetalhesScreen(venda: venda),
        ),
      ),
    );
  }

  void _mostrarFiltros(BuildContext context, List<Venda> todasVendas) {
    final metodos = _metodosPagamentoDisponiveis(todasVendas);
    DateTimeRange? periodoTemp = _filtroPeriodo;
    String? pagamentoTemp = _filtroPagamento;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Filtrar Vendas',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  const Text('Período', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Todos'),
                        selected: periodoTemp == null,
                        onSelected: (_) => setModalState(() => periodoTemp = null),
                      ),
                      ChoiceChip(
                        label: const Text('Hoje'),
                        selected: false,
                        onSelected: (_) {
                          final hoje = DateTime.now();
                          setModalState(() => periodoTemp = DateTimeRange(
                                start: DateTime(hoje.year, hoje.month, hoje.day),
                                end: DateTime(hoje.year, hoje.month, hoje.day),
                              ));
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Últimos 7 dias'),
                        selected: false,
                        onSelected: (_) {
                          final hoje = DateTime.now();
                          setModalState(() => periodoTemp = DateTimeRange(
                                start: DateTime(hoje.year, hoje.month, hoje.day)
                                    .subtract(const Duration(days: 6)),
                                end: DateTime(hoje.year, hoje.month, hoje.day),
                              ));
                        },
                      ),
                      ChoiceChip(
                        label: const Text('Este mês'),
                        selected: false,
                        onSelected: (_) {
                          final hoje = DateTime.now();
                          setModalState(() => periodoTemp = DateTimeRange(
                                start: DateTime(hoje.year, hoje.month, 1),
                                end: DateTime(hoje.year, hoje.month, hoje.day),
                              ));
                        },
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.date_range, size: 18),
                        label: Text(periodoTemp == null
                            ? 'Escolher período...'
                            : '${DateFormat('dd/MM').format(periodoTemp!.start)} - ${DateFormat('dd/MM').format(periodoTemp!.end)}'),
                        onPressed: () async {
                          final escolhido = await showDateRangePicker(
                            context: context,
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now(),
                            initialDateRange: periodoTemp,
                          );
                          if (escolhido != null) {
                            setModalState(() => periodoTemp = escolhido);
                          }
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Forma de pagamento', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Todas'),
                        selected: pagamentoTemp == null,
                        onSelected: (_) => setModalState(() => pagamentoTemp = null),
                      ),
                      ...metodos.map((metodo) => ChoiceChip(
                            label: Text(metodo),
                            selected: pagamentoTemp == metodo,
                            onSelected: (_) => setModalState(() => pagamentoTemp = metodo),
                          )),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            setModalState(() {
                              periodoTemp = null;
                              pagamentoTemp = null;
                            });
                          },
                          child: const Text('Limpar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _filtroPeriodo = periodoTemp;
                              _filtroPagamento = pagamentoTemp;
                            });
                            Navigator.pop(context);
                          },
                          child: const Text('Aplicar Filtros'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
