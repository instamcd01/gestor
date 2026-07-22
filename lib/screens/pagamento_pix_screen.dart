import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/supabase_config.dart';
import '../models/cliente.dart';
import '../providers/auth_provider.dart';
import '../widgets/itens_compra_card.dart';
import '../widgets/resumo_pagamento_card.dart';
import 'conclusao_venda_screen.dart';

class PagamentoPixScreen extends StatefulWidget {
  final double valorTotal;
  final List<Map<String, dynamic>> carrinho;
  final String metodoPagamento;
  final Cliente cliente;
  final double desconto;
  final double valorEntrega;
  final String entregaSelecionada;
  final double saldoUsado;

  PagamentoPixScreen({
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
  _PagamentoPixScreenState createState() => _PagamentoPixScreenState();
}

class _PagamentoPixScreenState extends State<PagamentoPixScreen> {
  String? _chavePix;

  @override
  void initState() {
    super.initState();
    _carregarChavePix();
  }

  Future<void> _carregarChavePix() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;
    try {
      final data = await supabase.from('empresas').select('chave_pix').eq('id', empresaId).single();
      final chave = data['chave_pix']?.toString() ?? '';
      if (chave.isNotEmpty && mounted) setState(() => _chavePix = chave);
    } catch (e) {
      debugPrint('Erro ao carregar chave Pix: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final subtotal = ResumoPagamentoCard.calcularSubtotal(widget.carrinho);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text('Pagamento Pix')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.pix, size: 64, color: colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              'Cliente: ${widget.cliente.nome}',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            if (_chavePix != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.key, color: Colors.green),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Chave Pix da loja', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                          Text(_chavePix!, style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, size: 20),
                      tooltip: 'Copiar chave',
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _chavePix!));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Chave Pix copiada.')),
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
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
              // Aqui você pode gerar QR code Pix ou lógica real de pagamento
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
            style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 52)),
            child: Text('Confirmar Pagamento Pix'),
          ),
        ),
      ),
    );
  }
}
