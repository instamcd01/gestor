import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../widgets/menu_secao.dart';
import 'campanhas_ativacao_screen.dart';
import 'cliente_screen.dart';
import 'sugestoes_produto_cliente_screen.dart';
import 'vinculos_clientes_screen.dart';

/// Agrupa as telas de relacionamento com cliente que antes ficavam soltas
/// no menu principal (Clientes, Campanhas, Vínculos, Sugestões) — reduz o
/// menu de 1º nível sem tirar nada de lugar, só junta o que já era um
/// tema só. "Clientes" em si continua sem restrição de papel (vendedor
/// também acessa); os outros 3 itens seguem exigindo dono/gerente, igual
/// já exigiam soltos no menu principal.
class ClientesHubScreen extends StatelessWidget {
  const ClientesHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final podeVerGerencial = context.watch<AuthProvider>().podeVerFinancas;

    return Scaffold(
      appBar: AppBar(title: const Text('Clientes')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          MenuSecao(
            titulo: 'Relacionamento',
            itens: [
              MenuItem('Clientes', Icons.person_outline, ClientesScreen()),
              if (podeVerGerencial)
                MenuItem('Campanhas de Ativação', Icons.campaign_outlined, const CampanhasAtivacaoScreen()),
              if (podeVerGerencial)
                MenuItem('Vínculos de Clientes', Icons.link, const VinculosClientesScreen()),
              if (podeVerGerencial)
                MenuItem('Sugestões de Clientes', Icons.search_off, const SugestoesProdutoClienteScreen()),
            ],
          ),
        ],
      ),
    );
  }
}
