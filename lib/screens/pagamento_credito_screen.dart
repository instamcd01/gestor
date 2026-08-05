// pagamento_cartao_credito_screen.dart
import 'package:flutter/material.dart';
import 'package:gestor/models/cliente.dart';
import '../models/zona_entrega.dart';
import '../widgets/itens_compra_card.dart';
import '../widgets/resumo_pagamento_card.dart';
import 'conclusao_venda_screen.dart';

class PagamentoCartaoCreditoScreen extends StatelessWidget {
  final double valorTotal;
  final List<Map<String, dynamic>> carrinho;
  final String? idCliente;
  final String metodoPagamento;
  final Cliente cliente;
  final double desconto;
  final String? cupomId;
  final double valorEntrega;
  final String entregaSelecionada;
  final double saldoUsado;
  final ZonaEntrega? zonaEntrega;

  PagamentoCartaoCreditoScreen({
    required this.valorTotal,
    required this.carrinho,
    this.idCliente,
    required this.metodoPagamento,
    required this.cliente,
    required this.desconto,
    this.cupomId,
    required this.valorEntrega,
    required this.entregaSelecionada,
    required this.saldoUsado,
    this.zonaEntrega,
  });

  @override
  Widget build(BuildContext context) {
    final subtotal = ResumoPagamentoCard.calcularSubtotal(carrinho);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Cartão de Crédito'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Icon(Icons.credit_card, size: 64, color: colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              'Cliente: ${cliente.nome}',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            ItensCompraCard(carrinho: carrinho),
            const SizedBox(height: 16),
            ResumoPagamentoCard(
              subtotal: subtotal,
              desconto: desconto,
              valorEntrega: valorEntrega,
              saldoUsado: saldoUsado,
              valorTotal: valorTotal,
            ),
            const SizedBox(height: 12),
            Text(
              'Pagamento via cartão de crédito será processado no valor exato.',
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
            onPressed: () {
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
                    cupomId: cupomId,
                    valorEntrega: valorEntrega,
                    entregaSelecionada: entregaSelecionada,
                    saldoUsado: saldoUsado,
                    zonaEntrega: zonaEntrega,
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 52)),
            child: Text('Concluir Pagamento'),
          ),
        ),
      ),
    );
  }
}
