//
// import 'package:flutter/material.dart';
// import 'package:provider/provider.dart';
//
// import '../providers/historico_vendas_provider.dart';
// import '../models/venda.dart';
//
// class HistoricoVendasScreen extends StatelessWidget {
//   @override
//   Widget build(BuildContext context) {
//     final historicoVendasProvider = Provider.of<HistoricoVendasProvider>(context);
//     final vendas = historicoVendasProvider.vendas;
//
//     // Função para agrupar as vendas por data
//     Map<String, List<Venda>> agrupadasPorData() {
//       Map<String, List<Venda>> agrupadas = {};
//       for (var venda in vendas) {
//         final dataVenda = venda.dataVenda; // A data de cada venda (deve estar no formato DateTime ou String)
//         final dataString = dataVenda.toString().split(' ')[0]; // Pega a data no formato "YYYY-MM-DD"
//         if (!agrupadas.containsKey(dataString)) {
//           agrupadas[dataString] = [];
//         }
//         agrupadas[dataString]!.add(venda);
//       }
//       return agrupadas;
//     }
//
//     // Função para calcular o resumo do mês atual
//     double calcularValorTotalMesAtual() {
//       double valorTotal = 0.0;
//       DateTime hoje = DateTime.now();
//       for (var venda in vendas) {
//         if (venda.dataVenda.month == hoje.month && venda.dataVenda.year == hoje.year) {
//           valorTotal += venda.valorTotal;
//         }
//       }
//       return valorTotal;
//     }
//
//     int calcularQuantidadeVendasMesAtual() {
//       int quantidadeVendas = 0;
//       DateTime hoje = DateTime.now();
//       for (var venda in vendas) {
//         if (venda.dataVenda.month == hoje.month && venda.dataVenda.year == hoje.year) {
//           quantidadeVendas++;
//         }
//       }
//       return quantidadeVendas;
//     }
//
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('Histórico de Vendas'),
//         actions: [
//           IconButton(
//             icon: Icon(Icons.import_export),
//             onPressed: () {
//               // Lógica para exportar relatório
//             },
//           ),
//           IconButton(
//             icon: Icon(Icons.filter_list),
//             onPressed: () {
//               // Lógica para filtro
//             },
//           ),
//         ],
//       ),
//       body: Column(
//         children: [
//           Padding(
//             padding: const EdgeInsets.all(8.0),
//             child: TextField(
//               decoration: InputDecoration(
//                 hintText: 'Pesquisar por item, cliente, valor ou ID da venda...',
//                 prefixIcon: Icon(Icons.search),
//                 border: OutlineInputBorder(
//                   borderRadius: BorderRadius.circular(8.0),
//                 ),
//               ),
//             ),
//           ),
//           Expanded(
//             child: vendas.isEmpty
//                 ? Center(
//               child: Text(
//                 'Nenhuma venda realizada.',
//                 style: TextStyle(fontSize: 18, color: Colors.grey),
//               ),
//             )
//                 : ListView.builder(
//               itemCount: agrupadasPorData().keys.length,
//               itemBuilder: (context, index) {
//                 final data = agrupadasPorData().keys.toList()[index];
//                 final vendasDoDia = agrupadasPorData()[data]!;
//                 double valorTotalDia = 0.0;
//                 int quantidadeVendasDia = 0;
//
//                 // Calculando o total de vendas e quantidade de vendas do dia
//                 for (var venda in vendasDoDia) {
//                   valorTotalDia += venda.valorTotal;
//                   quantidadeVendasDia++;
//                 }
//
//                 return Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Padding(
//                       padding: const EdgeInsets.all(8.0),
//                       child: Text(
//                         'Data: $data',
//                         style: TextStyle(
//                           fontSize: 18,
//                           fontWeight: FontWeight.bold,
//                         ),
//                       ),
//                     ),
//                     Column(
//                       children: vendasDoDia.map((venda) {
//                         return ListTile(
//                           title: Text('Cliente: ${venda.cliente.nome}'),
//                           subtitle: Text(
//                             'Valor: R\$ ${venda.valorTotal.toStringAsFixed(2)} - Horário: ${venda.dataVenda.toString().split(' ')[1]}',
//                           ),
//                           trailing: Text('ID: ${venda.id}'),
//                           onTap: () {
//                             // Exibir mais detalhes ou navegação para outra tela
//                           },
//                         );
//                       }).toList(),
//                     ),
//                     Padding(
//                       padding: const EdgeInsets.all(8.0),
//                       child: Row(
//                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                         children: [
//                           Text(
//                             'Quantidade de Vendas: $quantidadeVendasDia',
//                             style: TextStyle(
//                               fontWeight: FontWeight.bold,
//                             ),
//                           ),
//                           Text(
//                             'Valor Total: R\$ ${valorTotalDia.toStringAsFixed(2)}',
//                             style: TextStyle(
//                               fontWeight: FontWeight.bold,
//                             ),
//                           ),
//                         ],
//                       ),
//                     ),
//                     Divider(),
//                   ],
//                 );
//               },
//             ),
//           ),
//           // Resumo do mês atual
//           Padding(
//             padding: const EdgeInsets.all(8.0),
//             child: Container(
//               padding: EdgeInsets.all(12.0),
//               decoration: BoxDecoration(
//                 border: Border.all(color: Colors.grey),
//                 borderRadius: BorderRadius.circular(8.0),
//               ),
//               child: Column(
//                 children: [
//                   Text(
//                     'Resumo do Mês Atual',
//                     style: TextStyle(
//                       fontSize: 18,
//                       fontWeight: FontWeight.bold,
//                     ),
//                   ),
//                   SizedBox(height: 8.0),
//                   Text(
//                     'Quantidade de Vendas: ${calcularQuantidadeVendasMesAtual()}',
//                     style: TextStyle(fontSize: 16),
//                   ),
//                   SizedBox(height: 8.0),
//                   Text(
//                     'Valor Total: R\$ ${calcularValorTotalMesAtual().toStringAsFixed(2)}',
//                     style: TextStyle(fontSize: 16),
//                   ),
//                 ],
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }


import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/historico_vendas_provider.dart';
import '../models/venda.dart';
import 'venda_detalhes_screen.dart'; // Importa a tela de detalhes da venda

class HistoricoVendasScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final historicoVendasProvider = Provider.of<HistoricoVendasProvider>(context);
    final vendas = historicoVendasProvider.vendas;
    print(vendas);
    // Função para agrupar as vendas por data
    Map<String, List<Venda>> agrupadasPorData() {
      Map<String, List<Venda>> agrupadas = {};
      for (var venda in vendas) {
        final dataVenda = venda.dataVenda; // A data de cada venda (deve estar no formato DateTime ou String)
        final dataString = dataVenda.toString().split(' ')[0]; // Pega a data no formato "YYYY-MM-DD"
        if (!agrupadas.containsKey(dataString)) {
          agrupadas[dataString] = [];
        }
        agrupadas[dataString]!.add(venda);
      }
      return agrupadas;
    }

    // Função para calcular o resumo do mês atual
    double calcularValorTotalMesAtual() {
      double valorTotal = 0.0;
      DateTime hoje = DateTime.now();
      for (var venda in vendas) {
        if (venda.dataVenda.month == hoje.month && venda.dataVenda.year == hoje.year) {
          valorTotal += venda.valorTotal;
        }
      }
      return valorTotal;
    }

    int calcularQuantidadeVendasMesAtual() {
      int quantidadeVendas = 0;
      DateTime hoje = DateTime.now();
      for (var venda in vendas) {
        if (venda.dataVenda.month == hoje.month && venda.dataVenda.year == hoje.year) {
          quantidadeVendas++;
        }
      }
      return quantidadeVendas;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Histórico de Vendas'),
        actions: [
          IconButton(
            icon: Icon(Icons.import_export),
            onPressed: () {
              // Lógica para exportar relatório
            },
          ),
          IconButton(
            icon: Icon(Icons.filter_list),
            onPressed: () {
              // Lógica para filtro
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Pesquisar por item, cliente, valor ou ID da venda...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
            ),
          ),
          Expanded(
            child: vendas.isEmpty
                ? Center(
              child: Text(
                'Nenhuma venda realizada.',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
            )
                : ListView.builder(
              itemCount: agrupadasPorData().keys.length,
              itemBuilder: (context, index) {
                final data = agrupadasPorData().keys.toList()[index];
                final vendasDoDia = agrupadasPorData()[data]!;
                double valorTotalDia = 0.0;
                int quantidadeVendasDia = 0;

                // Calculando o total de vendas e quantidade de vendas do dia
                for (var venda in vendasDoDia) {
                  valorTotalDia += venda.valorTotal;
                  quantidadeVendasDia++;
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Text(
                        'Data: $data',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Column(
                      children: vendasDoDia.map((venda) {
                        return ListTile(
                          title: Text('Cliente: ${venda.cliente.nome}'),
                          subtitle: Text(
                            'Valor: R\$ ${venda.valorTotal.toStringAsFixed(2)} - Horário: ${venda.dataVenda.toString().split(' ')[1]}',
                          ),
                          trailing: Text('ID: ${venda.idVenda}'),
                          onTap: () {
                            print('Venda sendo passada: ${venda.idVenda}');
                            print('Itens: ${venda.itens.map((item) => item.produto.nome).toList()}');
                            print('Quantidade de itens: ${venda.itens.length}');// Navega para a tela de detalhes da venda
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => VendaDetalhesScreen(venda: venda),
                              ),
                            );
                          },
                        );
                      }).toList(),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Quantidade de Vendas: $quantidadeVendasDia',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Valor Total: R\$ ${valorTotalDia.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(),
                  ],
                );
              },
            ),
          ),
          // Resumo do mês atual
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Container(
              padding: EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
                borderRadius: BorderRadius.circular(8.0),
              ),
              child: Column(
                children: [
                  Text(
                    'Resumo do Mês Atual',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8.0),
                  Text(
                    'Quantidade de Vendas: ${calcularQuantidadeVendasMesAtual()}',
                    style: TextStyle(fontSize: 16),
                  ),
                  SizedBox(height: 8.0),
                  Text(
                    'Valor Total: R\$ ${calcularValorTotalMesAtual().toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 16),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
