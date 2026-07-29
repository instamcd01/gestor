import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/notificacao.dart';
import '../providers/notificacao_provider.dart';

/// Tela de preferências de notificação da empresa (Configurações > Loja >
/// Notificações). Cada categoria liga/desliga in-app E push juntos — o
/// push só existe se a linha em `notificacoes` for criada, então desligar
/// aqui já corta os dois no banco (ver `notificacao_provider.dart`).
class ConfiguracaoNotificacoesScreen extends StatelessWidget {
  const ConfiguracaoNotificacoesScreen({super.key});

  Future<void> _salvarComFeedback(BuildContext context, Future<void> Function() acao) async {
    try {
      await acao();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível salvar: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificacaoProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Notificações')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            'Escolha quais eventos devem gerar notificação (na sininho do app e no celular).',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 16),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < categoriasNotificacaoDisponiveis.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  SwitchListTile(
                    title: Text(categoriasNotificacaoDisponiveis[i].titulo),
                    subtitle: Text(categoriasNotificacaoDisponiveis[i].descricao),
                    value: provider.habilitado(categoriasNotificacaoDisponiveis[i].chave),
                    onChanged: (valor) => _salvarComFeedback(
                      context,
                      () => provider.definirPreferencia(categoriasNotificacaoDisponiveis[i].chave, valor),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text('Histórico', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              title: const Text('Manter notificações lidas por'),
              subtitle: const Text('Depois desse prazo, as já lidas são apagadas automaticamente todo dia.'),
              trailing: DropdownButton<int>(
                value: provider.retencaoDias,
                items: const [7, 15, 30, 60, 90]
                    .map((dias) => DropdownMenuItem(value: dias, child: Text('$dias dias')))
                    .toList(),
                onChanged: (dias) {
                  if (dias == null) return;
                  _salvarComFeedback(context, () => provider.definirRetencaoDias(dias));
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
