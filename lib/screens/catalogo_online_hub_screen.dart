import 'package:flutter/material.dart';

import 'banners_loja_screen.dart';
import 'catalogo_online_screen.dart';

/// Reúne "Catálogo Online" (visibilidade, taxas, redes sociais do site) e
/// "Banners da Home" (carrossel da página inicial) numa tela só — as duas
/// configuram a mesma vitrine pública. Sem diferença de permissão entre
/// as duas (dono+gerente nas duas), então sempre 2 abas, sem gating.
class CatalogoOnlineHubScreen extends StatelessWidget {
  const CatalogoOnlineHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Catálogo Online'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Catálogo'),
              Tab(text: 'Banners'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            CatalogoOnlineScreen(),
            BannersLojaScreen(),
          ],
        ),
      ),
    );
  }
}
