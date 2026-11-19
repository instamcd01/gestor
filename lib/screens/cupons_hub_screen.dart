import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import 'config_cupom_automatico_screen.dart';
import 'cupons_screen.dart';
import 'indicacoes_screen.dart';
import 'metricas_cupons_screen.dart';

/// Reúne as 3 telas que eram itens de menu separados (Cupons de Desconto,
/// Cupom Automático, Métricas de Cupons) numa tela só com abas — todas
/// sobre o mesmo recurso, só ângulos diferentes (gerenciar / regra
/// automática / acompanhar). Cada aba mantém seu próprio Scaffold interno
/// (só a aba "Cupons" tem FAB) — mesmo padrão de FAB por aba já usado no
/// resto do app.
class CuponsHubScreen extends StatelessWidget {
  const CuponsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Indicações mostra telefone de cliente e PetCash pago: só dono/gerente
    // (a RPC relatorio_indicacoes também recusa os outros papéis).
    final verIndicacoes = context.watch<AuthProvider>().podeVerFinancas;
    return DefaultTabController(
      length: verIndicacoes ? 4 : 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Cupons'),
          bottom: TabBar(
            isScrollable: verIndicacoes,
            tabs: [
              const Tab(text: 'Cupons'),
              const Tab(text: 'Automático'),
              const Tab(text: 'Métricas'),
              if (verIndicacoes) const Tab(text: 'Indicações'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            const CuponsScreen(),
            const ConfigCupomAutomaticoScreen(),
            const MetricasCuponsScreen(),
            if (verIndicacoes) const IndicacoesScreen(),
          ],
        ),
      ),
    );
  }
}
