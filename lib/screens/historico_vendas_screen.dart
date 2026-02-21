// import 'package:flutter/material.dart';
// import 'package:intl/intl.dart';
// import 'package:provider/provider.dart';
// import '../providers/historico_vendas_provider.dart';
// import '../models/venda.dart';
// import 'venda_detalhes_screen.dart';
//
// class HistoricoVendasScreen extends StatefulWidget {
//   @override
//   _HistoricoVendasScreenState createState() => _HistoricoVendasScreenState();
// }
//
// class _HistoricoVendasScreenState extends State<HistoricoVendasScreen> {
//   final _searchController = TextEditingController();
//   bool _carregando = true;
//
//   @override
//   void initState() {
//     super.initState();
//    _carregarVendas();
//   }
//
//   Future<void> _carregarVendas() async {
//     try {
//       await Provider.of<HistoricoVendasProvider>(context, listen: false)
//           .carregarVendasDoFirestore();
//     } finally {
//       if (mounted) {
//         setState(() => _carregando = false);
//       }
//     }
//   }
//
//   @override
//   void dispose() {
//     _searchController.dispose();
//     super.dispose();
//   }
//
//   Map<String, List<Venda>> _agruparVendasPorData(List<Venda> vendas) {
//     final Map<String, List<Venda>> agrupadas = {};
//     final dateFormat = DateFormat('dd/MM/yyyy');
//
//     for (final venda in vendas) {
//       final dataString = dateFormat.format(venda.dataVenda);
//       agrupadas.putIfAbsent(dataString, () => []).add(venda);
//     }
//
//     // Ordenar as datas da mais recente para a mais antiga
//     final sortedKeys = agrupadas.keys.toList()
//       ..sort((a, b) => dateFormat.parse(b).compareTo(dateFormat.parse(a)));
//
//     return Map.fromEntries(
//       sortedKeys.map((key) => MapEntry(key, agrupadas[key]!)),
//     );
//   }
//
//   Map<String, dynamic> _calcularTotais(List<Venda> vendas) {
//     final hoje = DateTime.now();
//     double valorTotalMes = 0.0;
//     int qtdVendasMes = 0;
//
//     for (final venda in vendas) {
//       if (venda.dataVenda.month == hoje.month &&
//           venda.dataVenda.year == hoje.year) {
//         valorTotalMes += venda.valorTotal;
//         qtdVendasMes++;
//       }
//     }
//
//     return {
//       'valorTotalMes': valorTotalMes,
//       'qtdVendasMes': qtdVendasMes,
//     };
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final historicoProvider = Provider.of<HistoricoVendasProvider>(context);
//     final vendas = historicoProvider.vendas;
//     final vendasAgrupadas = _agruparVendasPorData(vendas);
//     final totaisMes = _calcularTotais(vendas);
//     final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
//     final carregando = _carregando;
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Histórico de Vendas'),
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.refresh),
//             onPressed: () {
//               setState(() => _carregando = true);
//               _carregarVendas();
//             },
//           ),
//           IconButton(
//             icon: const Icon(Icons.filter_list),
//             onPressed: () => _mostrarFiltros(context),
//           ),
//         ],
//       ),
//       body: Column(
//         children: [
//           Padding(
//             padding: const EdgeInsets.all(12),
//             child: TextField(
//               controller: _searchController,
//               decoration: InputDecoration(
//                 hintText: 'Pesquisar vendas...',
//                 prefixIcon: const Icon(Icons.search),
//                 border: OutlineInputBorder(
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//                 suffixIcon: IconButton(
//                   icon: const Icon(Icons.clear),
//                   onPressed: () {
//                     _searchController.clear();
//                     // Implementar limpeza da busca
//                   },
//                 ),
//               ),
//               onChanged: (value) {
//                 // Implementar busca em tempo real
//               },
//             ),
//           ),
//           if (_carregando)
//             const LinearProgressIndicator()
//           else if (vendas.isEmpty)
//             Expanded(
//               child: Center(
//                 child: Column(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
//                     const SizedBox(height: 16),
//                     Text(
//                       'Nenhuma venda registrada',
//                       style: TextStyle(
//                         fontSize: 18,
//                         color: Colors.grey[600],
//                       ),
//                     ),
//                     TextButton(
//                       onPressed: _carregarVendas,
//                       child: const Text('Recarregar'),
//                     ),
//                   ],
//                 ),
//               ),
//             )
//           else
//             Expanded(
//               child: RefreshIndicator(
//                 onRefresh: _carregarVendas,
//                 child: ListView(
//                   children: [
//                     _buildResumoMensal(totaisMes, currencyFormat),
//                     ...vendasAgrupadas.entries.map((entry) {
//                       final valorTotalDia = entry.value.fold(
//                           0.0, (sum, venda) => sum + venda.valorTotal);
//
//                       return _buildDiaVendas(
//                         context,
//                         entry.key,
//                         entry.value,
//                         valorTotalDia,
//                         currencyFormat,
//                       );
//                     }),
//                   ],
//                 ),
//               ),
//             ),
//         ],
//       ),
//     );
//   }
//
//   Widget _buildResumoMensal(Map<String, dynamic> totais, NumberFormat format) {
//     return Card(
//       margin: const EdgeInsets.all(12),
//       child: Padding(
//         padding: const EdgeInsets.all(16),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             const Text(
//               'RESUMO DO MÊS',
//               style: TextStyle(
//                 fontSize: 16,
//                 fontWeight: FontWeight.bold,
//                 color: Colors.blue,
//               ),
//             ),
//             const SizedBox(height: 12),
//             Row(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 const Text('Total de vendas:'),
//                 Text(
//                   totais['qtdVendasMes'].toString(),
//                   style: const TextStyle(fontWeight: FontWeight.bold),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 8),
//             Row(
//               mainAxisAlignment: MainAxisAlignment.spaceBetween,
//               children: [
//                 const Text('Valor total:'),
//                 Text(
//                   format.format(totais['valorTotalMes']),
//                   style: const TextStyle(
//                     fontWeight: FontWeight.bold,
//                     fontSize: 16,
//                   ),
//                 ),
//               ],
//             ),
//           ],
//         ),
//       ),
//     );
//   }
//
//   Widget _buildDiaVendas(
//       BuildContext context,
//       String data,
//       List<Venda> vendasDoDia,
//       double valorTotalDia,
//       NumberFormat format,
//       ) {
//     return Card(
//       margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
//       child: ExpansionTile(
//         title: Text(
//           DateFormat('EEEE, dd/MM/yyyy').format(DateFormat('dd/MM/yyyy').parse(data)),
//           style: TextStyle(fontWeight: FontWeight.bold),
//         ),
//         subtitle: Text(
//           '${vendasDoDia.length} venda${vendasDoDia.length > 1 ? 's' : ''} • Total: ${format.format(valorTotalDia)}',
//         ),
//         children: vendasDoDia.map((venda) => _buildItemVenda(context, venda, format)).toList(),
//       ),
//     );
//   }
//
//   Widget _buildItemVenda(BuildContext context, Venda venda, NumberFormat format) {
//     final timeFormat = DateFormat('HH:mm');
//
//     return ListTile(
//       contentPadding: const EdgeInsets.symmetric(horizontal: 16),
//       leading: CircleAvatar(
//         backgroundColor: Colors.blue[50],
//         child: Icon(Icons.receipt, color: Colors.blue),
//       ),
//       title: Text(
//         venda.cliente.nome,
//         style: const TextStyle(fontWeight: FontWeight.bold),
//       ),
//       subtitle: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Text(timeFormat.format(venda.dataVenda)),
//           Text('${venda.itens.length} itens • ${venda.metodoPagamento}'),
//         ],
//       ),
//       trailing: Column(
//         mainAxisSize: MainAxisSize.min,
//         crossAxisAlignment: CrossAxisAlignment.end,
//         children: [
//           Text(
//             format.format(venda.valorTotal),
//             style: const TextStyle(
//               fontWeight: FontWeight.bold,
//               fontSize: 16,
//             ),
//           ),
//           Text(
//             venda.idVenda.substring(0, 6),
//             style: TextStyle(color: Colors.grey[600], fontSize: 12),
//           ),
//         ],
//       ),
//       onTap: () => Navigator.push(
//         context,
//         MaterialPageRoute(
//           builder: (context) => VendaDetalhesScreen(venda: venda),
//         ),
//       ),
//     );
//   }
//
//   void _mostrarFiltros(BuildContext context) {
//     showModalBottomSheet(
//       context: context,
//       builder: (context) {
//         return Container(
//           padding: const EdgeInsets.all(16),
//           child: Column(
//             mainAxisSize: MainAxisSize.min,
//             children: [
//               const Text(
//                 'Filtrar Vendas',
//                 style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
//               ),
//               const SizedBox(height: 16),
//               // Implementar filtros aqui
//               ElevatedButton(
//                 onPressed: () => Navigator.pop(context),
//                 child: const Text('Aplicar Filtros'),
//               ),
//             ],
//           ),
//         );
//       },
//     );
//   }
// }


import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/historico_vendas_provider.dart';
import '../models/venda.dart';
import 'venda_detalhes_screen.dart';

class HistoricoVendasScreen extends StatefulWidget {
  @override
  _HistoricoVendasScreenState createState() => _HistoricoVendasScreenState();
}

class _HistoricoVendasScreenState extends State<HistoricoVendasScreen> {
  final _searchController = TextEditingController();
  bool _carregando = true;
  List<Venda> _vendasFiltradas = [];

  @override
  void initState() {
    super.initState();
    _carregarVendas();
    _searchController.addListener(_filtrarVendas);
  }

  Future<void> _carregarVendas() async {
    try {
      await Provider.of<HistoricoVendasProvider>(context, listen: false)
          .carregarVendasDoFirestore();
      _filtrarVendas();
    } finally {
      if (mounted) {
        setState(() => _carregando = false);
      }
    }
  }

  void _filtrarVendas() {
    final historicoProvider = Provider.of<HistoricoVendasProvider>(context, listen: false);
    final termo = _searchController.text.toLowerCase();

    setState(() {
      if (termo.isEmpty) {
        _vendasFiltradas = historicoProvider.vendas;
      } else {
        _vendasFiltradas = historicoProvider.vendas.where((venda) {
          final nome = venda.cliente.nome.toLowerCase();
          final id = venda.idVenda.toLowerCase();
          return nome.contains(termo) || id.contains(termo);
        }).toList();
      }
    });
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
      if (venda.dataVenda.month == hoje.month &&
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
    final vendas = _vendasFiltradas;
    final vendasAgrupadas = _agruparVendasPorData(vendas);
    final totaisMes = _calcularTotais(vendas);
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Histórico de Vendas'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _carregando = true);
              _carregarVendas();
            },
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () => _mostrarFiltros(context),
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _filtrarVendas();
                  },
                ),
              ),
            ),
          ),
          if (_carregando)
            const LinearProgressIndicator()
          else if (vendas.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'Nenhuma venda registrada',
                      style: TextStyle(fontSize: 18, color: Colors.grey[600]),
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
                    _buildResumoMensal(totaisMes, currencyFormat),
                    ...vendasAgrupadas.entries.map((entry) {
                      final valorTotalDia = entry.value.fold(
                          0.0, (sum, venda) => sum + venda.valorTotal);

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

  Widget _buildResumoMensal(Map<String, dynamic> totais, NumberFormat format) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'RESUMO DO MÊS',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.blue,
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
                Text(
                  format.format(totais['valorTotalMes']),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
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

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: Colors.blue[50],
        child: const Icon(Icons.receipt, color: Colors.blue),
      ),
      title: Text(
        venda.cliente.nome,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(timeFormat.format(venda.dataVenda)),
          Text('${venda.itens.length} itens • ${venda.metodoPagamento}'),
        ],
      ),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            format.format(venda.valorTotal),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          Text(
            venda.idVenda.substring(0, 6),
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
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

  void _mostrarFiltros(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Filtrar Vendas',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              // Aqui você pode implementar filtros adicionais
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Aplicar Filtros'),
              ),
            ],
          ),
        );
      },
    );
  }
}
