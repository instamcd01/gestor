import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/notificacao.dart';
import '../providers/notificacao_provider.dart';
import '../services/navegacao_notificacao.dart';
import '../widgets/estado_erro_lista.dart';

(IconData, Color) _iconeECor(BuildContext context, String tipo) {
  final colorScheme = Theme.of(context).colorScheme;
  switch (tipo) {
    case TipoNotificacao.estoqueBaixo:
      return (Icons.warning_amber_outlined, Colors.orange);
    case TipoNotificacao.estoqueZerado:
      return (Icons.remove_shopping_cart_outlined, Colors.red);
    case TipoNotificacao.pedidoParado:
      return (Icons.hourglass_empty, Colors.orange);
    case TipoNotificacao.pedidoHoraSaidaEntrega:
      return (Icons.directions_run, Colors.orange);
    case TipoNotificacao.pedidoAtrasadoEntrega:
      return (Icons.local_shipping_outlined, Colors.red);
    case TipoNotificacao.despesaVencendo:
      return (Icons.event_outlined, Colors.orange);
    case TipoNotificacao.despesaVencida:
      return (Icons.event_busy_outlined, Colors.red);
    case TipoNotificacao.avaliacaoRecebida:
      return (Icons.star_outline, Colors.blue);
    case TipoNotificacao.disputaRecebida:
      return (Icons.gavel_outlined, Colors.amber);
    case TipoNotificacao.disputaPrazoVencendo:
      return (Icons.timer_outlined, Colors.red);
    case TipoNotificacao.syncFalhou:
      return (Icons.sync_problem_outlined, Colors.red);
    case TipoNotificacao.custoAlterado:
      return (Icons.price_change_outlined, Colors.orange);
    case TipoNotificacao.carrinhoAbandonado:
      return (Icons.shopping_cart_outlined, Colors.orange);
    case TipoNotificacao.clienteAtivoNoSite:
      return (Icons.person_search_outlined, Colors.blue);
    case TipoNotificacao.erroSistema:
      return (Icons.error_outline, Colors.red);
    case TipoNotificacao.nfePendente:
      return (Icons.receipt_long_outlined, Colors.blue);
    case TipoNotificacao.guiaRascunho:
      return (Icons.menu_book_outlined, Colors.blue);
    default:
      return (Icons.notifications_outlined, colorScheme.primary);
  }
}

class NotificacoesScreen extends StatefulWidget {
  const NotificacoesScreen({super.key});

  @override
  State<NotificacoesScreen> createState() => _NotificacoesScreenState();
}

class _NotificacoesScreenState extends State<NotificacoesScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<NotificacaoProvider>().carregar();
    });
  }

  Future<void> _abrir(Notificacao notificacao) async {
    await context.read<NotificacaoProvider>().marcarComoLida(notificacao.id);
    if (!mounted) return;
    await abrirNotificacao(tipo: notificacao.tipo, entidadeId: notificacao.entidadeId);
  }

  Future<void> _excluir(Notificacao notificacao) async {
    try {
      await context.read<NotificacaoProvider>().excluir(notificacao.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível excluir: $e')),
      );
    }
  }

  Future<void> _limparLidas(BuildContext context) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpar lidas'),
        content: const Text('Remove todas as notificações já lidas. As não lidas continuam na lista.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Limpar')),
        ],
      ),
    );
    if (confirmou != true || !context.mounted) return;
    await context.read<NotificacaoProvider>().excluirLidas();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<NotificacaoProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificações'),
        actions: [
          if (provider.temLidas)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Limpar lidas',
              onPressed: () => _limparLidas(context),
            ),
          if (provider.totalNaoLidas > 0)
            IconButton(
              icon: const Icon(Icons.done_all),
              tooltip: 'Marcar todas como lidas',
              onPressed: () => provider.marcarTodasComoLidas(),
            ),
        ],
      ),
      body: provider.carregando && provider.notificacoes.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : provider.erro != null && provider.notificacoes.isEmpty
              ? EstadoErroLista(mensagem: provider.erro!, onTentarNovamente: provider.carregar)
              : provider.notificacoes.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.notifications_none, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(height: 16),
                        Text(
                          'Nenhuma notificação por aqui.',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: provider.carregar,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: provider.notificacoes.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final n = provider.notificacoes[i];
                      final (icone, cor) = _iconeECor(context, n.tipo);
                      return Dismissible(
                        key: ValueKey(n.id),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Theme.of(context).colorScheme.error,
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.onError),
                        ),
                        onDismissed: (_) => _excluir(n),
                        child: ListTile(
                          leading: Icon(icone, color: cor),
                          title: Text(
                            n.titulo,
                            style: TextStyle(fontWeight: n.lida ? FontWeight.normal : FontWeight.bold),
                          ),
                          subtitle: Text(n.mensagem, maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                DateFormat('dd/MM HH:mm').format(n.createdAt.toLocal()),
                                style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                              if (!n.lida) ...[
                                const SizedBox(height: 4),
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
                                ),
                              ],
                            ],
                          ),
                          onTap: () => _abrir(n),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
