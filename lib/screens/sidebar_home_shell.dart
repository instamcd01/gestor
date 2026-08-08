import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/branding_provider.dart';
import '../providers/preferencias_provider.dart';
import '../utils/app_destinos.dart';
import 'drawer_home_shell.dart';
import 'meu_perfil_screen.dart';

/// Shell de navegação por barra lateral fixa — layout do modelo "Moderno".
/// Em telas estreitas (celular, < 600dp) cai pro mesmo conteúdo do
/// DrawerHomeShell — um NavigationRail permanente não cabe direito num
/// celular — A MENOS que o usuário tenha ligado a preferência "barra lateral
/// sempre visível" (Configurações > Aparência), aí a barra (só ícones) fica
/// fixa em qualquer largura, ver `PreferenciasProvider.barraLateralFixa`.
/// Acima de 600dp (tablet/desktop — o app também roda no Windows), sempre
/// mostra a barra lateral de verdade, extended (com texto) só a partir de
/// 900dp — a menos que a preferência force o modo ícone-só sempre.
///
/// A barra fica sempre visível enquanto o usuário navega entre os destinos
/// de nível 1 (Início, Vender, Pedidos, ...), via `IndexedStack` — isso
/// mantém o estado de cada seção (busca, rolagem) ao ir e voltar entre elas.
/// Uma tela de detalhe/cadastro empurrada por cima (ex: editar produto) cobre
/// a tela toda, barra incluída, como qualquer outra rota do app — não é um
/// caso especial tratado aqui.
class SidebarHomeShell extends StatefulWidget {
  const SidebarHomeShell({super.key});

  @override
  State<SidebarHomeShell> createState() => _SidebarHomeShellState();
}

class _SidebarHomeShellState extends State<SidebarHomeShell> {
  int _indiceSelecionado = 0;

  @override
  void initState() {
    super.initState();
    Provider.of<PreferenciasProvider>(context, listen: false).carregar();
  }

  @override
  Widget build(BuildContext context) {
    final barraSempreFixa = context.watch<PreferenciasProvider>().barraLateralFixa;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600 && !barraSempreFixa) {
          return const DrawerHomeShell();
        }
        final extended = !barraSempreFixa && constraints.maxWidth >= 900;
        return _buildLayoutLargo(context, extended: extended);
      },
    );
  }

  Widget _buildLayoutLargo(BuildContext context, {required bool extended}) {
    final colorScheme = Theme.of(context).colorScheme;
    final logoUrl = context.watch<BrandingProvider>().urlParaPosicao('app_sidebar');
    final destinos = destinosParaPapel(context.watch<AuthProvider>().papel);
    // Defensivo: se o papel mudou (ex: dono acabou de rebaixar o próprio
    // usuário de teste) e a lista filtrada ficou mais curta que o índice
    // selecionado antes, volta pro primeiro destino em vez de estourar.
    final indiceSeguro = _indiceSelecionado < destinos.length ? _indiceSelecionado : 0;

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            extended: extended,
            selectedIndex: indiceSeguro,
            // Sem isso, o NavigationRail NÃO rola quando a lista de destinos
            // não cabe na altura da tela (padrão do Flutter é false) — em
            // celular com tela mais baixa, com 12 destinos + avatar fixo no
            // rodapé, isso estourava (RenderFlex overflow).
            scrollable: true,
            // Centralizado (em vez do padrão -1.0 = topo) porque a lista de
            // destinos raramente ocupa a altura toda da tela — alinhado ao
            // topo, sobrava uma faixa vazia grande embaixo que parecia bug.
            groupAlignment: 0.0,
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: _logoOuIcone(logoUrl, colorScheme, tamanho: 32),
            ),
            // Fixo no rodapé (independente do groupAlignment acima) — usa o
            // espaço que sobraria vazio pra algo útil (conta/sair) em vez de
            // só decoração.
            trailing: _rodapeConta(context),
            trailingAtBottom: true,
            onDestinationSelected: (index) => setState(() => _indiceSelecionado = index),
            destinations: destinos
                .map((destino) => NavigationRailDestination(
                      icon: destino.construirIcone(context),
                      label: Text(destino.titulo),
                      // Espaçamento extra entre os ícones — sem isso ficavam
                      // muito colados um no outro, mesmo depois de centralizar
                      // o grupo (groupAlignment acima).
                      padding: const EdgeInsets.symmetric(vertical: 8),
                    ))
                .toList(),
          ),
          const VerticalDivider(width: 1, thickness: 1),
          Expanded(
            child: IndexedStack(
              index: indiceSeguro,
              children: [
                for (final destino in destinos) destino.builder(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rodapeConta(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final email = context.watch<AuthProvider>().usuarioAtual?.email ?? '';
    final inicial = email.isNotEmpty ? email[0].toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: PopupMenuButton<String>(
        tooltip: email.isEmpty ? 'Conta' : email,
        onSelected: (valor) {
          if (valor == 'sair') {
            _confirmarSaida(context);
          } else if (valor == 'perfil') {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const MeuPerfilScreen()));
          }
        },
        itemBuilder: (context) => [
          if (email.isNotEmpty)
            PopupMenuItem<String>(
              enabled: false,
              child: Text(email, style: Theme.of(context).textTheme.bodySmall),
            ),
          const PopupMenuItem<String>(
            value: 'perfil',
            child: Row(children: [Icon(Icons.person_outline, size: 18), SizedBox(width: 8), Text('Meu Perfil')]),
          ),
          const PopupMenuItem<String>(
            value: 'sair',
            child: Row(children: [Icon(Icons.logout, size: 18), SizedBox(width: 8), Text('Sair')]),
          ),
        ],
        child: CircleAvatar(
          radius: 18,
          backgroundColor: colorScheme.primaryContainer,
          child: Text(inicial, style: TextStyle(color: colorScheme.onPrimaryContainer, fontWeight: FontWeight.w700)),
        ),
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

  // `contain` (não `cover`) + só altura fixa — mesma correção de
  // `drawer_home_shell.dart` (logo raramente é quadrada, `cover` cortava
  // as bordas de qualquer imagem mais larga que alta).
  Widget _logoOuIcone(String? logoUrl, ColorScheme colorScheme, {required double tamanho}) {
    if (logoUrl == null || logoUrl.isEmpty) {
      return Icon(Icons.pets, size: tamanho, color: colorScheme.primary);
    }
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: tamanho * 3),
      child: Image.network(
        logoUrl,
        height: tamanho,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => Icon(Icons.pets, size: tamanho, color: colorScheme.primary),
      ),
    );
  }
}
