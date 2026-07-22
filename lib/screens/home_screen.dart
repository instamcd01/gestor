import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/modelo_visual.dart';
import '../providers/branding_provider.dart';
import 'drawer_home_shell.dart';
import 'sidebar_home_shell.dart';

/// Escolhe qual shell de navegação mostrar de acordo com o layout definido
/// pelo modelo visual escolhido pela empresa (ver `BrandingProvider` e a
/// tabela `modelos_visuais`). Cada modelo pode trazer um layout diferente
/// sem precisar mudar nenhuma outra parte do app — quem referencia
/// `HomeScreen()` (auth_gate.dart, main.dart) não precisa saber disso.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final layout = context.watch<BrandingProvider>().layoutNavegacao;

    return switch (layout) {
      LayoutNavegacao.sidebar => const SidebarHomeShell(),
      LayoutNavegacao.drawer => const DrawerHomeShell(),
    };
  }
}
