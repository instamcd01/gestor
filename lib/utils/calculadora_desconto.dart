import 'package:flutter/material.dart';

import 'produto_validators.dart';

/// Mantém "Preço de Venda", "Preço Promocional" e "Desconto (%)"
/// sincronizados nos formulários de produto:
/// - Preencher o preço promocional calcula o desconto (%) sozinho.
/// - Preencher o desconto (%) calcula o preço promocional sozinho.
/// - Mudar o preço de venda recalcula o promocional mantendo o mesmo
///   desconto já definido (se houver).
class CalculadoraDesconto {
  final TextEditingController precoController;
  final TextEditingController promocionalController;
  final TextEditingController descontoController;

  bool _atualizandoProgramaticamente = false;

  CalculadoraDesconto({
    required this.precoController,
    required this.promocionalController,
    required this.descontoController,
  }) {
    precoController.addListener(_aoMudarPreco);
    promocionalController.addListener(_aoMudarPromocional);
    descontoController.addListener(_aoMudarDesconto);
  }

  void dispose() {
    precoController.removeListener(_aoMudarPreco);
    promocionalController.removeListener(_aoMudarPromocional);
    descontoController.removeListener(_aoMudarDesconto);
  }

  void _aoMudarPreco() {
    if (_atualizandoProgramaticamente) return;

    final preco = ProdutoValidators.parseNumero(precoController.text);
    final desconto = ProdutoValidators.parseNumero(descontoController.text);
    if (preco == null || preco <= 0) return;
    if (desconto == null || desconto <= 0 || desconto >= 100) return;

    final promocional = preco * (1 - desconto / 100);

    _atualizandoProgramaticamente = true;
    promocionalController.text = ProdutoValidators.formatarMoeda(promocional);
    _atualizandoProgramaticamente = false;
  }

  void _aoMudarPromocional() {
    if (_atualizandoProgramaticamente) return;

    final preco = ProdutoValidators.parseNumero(precoController.text);
    final promocional = ProdutoValidators.parseNumero(promocionalController.text);
    if (preco == null || preco <= 0) return;
    if (promocional == null || promocional <= 0 || promocional >= preco) return;

    final desconto = (1 - promocional / preco) * 100;

    _atualizandoProgramaticamente = true;
    descontoController.text = desconto.toStringAsFixed(1).replaceAll('.', ',');
    _atualizandoProgramaticamente = false;
  }

  void _aoMudarDesconto() {
    if (_atualizandoProgramaticamente) return;

    final preco = ProdutoValidators.parseNumero(precoController.text);
    final desconto = ProdutoValidators.parseNumero(descontoController.text);
    if (preco == null || preco <= 0) return;
    if (desconto == null || desconto <= 0 || desconto >= 100) return;

    final promocional = preco * (1 - desconto / 100);

    _atualizandoProgramaticamente = true;
    promocionalController.text = ProdutoValidators.formatarMoeda(promocional);
    _atualizandoProgramaticamente = false;
  }
}
