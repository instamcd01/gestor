import 'package:flutter/material.dart';
import '../models/cliente.dart';
import '../models/zona_entrega.dart';
import '../widgets/itens_compra_card.dart';
import '../widgets/resumo_pagamento_card.dart';
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
  final ZonaEntrega? zonaEntrega;

  PagamentoLinkScreen({
    required this.valorTotal,
    required this.carrinho,
    required this.metodoPagamento,
    required this.cliente,
    required this.desconto,
    required this.valorEntrega,
    required this.entregaSelecionada,
    this.saldoUsado = 0.0,
    this.zonaEntrega,
  });

  @override
  _PagamentoLinkScreenState createState() => _PagamentoLinkScreenState();
}

class _PagamentoLinkScreenState extends State<PagamentoLinkScreen> {
  @override
  Widget build(BuildContext context) {
    final subtotal = ResumoPagamentoCard.calcularSubtotal(widget.carrinho);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text('Link de Pagamento')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.link, size: 64, color: colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              'Cliente: ${widget.cliente.nome}',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            ItensCompraCard(carrinho: widget.carrinho),
            const SizedBox(height: 16),
            ResumoPagamentoCard(
              subtotal: subtotal,
              desconto: widget.desconto,
              valorEntrega: widget.valorEntrega,
              saldoUsado: widget.saldoUsado,
              valorTotal: widget.valorTotal,
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
          ),
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
                    zonaEntrega: widget.zonaEntrega,
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 52)),
            child: Text('Gerar Link e Confirmar Pagamento'),
          ),
        ),
      ),
    );
  }
}
