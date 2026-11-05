import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor/widgets/enviar_orcamento_dialog.dart';
import 'package:gestor/widgets/orcamento_imagem_widget.dart';
import 'package:intl/date_symbol_data_local.dart';

ItemOrcamentoImagem _item(double preco, {int qtd = 1, double? cheio}) =>
    ItemOrcamentoImagem(nome: 'Ração X 15kg – Fabricante', quantidade: qtd, precoUnitario: preco, precoCheio: cheio);

Future<void> _montar(WidgetTester tester, OrcamentoImagemWidget w) async {
  tester.view.physicalSize = const Size(540, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: SingleChildScrollView(child: w)));
}

String _so(String t) => t.replaceAll(' ', ' ');

bool _temTexto(WidgetTester tester, String trecho) => find
    .byWidgetPredicate((w) =>
        (w is Text && _so(w.data ?? '').contains(trecho)) ||
        (w is RichText && _so(w.text.toPlainText()).contains(trecho)))
    .evaluate()
    .isNotEmpty;

OrcamentoImagemWidget _orcamento(List<ItemOrcamentoImagem> itens,
        {double? entrega, double? cheia, double? minimo, bool retirada = false, double desconto = 0}) =>
    OrcamentoImagemWidget(
      nomeLoja: 'Loja',
      corPrimaria: Colors.blue,
      data: DateTime(2026, 11, 5),
      itens: itens,
      entrega: entrega,
      entregaCheia: cheia,
      minimoFreteGratis: minimo,
      retirada: retirada,
      desconto: desconto,
    );

void main() {
  setUpAll(() => initializeDateFormatting('pt_BR'));

  testWidgets('perto do mínimo mostra quanto falta pro frete grátis', (tester) async {
    await _montar(tester, _orcamento([_item(39.64)], entrega: 7.99, cheia: 7.99, minimo: 50));
    expect(_temTexto(tester, 'Faltam R\$ 10,36 para o frete grátis'), isTrue);
    expect(_temTexto(tester, 'R\$ 47,63'), isTrue);
  });

  testWidgets('longe do mínimo não mostra a meta', (tester) async {
    await _montar(tester, _orcamento([_item(40)], entrega: 29.9, cheia: 29.9, minimo: 250));
    expect(_temTexto(tester, 'Faltam'), isFalse);
  });

  testWidgets('frete grátis corta a entrega e soma na economia', (tester) async {
    await _montar(tester, _orcamento([_item(90, cheio: 100)], entrega: 0, cheia: 7.99, minimo: 50, desconto: 5));
    expect(_temTexto(tester, 'Grátis'), isTrue);
    expect(_temTexto(tester, 'R\$ 7,99'), isTrue);
    expect(_temTexto(tester, 'R\$ 22,99'), isTrue); // 10 de promoção + 5 de desconto + 7,99 de entrega
    expect(_temTexto(tester, 'Faltam'), isFalse);
  });

  testWidgets('retirada não fala de frete nem de economia inexistente', (tester) async {
    await _montar(tester, _orcamento([_item(10)], entrega: 0, retirada: true));
    expect(_temTexto(tester, 'Retirada na loja'), isTrue);
    expect(_temTexto(tester, 'Faltam'), isFalse);
    expect(_temTexto(tester, 'economizando'), isFalse);
  });

  testWidgets('nome sem fabricante, com o peso', (tester) async {
    await _montar(tester, _orcamento([_item(10)], entrega: 5));
    expect(_temTexto(tester, 'Ração X 15kg'), isTrue);
    expect(_temTexto(tester, 'Fabricante'), isFalse);
  });

  test('avisos de recusa explicam o que fazer', () {
    expect(textoMotivoOrcamento('fora_da_janela'), contains('24 horas'));
    expect(textoMotivoOrcamento('meta', erro: 'x'), contains('x'));
    expect(textoMotivoOrcamento('qualquer'), contains('Tente de novo'));
  });
}
