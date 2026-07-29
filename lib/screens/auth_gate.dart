import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/branding_provider.dart';
import '../providers/produto_provider.dart';
import '../providers/cliente_provider.dart';
import '../providers/historico_vendas_provider.dart';
import '../providers/usuario_provider.dart';
import '../providers/zona_entrega_provider.dart';
import '../providers/fornecedor_provider.dart';
import '../providers/despesa_provider.dart';
import '../providers/notificacao_provider.dart';
import '../providers/entrada_provider.dart';
import '../services/push_notification_service.dart';
import 'auth/login_screen.dart';
import 'auth/onboarding_empresa_screen.dart';
import 'home_screen.dart';

/// Decide o que mostrar de acordo com o estado de autenticação:
/// sem login → LoginScreen; logado sem empresa → onboarding;
/// logado com empresa → app principal (já com branding/produtos carregados
/// pra essa empresa).
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _ultimaEmpresaCarregada;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    if (auth.carregando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!auth.estaLogado) {
      return const LoginScreen();
    }

    if (auth.precisaOnboarding) {
      return const OnboardingEmpresaScreen();
    }

    final empresaId = auth.empresaId;
    if (empresaId != null && empresaId != _ultimaEmpresaCarregada) {
      _ultimaEmpresaCarregada = empresaId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<BrandingProvider>().carregarBranding(empresaId);
        context.read<ProdutoProvider>().definirEmpresa(empresaId);
        context.read<ClientProvider>().definirEmpresa(empresaId);
        context.read<HistoricoVendasProvider>().definirEmpresa(empresaId);
        context.read<UsuarioProvider>().definirEmpresa(empresaId);
        context.read<FornecedorProvider>().definirEmpresa(empresaId);
        context.read<DespesaProvider>().definirEmpresa(empresaId);
        context.read<EntradaProvider>().definirEmpresa(empresaId);
        context.read<ZonaEntregaProvider>()
          ..definirEmpresa(empresaId)
          ..carregarZonas();
        context.read<NotificacaoProvider>()
          ..definirEmpresa(empresaId)
          ..carregar();
        PushNotificationService.inicializar();
      });
    }

    return HomeScreen();
  }
}
