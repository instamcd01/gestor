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
import 'providers/zona_entrega_99food_provider.dart';
import 'providers/fornecedor_provider.dart';
import 'providers/despesa_provider.dart';
import 'providers/preferencias_provider.dart';
import 'providers/notificacao_provider.dart';
import 'providers/entrada_provider.dart';
import 'providers/cupom_provider.dart';
import 'screens/auth_gate.dart';
import 'config/supabase_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Backend único do app (auth, dados multi-tenant com RLS, storage).
  await SupabaseConfig.inicializar();

  // Carrega a cor/tema/layout do último branding salvo NESTE aparelho antes
  // do primeiro frame — sem isso, o app sempre nascia com a cor padrão e só
  // trocava pra cor real da empresa depois que `carregarBranding` (que
  // depende de autenticação + rede) terminava, um "flash" visível toda vez.
  final brandingProvider = BrandingProvider();
  await brandingProvider.carregarCachePrevio();

  runApp(MyApp(brandingProvider: brandingProvider));
}

class MyApp extends StatelessWidget {
  final BrandingProvider brandingProvider;

  const MyApp({super.key, required this.brandingProvider});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ProdutoProvider()),
        ChangeNotifierProvider(create: (_) => ClientProvider()),
        ChangeNotifierProvider(create: (_) => HistoricoVendasProvider()),
        ChangeNotifierProvider(create: (_) => CarrinhoProvider()),
        ChangeNotifierProvider.value(value: brandingProvider),
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => UsuarioProvider()),
        ChangeNotifierProvider(create: (_) => ZonaEntregaProvider()),
        ChangeNotifierProvider(create: (_) => ZonaEntrega99FoodProvider()),
        ChangeNotifierProvider(create: (_) => FornecedorProvider()),
        ChangeNotifierProvider(create: (_) => DespesaProvider()),
        ChangeNotifierProvider(create: (_) => PreferenciasProvider()),
        ChangeNotifierProvider(create: (_) => NotificacaoProvider()),
        ChangeNotifierProvider(create: (_) => EntradaProvider()),
        ChangeNotifierProvider(create: (_) => CupomProvider()),
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

