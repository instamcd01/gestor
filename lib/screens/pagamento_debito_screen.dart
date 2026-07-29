// pagamento_cartao_debito_screen.dart
import 'package:flutter/material.dart';
import '../models/cliente.dart';
import '../models/zona_entrega.dart';
import '../widgets/itens_compra_card.dart';
import '../widgets/resumo_pagamento_card.dart';
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
  final ZonaEntrega? zonaEntrega;

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
    this.zonaEntrega,
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
          valorEntrega: widget.valorEntrega,
          entregaSelecionada: widget.entregaSelecionada,
          saldoUsado: widget.saldoUsado,
          zonaEntrega: widget.zonaEntrega,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final subtotal = ResumoPagamentoCard.calcularSubtotal(widget.carrinho);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Cartão de Débito'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.credit_card, size: 64, color: colorScheme.primary),
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
            const SizedBox(height: 12),
            Text(
              'Pagamento via Cartão de Débito será processado automaticamente.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
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
            onPressed: concluirPagamento,
            style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 52)),
            child: Text('Concluir'),
          ),
        ),
      ),
    );
  }
}
