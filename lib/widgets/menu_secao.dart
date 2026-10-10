import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/modulo_provider.dart';

/// Um item navegável dentro de uma [MenuSecao] — título, ícone e a tela
/// que abre ao tocar. [modulos]: módulos (ver `Modulos`) que liberam o
/// item — null é base, toda loja tem; com mais de um, basta qualquer um.
class MenuItem {
  final String titulo;
  final IconData icone;
  final Widget tela;
  final List<String>? modulos;

  const MenuItem(this.titulo, this.icone, this.tela, {this.modulos});
}

/// Agrupa itens de menu relacionados sob um rótulo, num único card com
/// divisores — usado nas telas "índice" do app (Configurações, Finanças)
/// em vez de cada uma desenhar seu próprio estilo de lista de navegação.
class MenuSecao extends StatelessWidget {
  final String titulo;
  final List<MenuItem> itens;

  const MenuSecao({super.key, required this.titulo, required this.itens});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final moduloProvider = context.watch<ModuloProvider>();
    final itens = this
        .itens
        .where((item) => item.modulos == null || moduloProvider.algumAtivo(item.modulos!))
        .toList();
    // Seção inteira de módulos não instalados some, em vez de um card vazio.
    if (itens.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Text(
            titulo,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700, color: colorScheme.primary),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < itens.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                ListTile(
                  leading: Icon(itens[i].icone, color: colorScheme.primary),
                  title: Text(itens[i].titulo),
                  trailing: Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => itens[i].tela),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
