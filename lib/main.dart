import 'package:flutter/material.dart';
import 'package:gestor/providers/carrinho_provider.dart';
import 'package:gestor/providers/historico_vendas_provider.dart';
import 'package:gestor/providers/pedido_provider.dart';
import 'package:gestor/screens/conclusao_venda_screen.dart';
import 'package:gestor/screens/historico_vendas_screen.dart';
import 'package:gestor/screens/pagamento_debito_screen.dart';
import 'package:gestor/screens/pedidos_screen.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'providers/produto_provider.dart';
import 'providers/cliente_provider.dart';
import 'providers/vendas_provider.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => ProdutoProvider()),
        ChangeNotifierProvider(create: (context) => ClientProvider()),
        ChangeNotifierProvider(create: (context) => VendasProvider()),
        ChangeNotifierProvider(create: (_) => PedidoProvider()),
        ChangeNotifierProvider(create: (_) => HistoricoVendasProvider()),
    // ChangeNotifierProvider(create: (context) => CarrinhoProvider()),
      ],
      child: MaterialApp(
        title: 'PetShop',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: HomeScreen(),
        routes: {
          '/home': (context) => HomeScreen(),
          '/pagamento_cartao_debito': (context) => PagamentoCartaoDebitoScreen(valorTotal: 0.0, carrinho: [],),
          '/conclusao_venda': (context) => ConclusaoVendaScreen(valorTotal: 0.0,carrinho: [],),
          '/historico_vendas': (context) => HistoricoVendasScreen(),
          '/pedidos': (context) => PedidosScreen(pedidosConcluidos: [],),
        },
      ),
    );
  }
}
