import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/produto_provider.dart';
import '../repositories/historico_precos_repository.dart';

/// Toda mudança de preço do produto (loja, promocional, custo e cada
/// marketplace), com botão pra voltar ao valor anterior. Começa em
/// 02/10/2026; os ajustes de iFood da auditoria desse dia foram lançados
/// retroativamente.
class HistoricoPrecosScreen extends StatefulWidget {
  final String produtoId;
  final String nomeProduto;

  const HistoricoPrecosScreen({super.key, required this.produtoId, required this.nomeProduto});

  @override
  State<HistoricoPrecosScreen> createState() => _HistoricoPrecosScreenState();
}

class _HistoricoPrecosScreenState extends State<HistoricoPrecosScreen> {
  static final _formatoData = DateFormat('dd/MM/yy HH:mm');
  static final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  final _repo = HistoricoPrecosRepository();
  late Future<List<AlteracaoPreco>> _futuro;
  bool _revertendo = false;

  @override
  void initState() {
    super.initState();
    _futuro = _repo.listar(widget.produtoId);
  }

  Future<void> _recarregar() async {
    final futuro = _repo.listar(widget.produtoId);
    setState(() => _futuro = futuro);
    await futuro;
  }

  String _valor(double? v) => v == null ? 'sem valor' : _moeda.format(v);

  String _origem(String? origem) => switch (origem) {
        'auditoria_ifood' => 'Auditoria de preços iFood',
        'reversao' => 'Reversão',
        null || 'manual' => 'Alteração manual',
        _ => origem,
      };

  Future<void> _reverter(AlteracaoPreco a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reverter preço?'),
        content: Text('${a.rotuloCampo} volta de ${_valor(a.valorNovo)} para ${_valor(a.valorAntigo)}.'
            '${a.campo == 'preco_canal' ? '\n\nO novo valor é enviado pro ${a.marketplace ?? 'marketplace'} pela sincronização.' : ''}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reverter')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _revertendo = true);
    try {
      await _repo.reverter(a.id);
      if (!mounted) return;
      await context.read<ProdutoProvider>().recarregarProdutos([widget.produtoId]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${a.rotuloCampo} voltou para ${_valor(a.valorAntigo)}.')),
      );
      await _recarregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível reverter: $e')));
    } finally {
      if (mounted) setState(() => _revertendo = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Histórico de preços')),
      body: FutureBuilder<List<AlteracaoPreco>>(
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
          final alteracoes = snapshot.data ?? [];
          return RefreshIndicator(
            onRefresh: _recarregar,
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: alteracoes.length + 1,
              separatorBuilder: (_, i) => i == 0 ? const SizedBox.shrink() : const Divider(height: 1),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.nomeProduto, style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        alteracoes.isEmpty
                            ? 'Nenhuma alteração de preço registrada (o histórico começa em 02/10/2026).'
                            : 'Toda mudança de preço da loja, promocional, custo e marketplaces. '
                                'O histórico começa em 02/10/2026.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ]),
                  );
                }
                final a = alteracoes[i - 1];
                final subiu = (a.valorNovo ?? 0) > (a.valorAntigo ?? 0);
                return ListTile(
                  leading: Icon(
                    subiu ? Icons.arrow_upward : Icons.arrow_downward,
                    color: subiu ? Colors.orange : Theme.of(context).colorScheme.primary,
                  ),
                  title: Text('${a.rotuloCampo}: ${_valor(a.valorAntigo)} → ${_valor(a.valorNovo)}'),
                  subtitle: Text('${_formatoData.format(a.alteradoEm)} • ${_origem(a.origem)}'),
                  trailing: a.podeReverter
                      ? IconButton(
                          tooltip: 'Voltar para ${_valor(a.valorAntigo)}',
                          icon: const Icon(Icons.undo),
                          onPressed: _revertendo ? null : () => _reverter(a),
                        )
                      : null,
                );
              },
            ),
          );
        },
      ),
    );
  }
}
