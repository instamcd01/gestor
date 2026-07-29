import 'package:flutter/material.dart';

import '../models/cliente.dart';
import '../models/zona_entrega.dart';
import '../theme/app_theme.dart';
import '../utils/cliente_validators.dart';
import '../utils/formatadores_input.dart';
import '../widgets/itens_compra_card.dart';
import '../widgets/resumo_pagamento_card.dart';
import 'conclusao_venda_screen.dart';

class PagamentoDinheiroScreen extends StatefulWidget {
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

  PagamentoDinheiroScreen({
    required this.valorTotal,
    required this.carrinho,
    this.idCliente,
    required this.metodoPagamento,
    required this.cliente,
    this.desconto = 0.0,
    required this.valorEntrega,
    required this.entregaSelecionada,
    required this.saldoUsado,
    this.zonaEntrega,
  });

  @override
  _PagamentoDinheiroScreenState createState() => _PagamentoDinheiroScreenState();
}

class _PagamentoDinheiroScreenState extends State<PagamentoDinheiroScreen> {
  final TextEditingController _valorRecebidoController = TextEditingController();
  double _troco = 0.0;
  double _valorFaltando = 0.0;
  double _valorPago = 0.0;

  @override
  void dispose() {
    _valorRecebidoController.dispose();
    super.dispose();
  }

  void calcularTrocoOuFalta() {
    final valorRecebido = ClienteValidators.parseNumero(_valorRecebidoController.text) ?? 0.0;
    setState(() {
      _valorPago = valorRecebido;
      if (valorRecebido >= widget.valorTotal) {
        _troco = valorRecebido - widget.valorTotal;
        _valorFaltando = 0.0;
      } else {
        _troco = 0.0;
        _valorFaltando = widget.valorTotal - valorRecebido;
      }
    });
  }

  void preencherValorExato() {
    _valorRecebidoController.text = ClienteValidators.formatarMoeda(widget.valorTotal);
    calcularTrocoOuFalta();
  }

  void concluirPagamento() {
    if (_valorFaltando > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pagamento incompleto!')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ConclusaoVendaScreen(
          valorTotal: widget.valorTotal,
          carrinho: widget.carrinho,
          idCliente: widget.idCliente,
          metodoPagamento: widget.metodoPagamento,
          cliente: widget.cliente,
          valorPago: _valorPago,
          troco: _troco,
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
      appBar: AppBar(title: Text('Pagamento em Dinheiro')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.payments_outlined, size: 64, color: colorScheme.primary),
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
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _valorRecebidoController,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [MoedaInputFormatter()],
                    decoration: InputDecoration(
                      labelText: 'Valor Recebido',
                      prefixText: 'R\$ ',
                    ),
                    onChanged: (value) => calcularTrocoOuFalta(),
                  ),
                ),
                SizedBox(width: 10),
                OutlinedButton(
                  onPressed: preencherValorExato,
                  child: Text('Valor exato'),
                ),
              ],
            ),
            if (_troco > 0 || _valorFaltando > 0) ...[
              const SizedBox(height: 16),
              Card(
                margin: EdgeInsets.zero,
                color: _troco > 0
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.red.withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    _troco > 0
                        ? 'Troco: R\$ ${_troco.toStringAsFixed(2)}'
                        : 'Falta: R\$ ${_valorFaltando.toStringAsFixed(2)}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.tomAdaptavel(
                        _troco > 0 ? Colors.green : Colors.red,
                        Theme.of(context).brightness,
                      ),
                    ),
                  ),
                ),
              ),
            ],
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
