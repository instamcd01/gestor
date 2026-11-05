import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gestor/models/cliente.dart';
import 'package:gestor/models/produto.dart';
import 'package:gestor/models/venda.dart';
import 'package:gestor/providers/auth_provider.dart';
import 'package:gestor/providers/despesa_provider.dart';
import 'package:gestor/providers/historico_vendas_provider.dart';
import 'package:gestor/providers/produto_provider.dart';
import 'package:gestor/screens/inicio_pc.dart';
import 'package:gestor/utils/app_destinos.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Venda _venda(String id, int numero, String nome, String status, {int minutos = 5, double total = 100, String entrega = ''}) => Venda(
      idVenda: id,
      numeroSequencial: numero,
      cliente: Cliente(
        idCliente: 'c$id',
        nome: nome,
        celular: '21999990000',
        email: '',
        endereco: '',
        complemento: '',
        cpf: '',
        observacao: '',
        saldo: 0,
        pets: const [],
      ),
      dataVenda: DateTime.now().subtract(Duration(minutes: minutos)),
      subtotal: total,
      desconto: 0,
      saldoUsado: 0,
      valorEntrega: 0,
      entregaSelecionada: entrega,
      valorTotal: total,
      valorPago: total,
      troco: 0,
      metodoPagamento: 'Pix',
      totalItens: 1,
      itens: const [],
      custoTotal: 0,
      lucroTotal: 0,
      status: status,
    );

Produto _produto(String id, String nome, int tem, int minimo, {bool ativo = true}) => Produto(
      id: id,
      nome: nome,
      preco: 10,
      descricao: '',
      categoria: 'Ração',
      estoqueAtual: tem,
      estoqueMinimo: minimo,
      imagemUrl: '',
      codigoBarras: id,
      custo: 5,
      ativo: ativo,
    );

/// Sem sessão, a autenticação real limpa o papel sozinha logo depois de criada.
class _AuthFalsa extends AuthProvider {
  final String _papelFalso;
  _AuthFalsa(this._papelFalso);

  @override
  bool get isVendedor => _papelFalso == 'vendedor';
  @override
  bool get podeVerFinancas => _papelFalso != 'vendedor';
  @override
  String? get nome => 'Lucas Machado';
}

class _Aberturas {
  final lista = <String>[];
}

Future<_Aberturas> _montar(WidgetTester tester, double largura, double altura, {String papel = 'dono', List<Venda>? vendas}) async {
  tester.view.physicalSize = Size(largura, altura);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  addTearDown(() {
    pedidoParaAbrir.value = null;
    produtoParaAbrir.value = null;
  });
  final aberturas = _Aberturas();
  final auth = _AuthFalsa(papel);
  await tester.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthProvider>.value(value: auth),
      ChangeNotifierProvider(create: (_) => DespesaProvider()),
      ChangeNotifierProvider(
        create: (_) => HistoricoVendasProvider()
          ..definirVendasParaTeste(vendas ??
              [
                _venda('1', 5403, 'Saiu Primeiro', StatusPedido.saiuParaEntrega, minutos: 40),
                _venda('2', 5412, 'Pendente Nova', StatusPedido.pendente, minutos: 2),
                _venda('3', 5411, 'Pendente Antiga', StatusPedido.pendente, minutos: 11),
                _venda('4', 5409, 'Em Preparo', StatusPedido.preparando, minutos: 20),
                _venda('5', 5300, 'Entregue Hoje', StatusPedido.entregue, minutos: 0, total: 250),
              ]),
      ),
      ChangeNotifierProvider(
        create: (_) => ProdutoProvider()
          ..definirProdutosParaTeste([
            _produto('a', 'Ração Quase Normal', 4, 5),
            _produto('b', 'Antipulgas Quase Acabando', 1, 5),
            _produto('c', 'Sem Estoque Nenhum', 0, 5),
            _produto('d', 'Estoque Tranquilo', 50, 5),
            _produto('e', 'Inativo Baixo', 1, 5, ativo: false),
          ]),
      ),
    ],
    child: MaterialApp(
      home: Row(children: [
        const SizedBox(width: 256),
        Expanded(
          child: InicioPc(
            mostrarAppBar: true,
            lucroLiquidoReal: 842.3,
            recarregar: () async {},
            aoVoltar: () => aberturas.lista.add('voltou'),
            abrirVender: () => aberturas.lista.add('vender'),
            abrirPedidos: () => aberturas.lista.add('pedidos'),
            abrirProdutos: () => aberturas.lista.add('produtos'),
            abrirFluxoCaixa: () => aberturas.lista.add('fluxo'),
            abrirLucro: () => aberturas.lista.add('lucro'),
          ),
        ),
      ]),
    ),
  ));
  await tester.pump();
  return aberturas;
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

  group('regras', () {
    test('saudação usa o primeiro nome e funciona sem nome', () {
      expect(saudacaoDoInicio('Lucas Machado', agora: DateTime(2026, 11, 5, 9)), 'Bom dia, Lucas');
      expect(saudacaoDoInicio(' ', agora: DateTime(2026, 11, 5, 14)), 'Boa tarde');
      expect(saudacaoDoInicio(null, agora: DateTime(2026, 11, 5, 20)), 'Boa noite');
    });

    test('pedidos: etapa mais atrás primeiro e, dentro dela, o mais antigo', () {
      final ordem = pedidosPorEtapa([
        _venda('1', 1, 'Saiu', StatusPedido.saiuParaEntrega, minutos: 40),
        _venda('2', 2, 'PendNova', StatusPedido.pendente, minutos: 2),
        _venda('3', 3, 'PendAntiga', StatusPedido.pendente, minutos: 11),
      ]).map((v) => v.cliente.nome);
      expect(ordem, ['PendAntiga', 'PendNova', 'Saiu']);
    });

    test('estoque baixo: mais perto de acabar primeiro; zerado e folgado fora', () {
      final nomes = produtosEstoqueBaixo([
        _produto('a', 'Quatro de cinco', 4, 5),
        _produto('b', 'Um de cinco', 1, 5),
        _produto('c', 'Zerado', 0, 5),
        _produto('d', 'Folgado', 50, 5),
        _produto('e', 'Sem mínimo', 1, 0),
        _produto('f', 'Inativo', 1, 5, ativo: false),
      ]).map((p) => p.nome);
      expect(nomes, ['Um de cinco', 'Quatro de cinco']);
    });

    test('agendado e retirada nunca contam como atrasado', () {
      final semPrazo = _venda('1', 1, 'X', StatusPedido.preparando, entrega: 'Zona A');
      expect(semPrazo.atrasadoEm(DateTime.now()), isFalse);
      expect(_venda('2', 2, 'Y', StatusPedido.entregue, entrega: 'Zona A').atrasadoEm(DateTime.now()), isFalse);
    });
  });

  for (final (largura, altura) in [(1200.0, 700.0), (1366.0, 768.0), (1920.0, 1080.0), (1200.0, 500.0)]) {
    testWidgets('sem estouro em ${largura.toInt()}x${altura.toInt()}', (tester) async {
      await _montar(tester, largura, altura);
      expect(tester.takeException(), isNull);
      expect(find.text('Lucro líquido real'), findsOneWidget);
    });
  }

  testWidgets('dono vê os 5 números; "Receita do mês" não existe mais', (tester) async {
    await _montar(tester, 1920, 1080);
    for (final r in ['Hoje', 'Ontem', 'Este mês', 'Despesas do mês', 'Lucro líquido real']) {
      expect(find.text(r), findsOneWidget);
    }
    expect(find.text('Receita do mês'), findsNothing);
    expect(find.text('2 pedidos aguardando confirmação'), findsOneWidget);
  });

  testWidgets('vendedor não vê estoque nem finanças', (tester) async {
    await _montar(tester, 1920, 1080, papel: 'vendedor');
    expect(tester.takeException(), isNull);
    expect(find.text('Estoque baixo'), findsNothing);
    expect(find.text('Lucro líquido real'), findsNothing);
    expect(find.text('Despesas do mês'), findsNothing);
    expect(find.text('Pedidos agora'), findsOneWidget);
  });

  testWidgets('estoque baixo lista só os certos, com o mais urgente em cima', (tester) async {
    await _montar(tester, 1920, 1080);
    expect(find.text('Sem Estoque Nenhum'), findsNothing);
    expect(find.text('Estoque Tranquilo'), findsNothing);
    expect(find.text('Inativo Baixo'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Antipulgas Quase Acabando')).dy,
      lessThan(tester.getTopLeft(find.text('Ração Quase Normal')).dy),
    );
  });

  testWidgets('clicar no pedido leva pra Pedidos com ele; no produto, pra Produtos', (tester) async {
    final aberturas = await _montar(tester, 1920, 1080);
    await tester.tap(find.text('Pendente Antiga'));
    expect(aberturas.lista, ['pedidos']);
    expect(pedidoParaAbrir.value, '3');

    await tester.tap(find.text('Ração Quase Normal'));
    expect(aberturas.lista, ['pedidos', 'produtos']);
    expect(produtoParaAbrir.value, 'a');
  });

  testWidgets('botões do topo vão pras seções', (tester) async {
    final aberturas = await _montar(tester, 1366, 768);
    await tester.tap(find.text('Vender · F2'));
    await tester.tap(find.text('Pedidos · F3'));
    await tester.tap(find.text('Produtos · F4'));
    expect(aberturas.lista, ['vender', 'pedidos', 'produtos']);
  });

  testWidgets('sem pedido e sem produto baixo: mensagem em vez de lista vazia', (tester) async {
    await _montar(tester, 1366, 768, vendas: const []);
    expect(find.text('Nenhum pedido em andamento'), findsOneWidget);
    expect(find.textContaining('aguardando confirmação'), findsNothing);
  });
}
