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
            'Escolha quais eventos devem gerar notificação (na sininho do app e no celular) — toque num '
            'evento pra escolher também se ele toca som e/ou vibra quando chega com o app aberto na tela.',
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
                  _CategoriaExpansionTile(
                    categoria: categoriasNotificacaoDisponiveis[i],
                    provider: provider,
                    onSalvar: (acao) => _salvarComFeedback(context, acao),
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

/// Uma categoria da lista — expande pra mostrar Som/Vibração dela. Ficam
/// desabilitados (cinza) quando a categoria em si tá desligada, porque
/// nesse caso nenhuma notificação é gerada pra ter som/vibração de nada.
class _CategoriaExpansionTile extends StatelessWidget {
  final CategoriaNotificacao categoria;
  final NotificacaoProvider provider;
  final void Function(Future<void> Function()) onSalvar;

  const _CategoriaExpansionTile({
    required this.categoria,
    required this.provider,
    required this.onSalvar,
  });

  @override
  Widget build(BuildContext context) {
    final categoriaHabilitada = provider.habilitado(categoria.chave);

    return ExpansionTile(
      title: Text(categoria.titulo),
      subtitle: Text(categoria.descricao),
      trailing: Switch(
        value: categoriaHabilitada,
        onChanged: (valor) => onSalvar(() => provider.definirPreferencia(categoria.chave, valor)),
      ),
      childrenPadding: const EdgeInsets.only(bottom: 4),
      children: [
        SwitchListTile(
          dense: true,
          title: const Text('Som'),
          value: categoriaHabilitada && provider.alertaHabilitado(categoria.chave, PreferenciaAlerta.som),
          onChanged: !categoriaHabilitada
              ? null
              : (valor) => onSalvar(
                    () => provider.definirPreferencia(
                      PreferenciaAlerta.chave(categoria.chave, PreferenciaAlerta.som),
                      valor,
                    ),
                  ),
        ),
        SwitchListTile(
          dense: true,
          title: const Text('Vibração'),
          value: categoriaHabilitada && provider.alertaHabilitado(categoria.chave, PreferenciaAlerta.vibracao),
          onChanged: !categoriaHabilitada
              ? null
              : (valor) => onSalvar(
                    () => provider.definirPreferencia(
                      PreferenciaAlerta.chave(categoria.chave, PreferenciaAlerta.vibracao),
                      valor,
                    ),
                  ),
        ),
      ],
    );
  }
}
