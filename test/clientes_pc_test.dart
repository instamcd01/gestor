import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor/models/cliente.dart';
import 'package:gestor/providers/auth_provider.dart';
import 'package:gestor/providers/cliente_provider.dart';
import 'package:gestor/providers/modulo_provider.dart';
import 'package:gestor/screens/clientes_hub_screen.dart';
import 'package:gestor/screens/clientes_pc.dart';
import 'package:gestor/screens/vender_pc_screen.dart';
import 'package:gestor/utils/app_destinos.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Cliente _cliente(
  String id,
  String nome, {
  String celular = '5521999990000',
  String? categoria,
  double total = 0,
  int compras = 0,
  int? diasDesdeCompra,
  double saldo = 0,
  double petcash = 0,
  String bairro = 'Campo Grande',
  String? canal,
  String? telefoneKyte,
}) =>
    Cliente(
      idCliente: id,
      nome: nome,
      celular: celular,
      email: 'a@b.com',
      endereco: 'Rua A',
      numero: '10',
      bairro: bairro,
      complemento: '',
      cpf: '',
      observacao: '',
      saldo: saldo,
      saldoPetCash: petcash,
      pets: const [],
      categoriaCliente: categoria,
      totalGasto: total,
      quantidadeCompras: compras,
      ultimaCompra: diasDesdeCompra == null ? null : DateTime.now().subtract(Duration(days: diasDesdeCompra)),
      canalOrigem: canal,
      telefoneKyte: telefoneKyte,
    );

final _clientes = [
  _cliente('1', 'Ana', categoria: 'regular', total: 100, compras: 2, diasDesdeCompra: 3),
  _cliente('2', 'Bruno', categoria: 'vip', total: 900, compras: 9, diasDesdeCompra: 74, saldo: 12.4),
  _cliente('3', 'Carla Maria de Oliveira Santos Pereira da Silva Nome Bem Comprido', categoria: 'novo', total: 50, compras: 1, diasDesdeCompra: 0, petcash: 8.2),
  _cliente('4', 'Dora', categoria: 'inativo'),
];

Future<void> _montar(WidgetTester tester, double largura, double altura) async {
  tester.view.physicalSize = Size(largura, altura);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final provider = ClientProvider()..definirClientesParaTeste(_clientes);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<ClientProvider>.value(value: provider),
      ChangeNotifierProvider(create: (_) => AuthProvider()),
      ChangeNotifierProvider(create: (_) => ModuloProvider()),
    ],
    // Com o espaço que a barra lateral ocupa de verdade na janela.
    child: MaterialApp(
      home: Row(children: [
        const SizedBox(width: 256),
        Expanded(
          child: MediaQuery(
            data: MediaQueryData(size: Size(largura, altura)),
            child: const ClientesPc(),
          ),
        ),
      ]),
    ),
  ));
  await tester.pump();
  await tester.pump();
}

List<String> _nomesNaTela(WidgetTester tester) => _clientes
    .map((c) => c.nome)
    .where((n) => find.text(n).evaluate().isNotEmpty)
    .toList()
  ..sort((a, b) => tester.getTopLeft(find.text(a).first).dy.compareTo(tester.getTopLeft(find.text(b).first).dy));

void main() {
  // Endereço falso e sem sessão: nada aqui chega no banco. As chamadas falham
  // e a tela precisa continuar de pé só com a lista que já está no provider.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:1',
      anonKey: 'teste',
      authOptions: const FlutterAuthClientOptions(localStorage: EmptyLocalStorage()),
    );
  });

  group('telefoneContato', () {
    test('placeholder do Kyte nunca aparece como telefone', () {
      expect(_cliente('k', 'K', celular: 'kyte-sem-numero-7').telefoneContato, '');
      expect(_cliente('k', 'K', celular: 'kyte-sem-numero-7', telefoneKyte: '21988887777').telefoneContato, '21988887777');
      expect(_cliente('n', 'N', celular: '21977776666').telefoneContato, '21977776666');
    });
  });

  for (final (largura, altura) in [(1200.0, 700.0), (1366.0, 768.0), (1920.0, 1080.0)]) {
    testWidgets('sem estouro em ${largura.toInt()} px: lista e cliente aberto', (tester) async {
      await _montar(tester, largura, altura);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Bruno'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(find.text('Nova venda · F2'), findsOneWidget);
      expect(find.text('Volta a cada'), findsOneWidget);

      await tester.tap(find.textContaining('Comprido').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('começa do maior total gasto e o título inverte a ordem', (tester) async {
    await _montar(tester, 1920, 1080);
    expect(_nomesNaTela(tester).first, 'Bruno');
    await tester.tap(find.text('TOTAL GASTO'));
    await tester.pump();
    expect(_nomesNaTela(tester).first, 'Dora');
  });

  testWidgets('filtros: categoria, com saldo e sem comprar há 60+ dias', (tester) async {
    await _montar(tester, 1920, 1080);
    Finder chip(String nome) => find.widgetWithText(ChoiceChip, nome);

    await tester.tap(chip('VIP'));
    await tester.pump();
    expect(_nomesNaTela(tester), ['Bruno']);

    await tester.tap(chip('Com saldo'));
    await tester.pump();
    expect(_nomesNaTela(tester), ['Bruno']);

    await tester.tap(chip('Sem comprar há 60+ dias'));
    await tester.pump();
    // Quem nunca comprou (Dora) não conta como "sumiu".
    expect(_nomesNaTela(tester), ['Bruno']);
    expect(find.text('há 74 dias'), findsOneWidget);

    await tester.tap(chip('Inativo'));
    await tester.pump();
    expect(_nomesNaTela(tester), ['Dora']);
  });

  testWidgets('F2 com cliente aberto leva ele pro Vender; sem cliente, não', (tester) async {
    await _montar(tester, 1920, 1080);
    final secoes = <String>[];
    irParaSecaoDoMenu = (titulo) {
      secoes.add(titulo);
      return true;
    };
    addTearDown(() {
      irParaSecaoDoMenu = null;
      vendaParaCliente.value = null;
    });

    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    expect(vendaParaCliente.value, isNull);

    await tester.tap(find.text('Bruno'));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    expect(secoes, ['Vender']);
    expect(vendaParaCliente.value?.idCliente, '2');
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('↑ ↓ trocam de cliente e Esc fecha o painel', (tester) async {
    await _montar(tester, 1920, 1080);
    await tester.tap(find.text('Bruno'));
    await tester.pump();
    expect(find.text('Nova venda · F2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    // Bruno (900) → Ana (100): o nome dela aparece também no painel.
    expect(find.text('Ana'), findsNWidgets(2));

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.text('Nova venda · F2'), findsNothing);
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('aba Histórico Kyte: banco fora do ar mostra erro, sem quebrar', (tester) async {
    await _montar(tester, 1366, 768);
    await tester.tap(find.text('Histórico Kyte'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Erro ao carregar histórico do Kyte'), findsOneWidget);
  });

  for (final (largura, abreTabela) in [(800.0, false), (1300.0, true)]) {
    testWidgets('Clientes no menu com ${largura.toInt()} px: ${abreTabela ? 'tabela direto' : 'menu de sempre'}', (tester) async {
      tester.view.physicalSize = Size(largura, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ClientProvider()..definirClientesParaTeste(_clientes)),
          ChangeNotifierProvider(create: (_) => AuthProvider()),
          ChangeNotifierProvider(create: (_) => ModuloProvider()),
        ],
        child: const MaterialApp(home: ClientesHubScreen()),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.byType(ClientesPc), abreTabela ? findsOneWidget : findsNothing);
      expect(find.text('Relacionamento'), abreTabela ? findsNothing : findsOneWidget);
    });
  }

  testWidgets('busca filtra a tabela', (tester) async {
    await _montar(tester, 1920, 1080);
    await tester.enterText(find.byType(TextField).first, 'ana');
    await tester.pump();
    expect(_nomesNaTela(tester), ['Ana']);
  });
}
