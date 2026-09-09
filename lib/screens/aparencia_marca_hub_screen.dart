import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import 'aparencia_screen.dart';
import 'kit_de_marca_screen.dart';

/// Reúne "Aparência" (cor/tema, dono+gerente) e "Kit de Marca"
/// (imagens/mascote, só dono) numa tela só — são as duas faces da
/// identidade visual da loja. Gerente não vê Kit de Marca (decisão do
/// usuário, ver KitDeMarcaScreen) — nesse caso cai direto na Aparência
/// sem TabBar nenhuma, já que 1 aba só seria redundante.
class AparenciaMarcaHubScreen extends StatelessWidget {
  const AparenciaMarcaHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDono = context.watch<AuthProvider>().isDono;

    if (!isDono) {
      return Scaffold(
        appBar: AppBar(title: const Text('Aparência e Marca')),
        body: const AparenciaScreen(),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Aparência e Marca'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Aparência'),
              Tab(text: 'Kit de Marca'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            AparenciaScreen(),
            KitDeMarcaScreen(),
          ],
        ),
      ),
    );
  }
}
