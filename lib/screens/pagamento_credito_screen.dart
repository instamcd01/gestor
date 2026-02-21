// pagamento_cartao_credito_screen.dart
import 'package:flutter/material.dart';
import 'package:gestor/models/cliente.dart';
import 'conclusao_venda_screen.dart';

class PagamentoCartaoCreditoScreen extends StatelessWidget {
  final double valorTotal;
  final List<Map<String, dynamic>> carrinho;
  final String? idCliente;
  final String metodoPagamento;
  final Cliente cliente;
  final double desconto;
  final double valorEntrega;
  final String entregaSelecionada;
  final double saldoUsado;

  PagamentoCartaoCreditoScreen({
    required this.valorTotal,
    required this.carrinho,
    this.idCliente,
    required this.metodoPagamento,
    required this.cliente, required this.desconto,
    required this.valorEntrega,
    required this.entregaSelecionada,
    required this.saldoUsado,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Pagamento: Cartão de Crédito'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.credit_card, size: 100, color: Colors.blue),
            SizedBox(height: 30),
            Text(
              'Valor Total: R\$ ${valorTotal.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Pagamento via cartão de crédito será processado no valor exato.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18),
            ),
            SizedBox(height: 50),
            ElevatedButton(
              onPressed: () {
                // Navegar para a tela de conclusão da venda
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ConclusaoVendaScreen(
                      valorTotal: valorTotal,
                      carrinho: carrinho,
                      idCliente: idCliente,
                      metodoPagamento: metodoPagamento,
                      cliente: cliente,
                      desconto: desconto,
                      valorEntrega: valorEntrega,
                      entregaSelecionada: entregaSelecionada,
                      saldoUsado: saldoUsado,
                    ),
                  ),
                );
              },
              child: Text('Concluir Pagamento'),
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
