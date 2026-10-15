import 'package:flutter/material.dart';

import 'banners_loja_screen.dart';
import 'catalogo_online_screen.dart';
import 'endereco_loja_screen.dart';

/// Reúne "Catálogo Online" (visibilidade, taxas, redes sociais do site),
/// "Banners da Home" (carrossel da página inicial) e "Endereço" (subdomínio
/// e domínio próprio) numa tela só — todas configuram a mesma vitrine
/// pública. Sempre as mesmas abas, sem gating (dono+gerente); Endereço
/// controla sozinha o que só o dono pode mexer.
class CatalogoOnlineHubScreen extends StatelessWidget {
  const CatalogoOnlineHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Catálogo Online'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Catálogo'),
              Tab(text: 'Banners'),
              Tab(text: 'Endereço'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            CatalogoOnlineScreen(),
            BannersLojaScreen(),
            EnderecoLojaScreen(),
          ],
        ),
      ),
    );
  }
}
