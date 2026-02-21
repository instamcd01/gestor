import 'package:flutter/material.dart';
import 'package:gestor/providers/carrinho_provider.dart';
import 'package:gestor/providers/historico_vendas_provider.dart';
import 'package:gestor/providers/pedido_provider.dart';
import 'package:gestor/screens/conclusao_venda_screen.dart';
import 'package:gestor/screens/historico_vendas_screen.dart';
import 'package:gestor/screens/pagamento_debito_screen.dart';
import 'package:gestor/screens/pedidos_screen.dart';
import 'package:provider/provider.dart';
import 'models/cliente.dart';
import 'screens/home_screen.dart';
import 'providers/produto_provider.dart';
import 'providers/cliente_provider.dart';
import 'providers/vendas_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart'; // 👈 importa o AppCheck
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 👇 Ativando o App Check com Debug Provider
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.debug,
    appleProvider: AppleProvider.debug,
    // Se não for usar Web, pode remover a linha abaixo
    webProvider: ReCaptchaV3Provider('SUA_CHAVE_RECAPTCHA'),
  );

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (context) {
            final provider = ProdutoProvider();
            provider.carregarProdutos();
            return provider;
          },
        ),
        ChangeNotifierProvider(
          create: (context) {
            final provider = ClientProvider();
            provider.carregarClientesDoFirestore();
            return provider;
          },
        ),
        ChangeNotifierProvider(create: (context) => VendasProvider()),
        ChangeNotifierProvider(create: (_) => PedidoProvider()),
        ChangeNotifierProvider(create: (_) => HistoricoVendasProvider()),
        ChangeNotifierProvider(create: (context) => ProdutoProvider()..carregarProdutos()),
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
          '/historico_vendas': (context) => HistoricoVendasScreen(),
          '/pedidos': (context) => PedidosScreen(pedidosConcluidos: []),
        },
      ),
    );
  }
}

