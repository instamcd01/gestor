import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor/models/cliente.dart';
import 'package:gestor/models/produto.dart';
import 'package:gestor/providers/auth_provider.dart';
import 'package:gestor/providers/carrinho_provider.dart';
import 'package:gestor/providers/kit_produto_provider.dart';
import 'package:gestor/providers/metodos_pagamento_provider.dart';
import 'package:gestor/providers/produto_provider.dart';
import 'package:gestor/screens/vender_pc_screen.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Produto _produto() => Produto(
      id: 'p1',
      nome: 'Ração Teste 1kg',
      preco: 50,
      descricao: '',
      categoria: 'Ração',
      estoqueAtual: 10,
      estoqueMinimo: 1,
      imagemUrl: '',
      codigoBarras: '789',
      custo: 20,
    );

Cliente _cliente() => Cliente(
      idCliente: 'c1',
      nome: 'Cliente de Teste',
      celular: '21900000000',
      email: '',
      endereco: 'Rua A',
      complemento: '',
      cpf: '',
      observacao: '',
      saldo: 0,
      pets: const [],
    );

Future<CarrinhoProvider> _montar(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final carrinho = CarrinhoProvider()
    ..adicionarProduto(_produto())
    ..selecionarCliente(_cliente());
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<CarrinhoProvider>.value(value: carrinho),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => ProdutoProvider()..definirProdutosParaTeste([_produto()])),
      ChangeNotifierProvider(create: (_) => KitProdutoProvider()),
      ChangeNotifierProvider(create: (_) => MetodosPagamentoProvider()),
    ],
    child: const MaterialApp(home: VenderPcScreen()),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return carrinho;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:1',
      anonKey: 'teste',
      authOptions: const FlutterAuthClientOptions(localStorage: EmptyLocalStorage()),
    );
  });

  testWidgets('venda concluída em outra tela (Pix, link): carrinho limpo não quebra o painel de pagamento', (tester) async {
    final carrinho = await _montar(tester);
    expect(tester.takeException(), isNull);

    // F9: vai pro pagamento, como quem escolhe Pix em seguida.
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pump();
    expect(find.text('Pagar · F9'), findsNothing);

    // A tela de conclusão grava a venda e limpa o carrinho, com o Vender parado atrás.
    carrinho.limparCarrinho();
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Volta sozinho pra uma venda nova.
    await tester.pump();
    expect(find.text('Busque ou bipe um produto pra começar.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('sessão', () {
    bool precisa(String? sessao, String? carregado) =>
        AuthProvider.precisaRecarregarUsuario(usuarioDaSessao: sessao, usuarioCarregado: carregado);

    test('renovar o login do mesmo usuário não recarrega o app', () => expect(precisa('u1', 'u1'), isFalse));
    test('entrar, sair e trocar de conta recarregam', () {
      expect(precisa('u1', null), isTrue);
      expect(precisa(null, 'u1'), isTrue);
      expect(precisa('u2', 'u1'), isTrue);
    });
  });

  testWidgets('desistir do pagamento com Esc volta pro carrinho com os itens', (tester) async {
    final carrinho = await _montar(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f9);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Pagar · F9'), findsOneWidget);
    expect(carrinho.itens, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
