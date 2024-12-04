import 'package:flutter/material.dart';
import 'package:gestor/providers/pedido_provider.dart';
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
      ],
      child: MaterialApp(
        title: 'PetShop',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: HomeScreen(),
      ),
    );
  }
}
