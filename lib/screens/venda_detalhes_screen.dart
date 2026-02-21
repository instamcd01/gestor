// import 'package:flutter/material.dart';
// import '../models/venda.dart';
//
// class VendaDetalhesScreen extends StatelessWidget {
//   final Venda venda;
//
//   VendaDetalhesScreen({required this.venda});
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('Venda - ${venda.cliente.nome}'),
//         actions: [
//           IconButton(
//             icon: Icon(Icons.receipt),
//             onPressed: () {
//               // Lógica para mostrar o recibo ou gerar PDF
//             },
//           ),
//         ],
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Text('Data: ${venda.dataVenda.toLocal()}', style: TextStyle(fontSize: 18)),
//             Text('ID da Venda: ${venda.idVenda}', style: TextStyle(fontSize: 18)),
//             Text('Forma de Pagamento: ${venda.metodoPagamento}', style: TextStyle(fontSize: 18)),
//             Text('Valor Total: R\$ ${venda.valorTotal.toStringAsFixed(2)}', style: TextStyle(fontSize: 18)),
//             Text('Endereço: ${venda.cliente.endereco ?? "Não disponível"}', style: TextStyle(fontSize: 18)),
//             SizedBox(height: 20),
//
//             Text('Itens:', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
//
//             Expanded(
//               child: venda.itens.isEmpty
//                   ? Center(
//                 child: Text('Nenhum item encontrado.',
//                     style: TextStyle(fontSize: 16, color: Colors.grey)),
//               )
//                   : ListView.builder(
//                 itemCount: venda.itens.length,
//                 itemBuilder: (context, index) {
//                   final itemVenda = venda.itens[index];
//
//                   final nomeProduto = itemVenda.produto.nome;
//                   final quantidade = itemVenda.quantidade;
//
//                   // Se precoTotal vier zerado, calcula dinamicamente
//                   double precoTotal = itemVenda.precoTotal;
//                   if (precoTotal == 0) {
//                     precoTotal = (itemVenda.produto.preco ?? 0) * quantidade;
//                   }
//
//                   return Card(
//                     elevation: 2,
//                     margin: EdgeInsets.symmetric(vertical: 5),
//                     child: ListTile(
//                       title: Text(nomeProduto),
//                       subtitle: Text(
//                           'Quantidade: $quantidade | Valor: R\$ ${precoTotal.toStringAsFixed(2)}'),
//                     ),
//                   );
//                 },
//               ),
//             ),
//
//             SizedBox(height: 20),
//             Row(
//               mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//               children: [
//                 ElevatedButton(
//                   onPressed: () {
//                     // Ver recibo
//                   },
//                   child: Text('Ver Recibo'),
//                 ),
//                 ElevatedButton(
//                   onPressed: () {
//                     // Cancelar venda
//                   },
//                   child: Text('Cancelar Venda'),
//                 ),
//               ],
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

import 'package:flutter/material.dart';
import '../models/venda.dart';
import 'package:intl/intl.dart';

class VendaDetalhesScreen extends StatelessWidget {
  final Venda venda;

  VendaDetalhesScreen({required this.venda});

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Scaffold(
      appBar: AppBar(
        title: Text('Venda - ${venda.cliente.nome}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Data: ${DateFormat('dd/MM/yyyy HH:mm').format(venda.dataVenda)}', style: TextStyle(fontSize: 16)),
            Text('ID da Venda: ${venda.idVenda}', style: TextStyle(fontSize: 16)),
            Text('Forma de Pagamento: ${venda.metodoPagamento}', style: TextStyle(fontSize: 16)),

            if (venda.pagamentosDetalhados != null && venda.pagamentosDetalhados!.isNotEmpty) ...[
              SizedBox(height: 8),
              Text(
                'Pagamentos Detalhados:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 4),
              ...venda.pagamentosDetalhados!.entries.map((entry) {
                return Text(
                  '${entry.key}: ${currencyFormat.format(entry.value)}',
                  style: TextStyle(fontSize: 16),
                );
              }).toList(),
              SizedBox(height: 16),
            ],
            SizedBox(height: 8),
            Text('Subtotal: ${currencyFormat.format(venda.subtotal)}', style: TextStyle(fontSize: 16)),
            Text('Desconto: -${currencyFormat.format(venda.desconto)}', style: TextStyle(fontSize: 16, color: Colors.red)),
            Text('Saldo utilizado: -${currencyFormat.format(venda.saldoUsado)}', style: TextStyle(fontSize: 16, color: Colors.red)),
            Text('Entrega (${venda.entregaSelecionada}): +${currencyFormat.format(venda.valorEntrega)}', style: TextStyle(fontSize: 16, color: Colors.blue)),
            Text('Valor Total: ${currencyFormat.format(venda.valorTotal)}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text('Valor Pago: ${currencyFormat.format(venda.valorPago)}', style: TextStyle(fontSize: 16)),
            Text('Troco: ${currencyFormat.format(venda.troco)}', style: TextStyle(fontSize: 16)),
            SizedBox(height: 8),
            Text('Custo Total: ${currencyFormat.format(venda.custoTotal)}', style: TextStyle(fontSize: 16, color: Colors.orange)),
            Text('Lucro Total: ${currencyFormat.format(venda.lucroTotal)}', style: TextStyle(fontSize: 16, color: Colors.green)),
            SizedBox(height: 16),

            Text('Itens:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Expanded(
              child: ListView.builder(
                itemCount: venda.itens.length,
                itemBuilder: (context, index) {
                  final item = venda.itens[index];
                  return Card(
                    elevation: 2,
                    margin: EdgeInsets.symmetric(vertical: 5),
                    child: ListTile(
                      title: Text(item.produto.nome),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Quantidade: ${item.quantidade}'),
                          Text('Preço Unitário: ${currencyFormat.format(item.precoUnitario)}'),
                          Text('Custo Unitário: ${currencyFormat.format(item.custoUnitario)}'),
                          Text('Lucro Unitário: ${currencyFormat.format(item.lucroUnitario)}', style: TextStyle(color: Colors.green)),
                          Text('Total: ${currencyFormat.format(item.precoTotal)}'),
                          Text('Custo Total: ${currencyFormat.format(item.custoTotal)}'),
                          Text('Lucro Total: ${currencyFormat.format(item.lucroTotal)}', style: TextStyle(color: Colors.green)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (venda.observacao.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: Text('Observações: ${venda.observacao}', style: TextStyle(fontSize: 16, fontStyle: FontStyle.italic)),
              ),
          ],
        ),
      ),
    );
  }
}


