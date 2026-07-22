import 'package:flutter/material.dart';

import '../models/produto.dart';
import '../utils/produto_validators.dart';

/// Mostra o preço de um produto já considerando promoção: se houver preço
/// promocional válido, mostra o preço normal riscado, o promocional em
/// destaque e um selo com o % de desconto. Usado no catálogo de vendas e
/// no carrinho pra manter a mesma linguagem visual nos dois lugares.
class PrecoComDesconto extends StatelessWidget {
  final Produto produto;
  final bool compact;

  const PrecoComDesconto({super.key, required this.produto, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final desconto = ProdutoValidators.calcularDescontoPercentual(
        produto.preco, produto.precoPromocional);

    if (desconto == null) {
      return Text(
        'R\$ ${produto.preco.toStringAsFixed(2)}',
        style: compact ? null : const TextStyle(fontWeight: FontWeight.w500),
      );
    }

    return Wrap(
      alignment: compact ? WrapAlignment.center : WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 2,
      children: [
        Text(
          'R\$ ${produto.preco.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: compact ? 11 : 13,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            decoration: TextDecoration.lineThrough,
          ),
        ),
        Text(
          'R\$ ${produto.precoPromocional!.toStringAsFixed(2)}',
          style: TextStyle(
            color: Colors.red[700],
            fontWeight: FontWeight.bold,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: Colors.red[700],
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '-${desconto.round()}%',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}
