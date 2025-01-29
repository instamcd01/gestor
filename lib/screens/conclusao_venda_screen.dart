// import 'package:flutter/material.dart';
// import 'package:pdf/widgets.dart' as pw;
// import 'package:pdf/pdf.dart';
// import 'package:path_provider/path_provider.dart';
// import 'dart:io';
//
// class ConclusaoVendaScreen extends StatelessWidget {
//   final double valorTotal;
//
//   ConclusaoVendaScreen({required this.valorTotal});
//
//   // Função para gerar o PDF do recibo
//   Future<void> gerarRecibo(BuildContext context) async {
//     final pdf = pw.Document();
//
//     // Adiciona uma página ao PDF
//     pdf.addPage(pw.Page(
//       build: (pw.Context context) {
//         return pw.Center(
//           child: pw.Column(
//             crossAxisAlignment: pw.CrossAxisAlignment.start,
//             children: [
//               pw.Text('Recibo de Venda',
//                   style: pw.TextStyle(
//                     fontSize: 24,
//                     fontWeight: pw.FontWeight.bold,
//                   )),
//               pw.SizedBox(height: 20),
//               pw.Text('Data: ${DateTime.now().toString()}'),
//               pw.SizedBox(height: 10),
//               pw.Text('Valor Total: R\$ ${valorTotal.toStringAsFixed(2)}'),
//               pw.SizedBox(height: 20),
//               pw.Text('Obrigado por sua compra!',
//                   style: pw.TextStyle(fontSize: 16)),
//             ],
//           ),
//         );
//       },
//     ));
//
//     // Obter o diretório de downloads no Android
//     final directory = await getExternalStorageDirectory();
//     final downloadDirectory = Directory('${directory!.path}/Download'); // Define o diretório de downloads
//     if (!await downloadDirectory.exists()) {
//       await downloadDirectory.create(recursive: true);
//     }
//
//     final file = File('${downloadDirectory.path}/recibo_venda.pdf');
//
//     // Salva o arquivo PDF no diretório de downloads
//     await file.writeAsBytes(await pdf.save());
//
//     // Exibe uma mensagem de sucesso
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(content: Text('Recibo baixado com sucesso!')),
//     );
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('Venda Concluída'),
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           crossAxisAlignment: CrossAxisAlignment.center,
//           children: [
//             Icon(
//               Icons.check_circle,
//               color: Colors.green,
//               size: 100,
//             ),
//             SizedBox(height: 20),
//             Text(
//               'Venda Concluída com Sucesso!',
//               style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
//             ),
//             SizedBox(height: 20),
//             Text(
//               'Valor Total: R\$ ${valorTotal.toStringAsFixed(2)}',
//               style: TextStyle(fontSize: 20),
//             ),
//             SizedBox(height: 30),
//             ElevatedButton.icon(
//               onPressed: () {
//                 // Chama a função de geração de PDF
//                 gerarRecibo(context);
//               },
//               icon: Icon(Icons.download),
//               label: Text('Baixar Recibo'),
//               style: ElevatedButton.styleFrom(
//                 minimumSize: Size(double.infinity, 50),
//                 textStyle: TextStyle(fontSize: 18),
//               ),
//             ),
//             SizedBox(height: 20),
//             ElevatedButton.icon(
//               onPressed: () {
//                 // Navegar para a tela de vendas
//                 Navigator.popUntil(
//                     context, (route) => route.isFirst); // Voltar para a tela inicial
//               },
//               icon: Icon(Icons.shopping_bag),
//               label: Text('Nova Venda'),
//               style: ElevatedButton.styleFrom(
//                 minimumSize: Size(double.infinity, 50),
//                 textStyle: TextStyle(fontSize: 18),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }


import 'package:flutter/material.dart';
import 'package:gestor/providers/cliente_provider.dart';
import 'package:provider/provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../models/cliente.dart';
import '../models/venda.dart';
import '../providers/historico_vendas_provider.dart';
import '../providers/vendas_provider.dart';

class ConclusaoVendaScreen extends StatelessWidget {
  final double valorTotal;
  final List<Map<String, dynamic>> carrinho;
  ConclusaoVendaScreen({required this.valorTotal,required this.carrinho,});

  // Função para gerar o PDF do recibo
  // Future<void> gerarRecibo(BuildContext context) async {
  //   final pdf = pw.Document();
  //
  //   // Adiciona uma página ao PDF
  //   pdf.addPage(pw.Page(
  //     build: (pw.Context context) {
  //       return pw.Center(
  //         child: pw.Column(
  //           crossAxisAlignment: pw.CrossAxisAlignment.start,
  //           children: [
  //             pw.Text('Recibo de Venda',
  //                 style: pw.TextStyle(
  //                   fontSize: 24,
  //                   fontWeight: pw.FontWeight.bold,
  //                 )),
  //             pw.SizedBox(height: 20),
  //             pw.Text('Data: ${DateTime.now().toString()}'),
  //             pw.SizedBox(height: 10),
  //             pw.Text('Valor Total: R\$ ${valorTotal.toStringAsFixed(2)}'),
  //             pw.SizedBox(height: 20),
  //             pw.Text('Itens Vendidos:', style: pw.TextStyle(fontSize: 18)),
  //             pw.SizedBox(height: 10),
  //             ...carrinho.map((item) => pw.Text(
  //                 '- ${item.produto.nome} (Qtd: ${item.quantidade}) - R\$ ${item.precoTotal.toStringAsFixed(2)}')),
  //             pw.SizedBox(height: 20),
  //             pw.Text('Obrigado por sua compra!',
  //                 style: pw.TextStyle(fontSize: 16)),
  //           ],
  //         ),
  //       );
  //     },
  //   ));
  //
  //   // Obter o diretório de downloads no Android
  //   final directory = await getExternalStorageDirectory();
  //   final downloadDirectory = Directory('${directory!.path}/Download');
  //   if (!await downloadDirectory.exists()) {
  //     await downloadDirectory.create(recursive: true);
  //   }
  //
  //   final file = File('${downloadDirectory.path}/recibo_venda.pdf');
  //
  //   // Salva o arquivo PDF no diretório de downloads
  //   await file.writeAsBytes(await pdf.save());
  //
  //   // Exibe uma mensagem de sucesso
  //   ScaffoldMessenger.of(context).showSnackBar(
  //     SnackBar(content: Text('Recibo baixado com sucesso!')),
  //   );
  // }

  // Função para adicionar a venda ao histórico (executada em 2º plano)
  // void adicionarVendaAoHistorico(BuildContext context) async {
  //   final historicoVendasProvider =
  //   Provider.of<HistoricoVendasProvider>(context, listen: false);
  //
  //   // Acesse o cliente selecionado a partir do provider ou da forma que estiver sendo mantido
  //   Cliente? clienteSelecionado = Provider.of<ClientProvider>(context, listen: false).clienteSelecionado;
  //
  //   // Criação da venda com base no cliente selecionado
  //   historicoVendasProvider.adicionarVenda(
  //     Venda(
  //       cliente: clienteSelecionado, // Cliente obtido do provider
  //       metodoPagamento: 'Cartão de Débito', // Substitua conforme necessário
  //       valorTotal: valorTotal,
  //       itens: [], // Adicione itens se necessário
  //       id: DateTime.now().millisecondsSinceEpoch.toString(),
  //       dataVenda: DateTime.now(),
  //     ),
  //   );
  // }
//   void adicionarVendaAoHistorico(BuildContext context) async {
//     final historicoVendasProvider =
//     Provider.of<HistoricoVendasProvider>(context, listen: false);
//     final vendasProvider = Provider.of<VendasProvider>(context, listen: false);
//
//     // Acesse o cliente selecionado a partir do provider
//     Cliente? clienteSelecionado =
//         Provider.of<ClientProvider>(context, listen: false).clienteSelecionado;
//
//     if (clienteSelecionado == null) {
//       // Exibe uma mensagem de erro caso o cliente não tenha sido selecionado
//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text('Erro: Nenhum cliente selecionado!')),
//       );
//       return; // Retorna sem adicionar a venda
//     }
// // Converte o carrinho para uma lista de ItemVenda
//     List<ItemVenda> itensVenda = carrinho.map((item) {
//
//       return ItemVenda(
//         produto: item['produto'].nome, // Acessando o nome do produto
//         quantidade: item['quantidade'], // Acessando a quantidade
//         precoTotal: item['produto'].preco * item['quantidade'], // Acessando o preço total
//       );
//     }).toList();
//     // Criação da venda com base no cliente selecionado
//     historicoVendasProvider.adicionarVenda(
//       Venda(
//         cliente: clienteSelecionado, // Cliente obtido do provider
//         metodoPagamento: 'Cartão de Débito', // Substitua conforme necessário
//         valorTotal: valorTotal,
//         itens: List.from(itensVenda), // Adicione itens se necessário
//         idVenda: DateTime.now().millisecondsSinceEpoch.toString(),
//         dataVenda: DateTime.now(),
//         // custoTotal: custoTotal,
//       ),
//     );
//   }

  // Função para adicionar a venda ao histórico (executada em 2º plano)
  void adicionarVendaAoHistorico(BuildContext context) async {
    final historicoVendasProvider =
    Provider.of<HistoricoVendasProvider>(context, listen: false);
    final vendasProvider = Provider.of<VendasProvider>(context, listen: false);

    // Acesse o cliente selecionado a partir do provider
    Cliente? clienteSelecionado =
        Provider.of<ClientProvider>(context, listen: false).clienteSelecionado;

    if (clienteSelecionado == null) {
      // Exibe uma mensagem de erro caso o cliente não tenha sido selecionado
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro: Nenhum cliente selecionado!')),
      );
      return; // Retorna sem adicionar a venda
    }

    // Converte o carrinho para uma lista de ItemVenda
    List<ItemVenda> itensVenda = carrinho.map((item) {
      return ItemVenda(
        produto: item['produto'].nome, // Acessando o nome do produto
        quantidade: item['quantidade'], // Acessando a quantidade
        precoTotal: item['produto'].preco * item['quantidade'], // Acessando o preço total
      );
    }).toList();

    // Criação da venda com base no cliente selecionado
    historicoVendasProvider.adicionarVenda(
      Venda(
        cliente: clienteSelecionado, // Cliente obtido do provider
        metodoPagamento: 'Cartão de Débito', // Substitua conforme necessário
        valorTotal: valorTotal,
        itens: List.from(itensVenda), // Adicione itens se necessário
        idVenda: DateTime.now().millisecondsSinceEpoch.toString(),
        dataVenda: DateTime.now(),
        // custoTotal: custoTotal,
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    // Chama a função para adicionar a venda ao histórico assim que a tela for exibida
    adicionarVendaAoHistorico(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Venda Concluída'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle,
              color: Colors.green,
              size: 100,
            ),
            SizedBox(height: 20),
            Text(
              'Venda Concluída com Sucesso!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            Text(
              'Valor Total: R\$ ${valorTotal.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 20),
            ),
            SizedBox(height: 30),
            ElevatedButton.icon(
              onPressed: () {
                // Chama a função de geração de PDF
                // gerarRecibo(context);
              },
              icon: Icon(Icons.download),
              label: Text('Baixar Recibo'),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 50),
                textStyle: TextStyle(fontSize: 18),
              ),
            ),
            SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () {
                // Navigator.pushReplacementNamed(context, '/historico_vendas');
                // Navegar para a tela de vendas
                Navigator.popUntil(
                    context, (route) => route.isFirst); // Voltar para a tela inicial
              },
              icon: Icon(Icons.shopping_bag),
              label: Text('Nova Venda'),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 50),
                textStyle: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
