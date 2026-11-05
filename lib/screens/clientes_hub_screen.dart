import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/modulo.dart';
import '../providers/auth_provider.dart';
import '../widgets/menu_secao.dart';
import 'campanhas_ativacao_screen.dart';
import 'cliente_screen.dart';
import 'clientes_pc.dart';
import 'push_campanha_screen.dart';
import 'sugestoes_produto_cliente_screen.dart';
import 'vinculos_clientes_screen.dart';

/// Telas de relacionamento além da própria lista de clientes. Exigem
/// dono/gerente, igual já exigiam soltas no menu principal. O filtro por
/// módulo fica com quem mostra (`MenuSecao` no celular, menu "Relacionamento"
/// no PC).
List<MenuItem> itensRelacionamento(bool podeVerGerencial) => [
      if (podeVerGerencial)
        MenuItem('Campanhas de Ativação', Icons.campaign_outlined, const CampanhasAtivacaoScreen(), modulos: [Modulos.marketing]),
      if (podeVerGerencial)
        MenuItem('Campanha de Push', Icons.notifications_active_outlined, const PushCampanhaScreen(), modulos: [Modulos.lojaOnline]),
      if (podeVerGerencial)
        MenuItem('Vínculos de Clientes', Icons.link, const VinculosClientesScreen()),
      if (podeVerGerencial)
        MenuItem('Sugestões de Clientes', Icons.search_off, const SugestoesProdutoClienteScreen(), modulos: [Modulos.marketing]),
    ];

/// Agrupa as telas de relacionamento com cliente que antes ficavam soltas
/// no menu principal (Clientes, Campanhas, Vínculos, Sugestões) — reduz o
/// menu de 1º nível sem tirar nada de lugar, só junta o que já era um
/// tema só. "Clientes" em si continua sem restrição de papel (vendedor
/// também acessa). No PC (≥ 1200 px) vai direto pra tabela, com esses itens
/// no menu "Relacionamento" do topo.
class ClientesHubScreen extends StatelessWidget {
  const ClientesHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= ClientesPc.larguraPc) return const ClientesPc();

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
              ...itensRelacionamento(podeVerGerencial),
            ],
          ),
        ],
      ),
    );
  }
}
