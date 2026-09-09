import 'package:flutter/material.dart';

import 'config_cupom_automatico_screen.dart';
import 'cupons_screen.dart';
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
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Cupons'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Cupons'),
              Tab(text: 'Automático'),
              Tab(text: 'Métricas'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            CuponsScreen(),
            ConfigCupomAutomaticoScreen(),
            MetricasCuponsScreen(),
          ],
        ),
      ),
    );
  }
}
