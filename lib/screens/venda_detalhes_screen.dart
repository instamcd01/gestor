import 'package:flutter/material.dart';
import '../models/venda.dart';

class VendaDetalhesScreen extends StatelessWidget {
  final Venda venda;


  VendaDetalhesScreen({required this.venda,  });

  @override
  Widget build(BuildContext context) {
    print('Venda recebida: ${venda.idVenda}');
    print('Itens da venda: ${venda.itens.map((item) => item.produto.nome).toList()}');
    print('Quantidade de itens: ${venda.itens.length}');

    return Scaffold(
      appBar: AppBar(
        title: Text('Venda - ${venda.cliente.nome ?? "Cliente Desconhecido"}'),
        actions: [
          IconButton(
            icon: Icon(Icons.receipt),
            onPressed: () {
              // Lógica para mostrar o recibo
              // Pode ser uma nova tela ou o download do PDF
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Resumo da venda
            Text(
              'Data: ${venda.dataVenda.toLocal()}',
              style: TextStyle(fontSize: 18),
            ),
            Text(
              'ID da Venda: ${venda.idVenda}',
              style: TextStyle(fontSize: 18),
            ),
            Text(
              'Forma de Pagamento: ${venda.metodoPagamento}',
              style: TextStyle(fontSize: 18),
            ),
            Text(
              'Valor Total: R\$ ${venda.valorTotal.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 18),
            ),
            Text(
              'Endereço: ${venda.cliente.endereco ?? "Não disponível"}',
              style: TextStyle(fontSize: 18),
            ),
            SizedBox(height: 20),

            // Detalhes dos itens da venda
            Text(
              'Itens:',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            // Expanded(
            //   child: ListView.builder(
            //     itemCount: venda.itens.length,
            //     itemBuilder: (context, index) {
            //       final itemVenda = venda.itens[index];
            //       print('Item ${index + 1}: ${itemVenda.produto.nome}, Quantidade: ${itemVenda.quantidade}, Valor Total: ${itemVenda.precoTotal}');
            //       return ListTile(
            //         title: Text('${itemVenda.produto.nome}'),
            //         subtitle: Text(
            //             'Quantidade: ${itemVenda.quantidade} | Valor: R\$ ${itemVenda.precoTotal.toStringAsFixed(2)}'),
            //       );
            //     },
            //   ),
            // ),
            // Detalhes adicionais
            // SizedBox(height: 20),
            // Text(
            //   'Lucro: R\$ ${venda.valorTotal - venda.custoTotal().toStringAsFixed(2)}',
            //   style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            // ),
            // Lista de produtos comprados
            Expanded(
              child: venda.itens.isNotEmpty
                  ? Center(
                child: Text(
                  'Nenhum item encontrado.',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              )
                  : ListView.builder(
                itemCount: venda.itens.length,
                itemBuilder: (context, index) {
                  final itemVenda = venda.itens[index];
                  return Card(
                    elevation: 2,
                    margin: EdgeInsets.symmetric(vertical: 5),
                    child: ListTile(
                      title: Text(itemVenda.produto.nome), // Ajuste para acessar o produto na estrutura do carrinho
                      subtitle: Text(
                        'Quantidade: ${itemVenda.quantidade} | Valor: R\$ ${(itemVenda.precoTotal * itemVenda.quantidade).toStringAsFixed(2)}',

                      ),
                    ),
                  );
                },
              ),
            ),
            SizedBox(height: 20),


            // Botões de ação
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton(
                  onPressed: () {
                    // Lógica para ver o recibo
                    // Aqui pode ser a navegação para outra tela ou a geração do PDF
                  },
                  child: Text('Ver Recibo'),
                ),
                ElevatedButton(
                  onPressed: () {
                    // Lógica para cancelar a venda
                  },
                  child: Text('Cancelar Venda'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
