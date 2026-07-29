import 'package:flutter/material.dart';

/// Card de resumo financeiro reutilizado em todas as telas de pagamento
/// (dinheiro, pix, crédito, débito, link, outros) — antes cada uma exibia
/// (ou não) subtotal/desconto/entrega/saldo de um jeito diferente e
/// inconsistente.
class ResumoPagamentoCard extends StatelessWidget {
  final double subtotal;
  final double desconto;
  final double valorEntrega;
  final double saldoUsado;
  final double valorTotal;

  const ResumoPagamentoCard({
    super.key,
    required this.subtotal,
    required this.desconto,
    required this.valorEntrega,
    required this.saldoUsado,
    required this.valorTotal,
  });

  static double calcularSubtotal(List<Map<String, dynamic>> carrinho) {
    return carrinho.fold<double>(
      0.0,
      (soma, item) => soma + ((item['precoTotalItem'] as num?)?.toDouble() ?? 0.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _linha('Subtotal', subtotal),
            _linha(
              'Entrega',
              valorEntrega,
              textoZero: 'Frete Grátis',
              corTextoZero: Colors.green,
            ),
            if (desconto > 0) _linha('Desconto', desconto, negativo: true, cor: Colors.red),
            if (saldoUsado > 0)
              _linha('Saldo do cliente', saldoUsado, negativo: true, cor: Colors.green),
            const Divider(),
            _linha('Total a pagar', valorTotal, negrito: true, tamanho: 18),
          ],
        ),
      ),
    );
  }

  Widget _linha(
    String rotulo,
    double valor, {
    bool negativo = false,
    bool negrito = false,
    double tamanho = 15,
    Color? cor,
    String? textoZero,
    Color? corTextoZero,
  }) {
    final ehZero = valor == 0 && textoZero != null;
    final texto = ehZero
        ? textoZero
        : '${negativo ? '- ' : ''}R\$ ${valor.toStringAsFixed(2)}';
    final corFinal = ehZero ? corTextoZero : cor;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            rotulo,
            style: TextStyle(fontSize: tamanho, fontWeight: negrito ? FontWeight.bold : FontWeight.w500),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              texto,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: tamanho,
                fontWeight: negrito ? FontWeight.bold : FontWeight.normal,
                color: corFinal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
