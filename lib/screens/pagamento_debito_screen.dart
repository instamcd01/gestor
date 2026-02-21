// pagamento_cartao_debito_screen.dart
import 'package:flutter/material.dart';
import '../models/cliente.dart';
import 'conclusao_venda_screen.dart';

class PagamentoCartaoDebitoScreen extends StatefulWidget {
  final double valorTotal;
  final List<Map<String, dynamic>> carrinho;
  final String? idCliente;
  final String metodoPagamento;
  final Cliente cliente;
  final double desconto;
  final double valorEntrega;
  final String entregaSelecionada;
  final double saldoUsado;

  PagamentoCartaoDebitoScreen({
    required this.valorTotal,
    required this.carrinho,
    this.idCliente,
    required this.metodoPagamento,
    required this.cliente,
    required this.desconto,
    required this.valorEntrega,
    required this.entregaSelecionada,
    required this.saldoUsado,

  });

  @override
  _PagamentoCartaoDebitoScreenState createState() =>
      _PagamentoCartaoDebitoScreenState();
}

class _PagamentoCartaoDebitoScreenState
    extends State<PagamentoCartaoDebitoScreen> {

  void concluirPagamento() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConclusaoVendaScreen(
          valorTotal: widget.valorTotal,
          carrinho: widget.carrinho,
          idCliente: widget.idCliente,
          metodoPagamento: widget.metodoPagamento,
          cliente: widget.cliente,
          desconto: widget.desconto,
          valorEntrega: widget.valorEntrega,          // ⬅️ Novo
          entregaSelecionada: widget.entregaSelecionada,
          saldoUsado: widget.saldoUsado,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Pagamento - ${widget.metodoPagamento}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              'Valor Total: R\$ ${widget.valorTotal.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.black,
              ),
            ),
            SizedBox(height: 30),
            Text(
              'Pagamento via Cartão de Débito será processado automaticamente.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey[700]),
            ),
            SizedBox(height: 50),
            ElevatedButton(
              onPressed: concluirPagamento,
              child: Text('Concluir'),
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
