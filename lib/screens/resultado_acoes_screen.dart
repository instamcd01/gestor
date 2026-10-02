import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/produto.dart';
import '../models/resultado_acao.dart';
import '../providers/produto_provider.dart';
import '../repositories/historico_precos_repository.dart';
import '../repositories/produto_repository.dart';

/// Resultado de cada ação feita no estoque parado (ajuste de preço,
/// promoção, aviso a clientes...): vendas depois x ritmo de antes, lucro e
/// botão de reverter o preço. Mostra também produto que já saiu da lista de
/// parados — que é justamente quando a ação funcionou.
class ResultadoAcoesScreen extends StatefulWidget {
  const ResultadoAcoesScreen({super.key});

  @override
  State<ResultadoAcoesScreen> createState() => _ResultadoAcoesScreenState();
}

class _ResultadoAcoesScreenState extends State<ResultadoAcoesScreen> {
  static final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  static final _data = DateFormat('dd/MM/yy');

  List<ResultadoAcao>? _itens;
  String? _erro;
  StatusResultado? _filtro;
  bool _revertendo = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _erro = null);
    try {
      final itens = await ProdutoRepository().listarResultadoAcoes();
      if (mounted) setState(() => _itens = itens);
    } catch (e) {
      if (mounted) setState(() => _erro = 'Erro ao carregar resultados: $e');
    }
  }

  Color _cor(StatusResultado s, ColorScheme c) => switch (s) {
        StatusResultado.funcionou => Colors.green.shade700,
        StatusResultado.semEfeito => c.error,
        StatusResultado.alterado => c.outline,
        StatusResultado.cedo || StatusResultado.igual => c.onSurfaceVariant,
      };

  Future<void> _reverter(ResultadoAcao r, Produto? produto) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Voltar ao preço anterior?'),
        content: Text('${produto?.nome ?? 'Produto'}\n\niFood volta de ${_moeda.format(r.precoNovo)} '
            'para ${_moeda.format(r.precoAntigo)}. O novo valor é enviado pro iFood pela sincronização.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reverter')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _revertendo = true);
    try {
      await HistoricoPrecosRepository().reverter(r.historicoId!);
      if (!mounted) return;
      await context.read<ProdutoProvider>().recarregarProdutos([r.produtoId]);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Preço do iFood voltou para ${_moeda.format(r.precoAntigo)}.')),
      );
      await _carregar();
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
      appBar: AppBar(title: const Text('Resultado das ações')),
      body: _erro != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_erro!)))
          : _itens == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(onRefresh: _carregar, child: _corpo(context, _itens!)),
    );
  }

  Widget _corpo(BuildContext context, List<ResultadoAcao> itens) {
    final cores = Theme.of(context).colorScheme;
    final porId = {for (final p in context.watch<ProdutoProvider>().produtos) if (p.id != null) p.id!: p};
    final contagem = <StatusResultado, int>{};
    for (final r in itens) {
      contagem[r.status] = (contagem[r.status] ?? 0) + 1;
    }
    final visiveis = itens.where((r) => _filtro == null || r.status == _filtro).toList();
    final produtosQueVenderam = itens.where((r) => r.vendasDepois > 0).map((r) => r.produtoId).toSet().length;
    final unidades = itens.fold<int>(0, (s, r) => s + r.vendasDepois);
    final lucro = itens.fold<double>(0, (s, r) => s + r.lucroDepois);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${itens.length} ação(ões) registradas', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text('$produtosQueVenderam produto(s) venderam depois da ação • $unidades unidade(s) • '
                    'lucro ${_moeda.format(lucro)}'),
                const SizedBox(height: 6),
                Text(
                  '"Funcionou" = vendeu bem acima do ritmo dos 90 dias antes da ação. '
                  '"Sem efeito" = 14 dias ou mais sem nenhuma venda.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ]),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(children: [
            ChoiceChip(
              label: Text('Todos (${itens.length})'),
              selected: _filtro == null,
              onSelected: (_) => setState(() => _filtro = null),
            ),
            for (final s in StatusResultado.values)
              if ((contagem[s] ?? 0) > 0) ...[
                const SizedBox(width: 6),
                ChoiceChip(
                  label: Text('${s.rotulo} (${contagem[s]})'),
                  selected: _filtro == s,
                  onSelected: (_) => setState(() => _filtro = s),
                ),
              ],
          ]),
        ),
        if (visiveis.isEmpty)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('Nenhuma ação com esse filtro.'))),
        for (final r in visiveis) _linha(context, r, porId[r.produtoId], cores),
      ],
    );
  }

  Widget _linha(BuildContext context, ResultadoAcao r, Produto? produto, ColorScheme cores) {
    final status = r.status;
    final antes = r.vendas90dAntes == 0
        ? 'antes: nenhuma venda em 90 dias'
        : 'antes: ${r.vendas90dAntes} em 90 dias (~${r.vendasEsperadas.toStringAsFixed(1)} no mesmo período)';
    final depois = 'depois: ${r.vendasDepois} em ${r.dias} dia(s)'
        '${r.vendasDepoisIfood > 0 ? ' (${r.vendasDepoisIfood} no iFood)' : ''}';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(produto?.nome ?? 'Produto removido', maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text('${r.acao} em ${_data.format(r.criadoEm)}'
                  '${r.ajusteDePreco && r.precoAntigo != null ? ': ${_moeda.format(r.precoAntigo)} → ${_moeda.format(r.precoNovo)}' : r.detalhe != null ? ' — ${r.detalhe}' : ''}'),
              Text('$depois • $antes', style: Theme.of(context).textTheme.bodySmall),
              if (r.vendasDepois > 0)
                Text('Lucro depois: ${_moeda.format(r.lucroDepois)}', style: Theme.of(context).textTheme.bodySmall),
              if (r.estoqueNoMomento != null && r.estoqueAtual != null)
                Text('Estoque: ${r.estoqueNoMomento} → ${r.estoqueAtual}', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 4),
              Text(status.rotulo, style: TextStyle(color: _cor(status, cores), fontWeight: FontWeight.w700)),
            ]),
          ),
          if (r.podeReverter)
            IconButton(
              tooltip: 'Voltar para ${_moeda.format(r.precoAntigo)}',
              icon: const Icon(Icons.undo),
              onPressed: _revertendo ? null : () => _reverter(r, produto),
            ),
        ]),
      ),
    );
  }
}
