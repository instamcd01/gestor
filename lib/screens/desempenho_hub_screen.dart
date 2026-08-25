import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../widgets/menu_secao.dart';
import 'avaliacoes_disputas_screen.dart';
import 'desempenho_equipe_screen.dart';
import 'estatisticas_screen.dart';
import 'meu_desempenho_screen.dart';

/// Agrupa as telas de desempenho/métricas que antes ficavam soltas no menu
/// principal (Meu Desempenho, Desempenho da Equipe, Estatísticas,
/// Avaliações) — mesmo raciocínio de ClientesHubScreen. "Meu Desempenho"
/// continua sem restrição de papel; os outros 3 seguem exigindo
/// dono/gerente, igual já exigiam soltos no menu principal.
class DesempenhoHubScreen extends StatelessWidget {
  const DesempenhoHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final podeVerGerencial = context.watch<AuthProvider>().podeVerFinancas;

    return Scaffold(
      appBar: AppBar(title: const Text('Desempenho')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          MenuSecao(
            titulo: 'Métricas',
            itens: [
              MenuItem('Meu Desempenho', Icons.insights_outlined, const MeuDesempenhoScreen()),
              if (podeVerGerencial)
                MenuItem('Desempenho da Equipe', Icons.groups_outlined, const DesempenhoEquipeScreen()),
              if (podeVerGerencial)
                MenuItem('Estatísticas', Icons.area_chart, const EstatisticasScreen()),
              if (podeVerGerencial)
                MenuItem('Avaliações', Icons.reviews_outlined, const AvaliacoesDisputasScreen()),
            ],
          ),
        ],
      ),
    );
  }
}
