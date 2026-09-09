import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import 'mercado_pago_conectar_screen.dart';
import 'opcoes_pagamento_screen.dart';

/// Reúne "Opções de Pagamento" (métodos aceitos no balcão, Pix, bandeiras,
/// parcelamento — dono+gerente) e "Pagamento Online" (conectar Mercado
/// Pago — só dono, credencial sensível) numa tela só — as duas faces de
/// "como a loja recebe". Mesma regra de gating de `AparenciaMarcaHubScreen`:
/// gerente só vê "Opções" sem TabBar nenhuma (1 aba só seria redundante).
class PagamentoHubScreen extends StatelessWidget {
  const PagamentoHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDono = context.watch<AuthProvider>().isDono;

    if (!isDono) {
      return Scaffold(
        appBar: AppBar(title: const Text('Opções de Pagamento')),
        body: const OpcoesPagamentoScreen(),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pagamento'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Opções'),
              Tab(text: 'Pagamento Online'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            OpcoesPagamentoScreen(),
            MercadoPagoConectarScreen(),
          ],
        ),
      ),
    );
  }
}
