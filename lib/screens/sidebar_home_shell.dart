import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/branding_provider.dart';
import '../utils/app_destinos.dart';
import 'drawer_home_shell.dart';

/// Shell de navegação por barra lateral fixa — layout do modelo "Moderno".
/// Em telas estreitas (celular, < 600dp) cai pro mesmo conteúdo do
/// DrawerHomeShell — um NavigationRail permanente não cabe direito num
/// celular. Acima disso (tablet/desktop — o app também roda no Windows),
/// mostra a barra lateral de verdade.
///
/// A barra fica sempre visível enquanto o usuário navega entre seções —
/// diferente da versão anterior, que empilhava cada seção como uma tela
/// cheia por cima (escondendo a barra). Cada destino já é o próprio
/// `Scaffold` com seu AppBar (ex: "Produtos", "Vender"); aqui só trocamos
/// qual deles ocupa o espaço ao lado da barra, via `IndexedStack` — isso
/// também mantém o estado de cada seção (busca, rolagem) ao ir e voltar
/// entre elas, em vez de recriar tudo do zero a cada troca.
class SidebarHomeShell extends StatefulWidget {
  const SidebarHomeShell({super.key});

  @override
  State<SidebarHomeShell> createState() => _SidebarHomeShellState();
}

class _SidebarHomeShellState extends State<SidebarHomeShell> {
  int _indiceSelecionado = 0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return const DrawerHomeShell();
        }
        return _buildLayoutLargo(context, constraints.maxWidth);
      },
    );
  }

  Widget _buildLayoutLargo(BuildContext context, double largura) {
    final colorScheme = Theme.of(context).colorScheme;
    final logoUrl = context.watch<BrandingProvider>().logoUrl;

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: largura >= 900,
            selectedIndex: _indiceSelecionado,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: _logoOuIcone(logoUrl, colorScheme, tamanho: 32),
            ),
            onDestinationSelected: (index) => setState(() => _indiceSelecionado = index),
            destinations: appDestinos
                .map((destino) => NavigationRailDestination(
                      icon: Icon(destino.icone),
                      label: Text(destino.titulo),
                    ))
                .toList(),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: IndexedStack(
              index: _indiceSelecionado,
              children: [
                for (final destino in appDestinos) destino.builder(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _logoOuIcone(String? logoUrl, ColorScheme colorScheme, {required double tamanho}) {
    if (logoUrl == null || logoUrl.isEmpty) {
      return Icon(Icons.pets, size: tamanho, color: colorScheme.primary);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        logoUrl,
        width: tamanho,
        height: tamanho,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Icon(Icons.pets, size: tamanho, color: colorScheme.primary),
      ),
    );
  }
}
