import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/branding_provider.dart';
import '../utils/app_destinos.dart';
import 'inicio_screen.dart';
import 'meu_perfil_screen.dart';

/// Shell de navegação por Drawer + painel inicial — layout do modelo
/// "Clássico". Usa cor/tipografia/forma do tema atual (`Theme.of(context)`)
/// em vez de cores fixas, e a lista compartilhada de `app_destinos.dart`.
class DrawerHomeShell extends StatefulWidget {
  const DrawerHomeShell({super.key});

  @override
  State<DrawerHomeShell> createState() => _DrawerHomeShellState();
}

class _DrawerHomeShellState extends State<DrawerHomeShell> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final branding = context.watch<BrandingProvider>();
    // Duas posições distintas de propósito: a pessoa pode querer, por
    // exemplo, só o nome no topo da tela inicial e o mascote no menu —
    // usar a mesma posição pras duas (como era antes) forçava a mesma
    // imagem nos dois lugares mesmo quando o usuário configurava diferente.
    final logoTopo = branding.urlParaPosicao('app_inicio');
    final logoMenu = branding.urlParaPosicao('app_drawer');
    final nomeEmpresa = branding.nomeEmpresa;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: logoTopo == null
            ? Text(nomeEmpresa)
            : Image.network(logoTopo, height: 44, fit: BoxFit.contain),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
      ),
      drawer: _buildDrawer(context, colorScheme, logoMenu),
      body: const InicioScreen(mostrarAppBar: false),
    );
  }

  Widget _buildDrawer(BuildContext context, ColorScheme colorScheme, String? logoUrl) {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.75,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          SizedBox(
            // Altura maior que o padrão do DrawerHeader (160) — logo
            // quadrada (ex: "logo completa") só cresce junto da altura
            // disponível, já que o encaixe é por `height` (contain);
            // ficava pequena demais com o tamanho antigo (64).
            height: 190,
            child: DrawerHeader(
              decoration: BoxDecoration(color: colorScheme.primary),
              child: Center(child: _logoOuIcone(logoUrl, colorScheme, tamanho: 130)),
            ),
          ),
          ...destinosParaPapel(context.watch<AuthProvider>().papel).map((destino) => ListTile(
                leading: destino.construirIcone(context, color: colorScheme.primary),
                title: Text(destino.titulo),
                onTap: () {
                  Navigator.pop(context); // fecha o drawer antes de navegar
                  Navigator.push(context, MaterialPageRoute(builder: destino.builder));
                },
              )),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Meu Perfil'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const MeuPerfilScreen()));
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sair'),
            onTap: () {
              Navigator.pop(context);
              _confirmarSaida(context);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _confirmarSaida(BuildContext context) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sair'),
        content: const Text('Tem certeza que deseja sair da sua conta?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (confirmou == true && context.mounted) context.read<AuthProvider>().sair();
  }

  // `contain` (não `cover`) + só altura fixa, sem largura fixa: logo raramente
  // é quadrada (ex: nome da loja em imagem, bem mais larga que alta) —
  // forçar num quadrado com `cover` cortava as bordas. `ConstrainedBox` evita
  // uma imagem muito larga estourar o espaço disponível.
  Widget _logoOuIcone(String? logoUrl, ColorScheme colorScheme, {required double tamanho}) {
    if (logoUrl == null || logoUrl.isEmpty) {
      return Icon(Icons.pets, size: tamanho, color: colorScheme.onPrimary);
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: tamanho * 3),
      child: Image.network(
        logoUrl,
        height: tamanho,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Icon(Icons.pets, size: tamanho, color: colorScheme.onPrimary),
      ),
    );
  }
}
