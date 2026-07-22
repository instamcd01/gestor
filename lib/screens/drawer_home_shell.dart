import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/branding_provider.dart';
import '../utils/app_destinos.dart';

/// Shell de navegação por Drawer + grade de atalhos — layout do modelo
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
    final logoUrl = context.watch<BrandingProvider>().logoUrl;

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Gestor'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
      ),
      drawer: _buildDrawer(context, colorScheme, logoUrl),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              const SizedBox(height: 8),
              Text(
                'Bem-vindo ao seu Gestor!',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Gerencie seus produtos, pedidos e clientes de forma simples e eficiente.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.3,
                ),
                itemCount: appDestinos.length,
                itemBuilder: (context, index) => _buildButton(context, appDestinos[index], colorScheme),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildButton(BuildContext context, AppDestino destino, ColorScheme colorScheme) {
    return Card(
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: destino.builder)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(destino.icone, size: 26, color: colorScheme.primary),
              ),
              const SizedBox(height: 10),
              Text(
                destino.titulo,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: colorScheme.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context, ColorScheme colorScheme, String? logoUrl) {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.75,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: colorScheme.primary),
            child: Row(
              children: [
                _logoOuIcone(logoUrl, colorScheme, tamanho: 40),
                const SizedBox(width: 12),
                Text(
                  'Gestor',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: colorScheme.onPrimary, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          ...appDestinos.map((destino) => ListTile(
                leading: Icon(destino.icone, color: colorScheme.primary),
                title: Text(destino.titulo),
                onTap: () {
                  Navigator.pop(context); // fecha o drawer antes de navegar
                  Navigator.push(context, MaterialPageRoute(builder: destino.builder));
                },
              )),
        ],
      ),
    );
  }

  Widget _logoOuIcone(String? logoUrl, ColorScheme colorScheme, {required double tamanho}) {
    if (logoUrl == null || logoUrl.isEmpty) {
      return Icon(Icons.pets, size: tamanho, color: colorScheme.onPrimary);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        logoUrl,
        width: tamanho,
        height: tamanho,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Icon(Icons.pets, size: tamanho, color: colorScheme.onPrimary),
      ),
    );
  }
}
