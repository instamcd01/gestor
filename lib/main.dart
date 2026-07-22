import 'package:flutter/material.dart';
import 'package:gestor/providers/carrinho_provider.dart';
import 'package:gestor/providers/historico_vendas_provider.dart';
import 'package:gestor/screens/historico_vendas_screen.dart';
import 'package:gestor/screens/fila_pedidos_screen.dart';
import 'package:provider/provider.dart';
import 'screens/home_screen.dart';
import 'providers/produto_provider.dart';
import 'providers/cliente_provider.dart';
import 'providers/branding_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/usuario_provider.dart';
import 'providers/zona_entrega_provider.dart';
import 'providers/fornecedor_provider.dart';
import 'providers/despesa_provider.dart';
import 'screens/auth_gate.dart';
import 'config/supabase_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Backend único do app (auth, dados multi-tenant com RLS, storage).
  await SupabaseConfig.inicializar();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProdutoProvider()),
        ChangeNotifierProvider(create: (_) => ClientProvider()),
        ChangeNotifierProvider(create: (_) => HistoricoVendasProvider()),
        ChangeNotifierProvider(create: (_) => CarrinhoProvider()),
        ChangeNotifierProvider(create: (_) => BrandingProvider()),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => UsuarioProvider()),
        ChangeNotifierProvider(create: (_) => ZonaEntregaProvider()),
        ChangeNotifierProvider(create: (_) => FornecedorProvider()),
        ChangeNotifierProvider(create: (_) => DespesaProvider()),
      ],
      child: Consumer<BrandingProvider>(
        builder: (context, branding, _) {
          return MaterialApp(
            title: 'Gestor',
            theme: branding.temaClaro,
            darkTheme: branding.temaEscuro,
            themeMode: branding.temaModo,
            home: const AuthGate(),
            routes: {
              '/home': (context) => HomeScreen(),
              '/historico_vendas': (context) => HistoricoVendasScreen(),
              '/pedidos': (context) => const FilaPedidosScreen(),
            },
          );
        },
      ),
    );
  }
}

