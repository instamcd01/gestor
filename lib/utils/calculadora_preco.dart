import 'package:flutter/material.dart';

import 'produto_validators.dart';

/// Mantém "Preço de Venda", "Custo", "Markup (%)" e "Lucro (R$)"
/// sincronizados nos formulários de produto:
/// - Preencher preço + custo calcula markup e lucro automaticamente.
/// - Preencher markup ou lucro (com custo já preenchido) calcula o preço.
///
/// Vale só pro preço de venda do site/app — os preços por marketplace
/// (seção "Disponibilidade em Marketplaces") são independentes disso.
class CalculadoraPrecoMarkup {
  final TextEditingController precoController;
  final TextEditingController custoController;
  final TextEditingController markupController;
  final TextEditingController lucroController;

  bool _atualizandoProgramaticamente = false;

  CalculadoraPrecoMarkup({
    required this.precoController,
    required this.custoController,
    required this.markupController,
    required this.lucroController,
  }) {
    precoController.addListener(_aoMudarPrecoOuCusto);
    custoController.addListener(_aoMudarPrecoOuCusto);
    markupController.addListener(_aoMudarMarkup);
    lucroController.addListener(_aoMudarLucro);
  }

  void dispose() {
    precoController.removeListener(_aoMudarPrecoOuCusto);
    custoController.removeListener(_aoMudarPrecoOuCusto);
    markupController.removeListener(_aoMudarMarkup);
    lucroController.removeListener(_aoMudarLucro);
  }

  void _aoMudarPrecoOuCusto() {
    if (_atualizandoProgramaticamente) return;

    final preco = ProdutoValidators.parseNumero(precoController.text);
    final custo = ProdutoValidators.parseNumero(custoController.text);
    if (preco == null || custo == null || preco <= 0) return;

    final lucro = preco - custo;
    final markup = (lucro / preco) * 100;

    _atualizandoProgramaticamente = true;
    lucroController.text = ProdutoValidators.formatarMoeda(lucro);
    markupController.text = markup.toStringAsFixed(1).replaceAll('.', ',');
    _atualizandoProgramaticamente = false;
  }

  void _aoMudarMarkup() {
    if (_atualizandoProgramaticamente) return;

    final custo = ProdutoValidators.parseNumero(custoController.text);
    final markup = ProdutoValidators.parseNumero(markupController.text);
    if (custo == null || markup == null || markup >= 100) return;

    final preco = custo / (1 - markup / 100);
    if (preco <= 0) return;

    _atualizandoProgramaticamente = true;
    precoController.text = ProdutoValidators.formatarMoeda(preco);
    lucroController.text = ProdutoValidators.formatarMoeda(preco - custo);
    _atualizandoProgramaticamente = false;
  }

  void _aoMudarLucro() {
    if (_atualizandoProgramaticamente) return;

    final custo = ProdutoValidators.parseNumero(custoController.text);
    final lucro = ProdutoValidators.parseNumero(lucroController.text);
    if (custo == null || lucro == null) return;

    final preco = custo + lucro;
    if (preco <= 0) return;

    final markup = (lucro / preco) * 100;

    _atualizandoProgramaticamente = true;
    precoController.text = ProdutoValidators.formatarMoeda(preco);
    markupController.text = markup.toStringAsFixed(1).replaceAll('.', ',');
    _atualizandoProgramaticamente = false;
  }
}
