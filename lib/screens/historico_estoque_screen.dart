import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/movimentacao_estoque.dart';
import '../repositories/produto_repository.dart';
import '../repositories/venda_repository.dart';
import 'venda_detalhes_screen.dart';

/// Extrato de estoque do produto: cada mudança de saldo com o porquê, quem
/// fez e o pedido/nota de origem. Os dados vêm de trigger no banco, então
/// aparece tudo — inclusive iFood, n8n, kit e granel. Histórico começa em
/// 01/10/2026 ("Início do histórico"); antes disso nada foi registrado.
class HistoricoEstoqueScreen extends StatefulWidget {
  final String produtoId;
  final String nomeProduto;

  const HistoricoEstoqueScreen({super.key, required this.produtoId, required this.nomeProduto});

  @override
  State<HistoricoEstoqueScreen> createState() => _HistoricoEstoqueScreenState();
}

class _HistoricoEstoqueScreenState extends State<HistoricoEstoqueScreen> {
  static final _formatoData = DateFormat('dd/MM/yy HH:mm');

  late Future<List<MovimentacaoEstoque>> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = ProdutoRepository().listarMovimentacoesEstoque(widget.produtoId);
  }

  Future<void> _recarregar() async {
    final futuro = ProdutoRepository().listarMovimentacoesEstoque(widget.produtoId);
    setState(() => _futuro = futuro);
    await futuro;
  }

  Future<void> _abrirReferencia(MovimentacaoEstoque m) async {
    if (m.referenciaTipo != 'pedido' || m.referenciaId == null) return;
    try {
      final venda = await VendaRepository().buscarPorId(m.referenciaId!);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => VendaDetalhesScreen(venda: venda)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível abrir o pedido: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Histórico de estoque')),
      body: FutureBuilder<List<MovimentacaoEstoque>>(
        future: _futuro,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Erro ao carregar histórico: ${snapshot.error}', textAlign: TextAlign.center),
              ),
            );
          }
          final movimentacoes = snapshot.data ?? [];
          return RefreshIndicator(
            onRefresh: _recarregar,
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: movimentacoes.length + 1,
              separatorBuilder: (_, i) => i == 0 ? const SizedBox.shrink() : const Divider(height: 1),
              itemBuilder: (context, i) {
                if (i == 0) return _cabecalho(context, movimentacoes);
                return _item(context, movimentacoes[i - 1]);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _cabecalho(BuildContext context, List<MovimentacaoEstoque> movimentacoes) {
    final saldo = movimentacoes.isEmpty ? null : movimentacoes.first.quantidadeNova;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.nomeProduto, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          if (saldo != null) ...[
            const SizedBox(height: 4),
            Text('Saldo atual no sistema: $saldo'),
          ],
          if (movimentacoes.isEmpty) ...[
            const SizedBox(height: 16),
            const Text('Nenhuma movimentação registrada ainda.'),
          ],
        ],
      ),
    );
  }

  Widget _item(BuildContext context, MovimentacaoEstoque m) {
    final colorScheme = Theme.of(context).colorScheme;
    final desconhecido = m.tipo == 'desconhecido';
    final marco = m.tipo == 'inicio_historico';
    final corDelta = m.delta > 0 ? Colors.green.shade700 : (m.delta < 0 ? colorScheme.error : colorScheme.onSurfaceVariant);

    final detalhes = <String>[
      if (m.referenciaDescricao != null) m.referenciaDescricao!,
      if (m.canal != null) _rotuloCanal(m.canal!),
      if (m.sincronizacao == 'kit') 'reflexo de kit',
      if (m.sincronizacao == 'granel') 'reflexo do granel (pai/filho)',
      if (m.motivo != null) m.tipo == 'ajuste_manual' ? rotuloMotivoAjusteEstoque(m.motivo) : m.motivo!,
      if (m.observacao != null) m.observacao!,
      m.usuarioNome ?? _rotuloOrigemTecnica(m.origemTecnica),
    ].where((t) => t.isNotEmpty).toList();

    return ListTile(
      onTap: m.referenciaTipo == 'pedido' ? () => _abrirReferencia(m) : null,
      leading: CircleAvatar(
        backgroundColor: desconhecido ? colorScheme.errorContainer : colorScheme.surfaceContainerHighest,
        child: Icon(_icone(m), size: 20, color: desconhecido ? colorScheme.onErrorContainer : colorScheme.onSurfaceVariant),
      ),
      title: Text(m.tipoLegivel, style: TextStyle(fontWeight: FontWeight.w600, color: desconhecido ? colorScheme.error : null)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_formatoData.format(m.criadoEm)),
          if (detalhes.isNotEmpty) Text(detalhes.join(' • ')),
          if (desconhecido && m.consulta != null)
            Text(m.consulta!, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
        ],
      ),
      isThreeLine: detalhes.isNotEmpty || desconhecido,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!marco)
            Text('${m.delta > 0 ? '+' : ''}${m.delta}',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: corDelta)),
          Text(marco ? 'saldo ${m.quantidadeNova}' : '${m.quantidadeAnterior} → ${m.quantidadeNova}',
              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  IconData _icone(MovimentacaoEstoque m) => switch (m.tipo) {
        'venda' || 'ajuste_pedido_ifood' => Icons.shopping_bag_outlined,
        'cancelamento_venda' => Icons.undo,
        'entrada_nota' || 'entrada_manual' => Icons.local_shipping_outlined,
        'ajuste_manual' => Icons.edit_note,
        'inicio_historico' => Icons.flag_outlined,
        'desconhecido' => Icons.help_outline,
        _ => Icons.sync,
      };

  String _rotuloCanal(String canal) => switch (canal) {
        'ifood' => 'iFood',
        'site' => 'Site',
        'app' => 'App',
        'whatsapp' => 'WhatsApp',
        'loja' => 'Loja',
        _ => canal,
      };

  /// Sem usuário logado = rotina automática (n8n/edge function com chave de
  /// serviço, cron, trigger).
  String _rotuloOrigemTecnica(String? origem) => switch (origem) {
        null => '',
        'service_role' => 'automação (n8n/servidor)',
        'authenticated' => 'usuário do app',
        _ => 'sistema',
      };
}
