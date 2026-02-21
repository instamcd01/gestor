import 'package:flutter/material.dart';
import '../models/cliente.dart';
import '../models/produto.dart';
import 'conclusao_venda_screen.dart';

class PagamentoLinkScreen extends StatefulWidget {
  final double valorTotal;
  final List<Map<String, dynamic>> carrinho;
  final String metodoPagamento;
  final Cliente cliente;
  final double desconto;
  final double valorEntrega;
  final String entregaSelecionada;
  final double saldoUsado;

  PagamentoLinkScreen({
    required this.valorTotal,
    required this.carrinho,
    required this.metodoPagamento,
    required this.cliente,
    required this.desconto,
    required this.valorEntrega,
    required this.entregaSelecionada,
    this.saldoUsado = 0.0,
  });

  @override
  _PagamentoLinkScreenState createState() => _PagamentoLinkScreenState();
}

class _PagamentoLinkScreenState extends State<PagamentoLinkScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Link de Pagamento')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Cliente: ${widget.cliente.nome}', style: TextStyle(fontSize: 18)),
            SizedBox(height: 10),
            Text('Valor a pagar: R\$ ${widget.valorTotal.toStringAsFixed(2)}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            SizedBox(height: 20),
            Text('Resumo da Compra:', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ...widget.carrinho.map((item) {
              final produto = item['produto'] as Produto;
              return Text('${item['quantidade']} x ${produto.nome} - R\$ ${produto.preco}');
            }).toList(),
            SizedBox(height: 20),
            Text('Saldo utilizado: R\$ ${widget.saldoUsado.toStringAsFixed(2)}', style: TextStyle(color: Colors.green)),
            SizedBox(height: 20),
            Center(
              child: ElevatedButton(
                onPressed: () {
                  // Aqui você pode gerar o link real de pagamento
                  // Para teste, já direcionamos para conclusão
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ConclusaoVendaScreen(
                        valorTotal: widget.valorTotal,
                        carrinho: widget.carrinho,
                        cliente: widget.cliente,
                        metodoPagamento: widget.metodoPagamento,
                        desconto: widget.desconto,
                        valorEntrega: widget.valorEntrega,
                        entregaSelecionada: widget.entregaSelecionada,
                        saldoUsado: widget.saldoUsado,
                      ),
                    ),
                  );
                },
                child: Text('Gerar Link e Confirmar Pagamento'),
                style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 50)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
