import 'package:flutter/material.dart';

import '../models/produto.dart';

/// Card com a lista itemizada dos produtos da compra — usado em Pagamento
/// e em todas as telas de método de pagamento, pra manter a mesma
/// apresentação em vez de cada uma desenhar essa lista do zero (antes
/// cada tela mostrava ou não os itens, e de um jeito diferente).
class ItensCompraCard extends StatelessWidget {
  final List<Map<String, dynamic>> carrinho;

  const ItensCompraCard({super.key, required this.carrinho});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Itens da compra',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final item in carrinho) _linhaItem(context, item, colorScheme),
          ],
        ),
      ),
    );
  }

  Widget _linhaItem(BuildContext context, Map<String, dynamic> item, ColorScheme colorScheme) {
    final produto = item['produto'] as Produto;
    final quantidade = item['quantidade'] as int;
    final precoUnitario = (item['precoUnitario'] as num?)?.toDouble() ?? produto.preco;
    final precoTotalItem = (item['precoTotalItem'] as num?)?.toDouble() ?? precoUnitario * quantidade;
    final temPromocao = produto.precoPromocional != null &&
        produto.precoPromocional! > 0 &&
        produto.precoPromocional! < produto.preco;
    final precoOriginalTotal = produto.preco * quantidade;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${quantidade}x', style: TextStyle(color: colorScheme.onSurfaceVariant)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(produto.nome, overflow: TextOverflow.ellipsis, maxLines: 1),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (temPromocao)
                Text(
                  'R\$ ${precoOriginalTotal.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              Text(
                'R\$ ${precoTotalItem.toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: temPromocao ? Colors.red[700] : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
