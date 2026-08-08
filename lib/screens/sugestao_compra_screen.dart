import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/fornecedor.dart';
import '../models/pedido_compra.dart';
import '../models/produto.dart';
import '../models/produto_fornecedor.dart';
import '../providers/auth_provider.dart';
import '../providers/fornecedor_provider.dart';
import '../providers/pedido_compra_provider.dart';
import '../providers/produto_provider.dart';
import '../repositories/entrada_repository.dart';
import '../repositories/produto_fornecedor_repository.dart';
import '../widgets/busca_produto_sheet.dart';
import '../widgets/estado_erro_lista.dart';
import 'pedido_compra_detalhe_screen.dart';

String _formatarDataCurta(DateTime data) =>
    '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}';

/// Item sugerido (ou adicionado manualmente) dentro de um grupo de
/// fornecedor, com a quantidade editável antes de virar pedido de verdade.
class _ItemEditavel {
  final String produtoId;
  final String produtoNome;
  final int? quantidadeSugerida;
  int quantidadePedida;
  bool incluido;
  ProdutoFornecedor? vinculo; // custo base + faixas de desconto, se cadastrado
  double custoAvulso; // usado quando não há vínculo produto-fornecedor cadastrado

  /// Custo/data da última vez que esse produto foi comprado de verdade
  /// (`itens_entrada`, qualquer fornecedor) — pra avisar se o custo desse
  /// pedido está subindo ou descendo em relação à última compra real.
  ({double custoUnitario, String fornecedorNome, DateTime dataEntrada})? ultimaCompra;

  /// Outro fornecedor vinculado a esse produto com custo menor que o
  /// aplicado aqui — pra avisar "fornecedor Y vende mais barato".
  ({String fornecedorNome, double custoUnitario})? fornecedorMaisBarato;

  _ItemEditavel({
    required this.produtoId,
    required this.produtoNome,
    this.quantidadeSugerida,
    required this.quantidadePedida,
    this.incluido = true,
    this.vinculo,
    this.custoAvulso = 0,
    this.ultimaCompra,
    this.fornecedorMaisBarato,
  });

  double get custoUnitario => vinculo?.custoParaQuantidade(quantidadePedida) ?? custoAvulso;
  double get subtotal => incluido ? quantidadePedida * custoUnitario : 0;

  ({int unidadesFaltando, double economiaPorUnidade})? get proximaFaixa =>
      vinculo?.proximaFaixa(quantidadePedida);

  /// Diferença percentual do custo deste pedido vs a última compra real —
  /// null se não há histórico ou a diferença é desprezível (<1%).
  double? get variacaoVsUltimaCompra {
    final ultima = ultimaCompra;
    if (ultima == null || ultima.custoUnitario <= 0) return null;
    final variacao = (custoUnitario - ultima.custoUnitario) / ultima.custoUnitario;
    return variacao.abs() < 0.01 ? null : variacao;
  }
}

class _GrupoFornecedor {
  final Fornecedor fornecedor;
  final List<_ItemEditavel> itens;

  _GrupoFornecedor({required this.fornecedor, required this.itens});

  String get fornecedorId => fornecedor.id!;
  String get fornecedorNome => fornecedor.nome;
  int? get prazoEntregaDias => fornecedor.prazoEntregaDias;
  double? get valorMinimoPedido => fornecedor.valorMinimoPedido;

  double get total => itens.fold(0, (soma, i) => soma + i.subtotal);
  bool get atingiuMinimo => valorMinimoPedido == null || total >= valorMinimoPedido!;
}

class SugestaoCompraScreen extends StatefulWidget {
  const SugestaoCompraScreen({super.key});

  @override
  State<SugestaoCompraScreen> createState() => _SugestaoCompraScreenState();
}

class _SugestaoCompraScreenState extends State<SugestaoCompraScreen> {
  int _diasAnalise = 30;
  int _diasSeguranca = 7;
  List<_GrupoFornecedor> _grupos = [];
  bool _montandoGrupos = false;
  final Set<String> _criandoPedidoPara = {};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final fornecedorProvider = context.read<FornecedorProvider>();
    if (fornecedorProvider.fornecedores.isEmpty) {
      await fornecedorProvider.carregar();
    }
    final provider = context.read<PedidoCompraProvider>();
    await provider.carregarSugestoes(diasAnalise: _diasAnalise, diasSeguranca: _diasSeguranca);
    if (!mounted) return;
    await _montarGrupos(provider.sugestoes, fornecedorProvider.fornecedores);
  }

  /// Busca os vínculos produto-fornecedor (com faixas de desconto) dos
  /// produtos sugeridos, pra poder calcular o custo por faixa, a dica de
  /// "peça mais N e economize", comparar com outros fornecedores do mesmo
  /// produto e com o último custo pago de verdade (`itens_entrada`) — a RPC
  /// só devolve o custo já aplicado na quantidade sugerida, não esse
  /// contexto todo.
  Future<void> _montarGrupos(List<SugestaoCompra> sugestoes, List<Fornecedor> fornecedores) async {
    setState(() => _montandoGrupos = true);
    final repository = ProdutoFornecedorRepository();
    final todosVinculosPorProduto = <String, List<ProdutoFornecedor>>{};
    for (final produtoId in sugestoes.map((s) => s.produtoId).toSet()) {
      try {
        todosVinculosPorProduto[produtoId] = await repository.listarPorProduto(produtoId);
      } catch (_) {
        // Sem vínculo detalhado, segue só com o custo que já veio da RPC.
      }
    }

    Map<String, ({double custoUnitario, String fornecedorNome, DateTime dataEntrada})> ultimosCustos = {};
    try {
      ultimosCustos = await EntradaRepository().buscarUltimoCustoPorProduto(sugestoes.map((s) => s.produtoId).toList());
    } catch (_) {
      // Sem histórico de compra, segue sem o aviso de variação de custo.
    }

    final grupos = <String, _GrupoFornecedor>{};
    for (final s in sugestoes) {
      final fornecedoresEncontrados = fornecedores.where((f) => f.id == s.fornecedorId).toList();
      final fornecedor = fornecedoresEncontrados.isNotEmpty
          ? fornecedoresEncontrados.first
          : Fornecedor(id: s.fornecedorId, nome: s.fornecedorNome, prazoEntregaDias: s.prazoEntregaDias);
      final grupo = grupos.putIfAbsent(
        s.fornecedorId,
        () => _GrupoFornecedor(fornecedor: fornecedor, itens: []),
      );

      final vinculosDoProduto = todosVinculosPorProduto[s.produtoId] ?? [];
      final vinculoDoGrupo = vinculosDoProduto.where((v) => v.fornecedorId == s.fornecedorId).toList();
      final custoAtual = vinculoDoGrupo.isNotEmpty ? vinculoDoGrupo.first.custoUnitario : s.custoUnitario;
      final alternativasMaisBaratas = vinculosDoProduto
          .where((v) => v.ativo && v.fornecedorId != s.fornecedorId && v.custoUnitario < custoAtual)
          .toList()
        ..sort((a, b) => a.custoUnitario.compareTo(b.custoUnitario));

      ({String fornecedorNome, double custoUnitario})? fornecedorMaisBarato;
      if (alternativasMaisBaratas.isNotEmpty) {
        final melhor = alternativasMaisBaratas.first;
        final nomeConhecido = fornecedores.where((f) => f.id == melhor.fornecedorId).toList();
        fornecedorMaisBarato = (
          fornecedorNome: melhor.fornecedorNome ?? (nomeConhecido.isNotEmpty ? nomeConhecido.first.nome : '—'),
          custoUnitario: melhor.custoUnitario,
        );
      }

      grupo.itens.add(_ItemEditavel(
        produtoId: s.produtoId,
        produtoNome: s.produtoNome,
        quantidadeSugerida: s.quantidadeSugerida,
        quantidadePedida: s.quantidadeSugerida,
        vinculo: vinculoDoGrupo.isNotEmpty ? vinculoDoGrupo.first : null,
        custoAvulso: s.custoUnitario,
        ultimaCompra: ultimosCustos[s.produtoId],
        fornecedorMaisBarato: fornecedorMaisBarato,
      ));
    }

    if (!mounted) return;
    setState(() {
      _grupos = grupos.values.toList()..sort((a, b) => a.fornecedorNome.compareTo(b.fornecedorNome));
      _montandoGrupos = false;
    });
  }

  Future<void> _adicionarProdutoManual(_GrupoFornecedor grupo) async {
    final produtos = context.read<ProdutoProvider>().produtos;
    final jaNoGrupo = grupo.itens.map((i) => i.produtoId).toSet();
    final disponiveis = produtos.where((p) => p.ativo && p.id != null && !jaNoGrupo.contains(p.id)).toList()
      ..sort((a, b) => a.nome.compareTo(b.nome));

    final produtoEscolhido = await showModalBottomSheet<Produto>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => BuscaProdutoSheet(produtos: disponiveis),
    );
    if (produtoEscolhido == null || !mounted) return;

    ProdutoFornecedor? vinculo;
    try {
      final vinculos = await ProdutoFornecedorRepository().listarPorProduto(produtoEscolhido.id!);
      final match = vinculos.where((v) => v.fornecedorId == grupo.fornecedorId).toList();
      vinculo = match.isNotEmpty ? match.first : null;
    } catch (_) {}

    setState(() {
      grupo.itens.add(_ItemEditavel(
        produtoId: produtoEscolhido.id!,
        produtoNome: produtoEscolhido.nome,
        quantidadePedida: vinculo?.multiploCompra ?? 1,
        vinculo: vinculo,
        custoAvulso: vinculo?.custoUnitario ?? produtoEscolhido.custo,
      ));
    });
  }

  Future<void> _criarPedido(_GrupoFornecedor grupo) async {
    final itensIncluidos = grupo.itens.where((i) => i.incluido && i.quantidadePedida > 0).toList();
    if (itensIncluidos.isEmpty) return;

    setState(() => _criandoPedidoPara.add(grupo.fornecedorId));
    try {
      final provider = context.read<PedidoCompraProvider>();
      final authProvider = context.read<AuthProvider>();

      final novo = await provider.criarPedido(
        pedido: PedidoCompra(fornecedor: grupo.fornecedor),
        itens: itensIncluidos
            .map((i) => ItemPedidoCompra(
                  produtoId: i.produtoId,
                  produtoNome: i.produtoNome,
                  quantidadeSugerida: i.quantidadeSugerida,
                  quantidadePedida: i.quantidadePedida,
                  custoUnitario: i.custoUnitario,
                  origem: i.quantidadeSugerida != null ? OrigemItemPedidoCompra.sugestao : OrigemItemPedidoCompra.manual,
                ))
            .toList(),
        criadoPor: authProvider.usuarioAtual?.id,
      );

      if (!mounted) return;
      setState(() => _grupos = _grupos.where((g) => g.fornecedorId != grupo.fornecedorId).toList());

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Pedido criado para ${grupo.fornecedorNome}'),
          action: SnackBarAction(
            label: 'Ver pedido',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => PedidoCompraDetalheScreen(pedidoId: novo.id!)),
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao criar pedido: $e')));
    } finally {
      if (mounted) setState(() => _criandoPedidoPara.remove(grupo.fornecedorId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PedidoCompraProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sugestão de Compra'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Recalcular', onPressed: _carregar),
        ],
      ),
      body: Column(
        children: [
          _FiltrosAnalise(
            diasAnalise: _diasAnalise,
            diasSeguranca: _diasSeguranca,
            onAplicar: (dias, seguranca) {
              setState(() {
                _diasAnalise = dias;
                _diasSeguranca = seguranca;
              });
              _carregar();
            },
          ),
          if (provider.carregandoSugestoes || _montandoGrupos)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (provider.erro != null)
            Expanded(child: EstadoErroLista(mensagem: provider.erro!, onTentarNovamente: _carregar))
          else if (_grupos.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline, size: 56, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(height: 16),
                      Text(
                        'Nenhuma reposição necessária no momento',
                        style: Theme.of(context).textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Com base nas vendas dos últimos $_diasAnalise dias, prazo de entrega e margem de segurança de $_diasSeguranca dias.',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _grupos.length,
                itemBuilder: (context, index) => _GrupoFornecedorCard(
                  grupo: _grupos[index],
                  criando: _criandoPedidoPara.contains(_grupos[index].fornecedorId),
                  onMudou: () => setState(() {}),
                  onAdicionarProduto: () => _adicionarProdutoManual(_grupos[index]),
                  onCriarPedido: () => _criarPedido(_grupos[index]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FiltrosAnalise extends StatelessWidget {
  final int diasAnalise;
  final int diasSeguranca;
  final void Function(int diasAnalise, int diasSeguranca) onAplicar;

  const _FiltrosAnalise({required this.diasAnalise, required this.diasSeguranca, required this.onAplicar});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Análise: vendas dos últimos $diasAnalise dias + $diasSeguranca dias de margem de segurança',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: () async {
              final resultado = await showDialog<({int dias, int seguranca})>(
                context: context,
                builder: (ctx) => _DialogFiltros(diasAnalise: diasAnalise, diasSeguranca: diasSeguranca),
              );
              if (resultado != null) onAplicar(resultado.dias, resultado.seguranca);
            },
            child: const Text('Ajustar'),
          ),
        ],
      ),
    );
  }
}

class _DialogFiltros extends StatefulWidget {
  final int diasAnalise;
  final int diasSeguranca;

  const _DialogFiltros({required this.diasAnalise, required this.diasSeguranca});

  @override
  State<_DialogFiltros> createState() => _DialogFiltrosState();
}

class _DialogFiltrosState extends State<_DialogFiltros> {
  late final TextEditingController _analiseController;
  late final TextEditingController _segurancaController;

  @override
  void initState() {
    super.initState();
    _analiseController = TextEditingController(text: widget.diasAnalise.toString());
    _segurancaController = TextEditingController(text: widget.diasSeguranca.toString());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Ajustar análise'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _analiseController,
            decoration: const InputDecoration(labelText: 'Período de vendas analisado (dias)'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _segurancaController,
            decoration: const InputDecoration(labelText: 'Margem de segurança extra (dias)'),
            keyboardType: TextInputType.number,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        ElevatedButton(
          onPressed: () {
            Navigator.pop(
              context,
              (
                dias: int.tryParse(_analiseController.text) ?? widget.diasAnalise,
                seguranca: int.tryParse(_segurancaController.text) ?? widget.diasSeguranca,
              ),
            );
          },
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}

class _GrupoFornecedorCard extends StatelessWidget {
  final _GrupoFornecedor grupo;
  final bool criando;
  final VoidCallback onMudou;
  final VoidCallback onAdicionarProduto;
  final VoidCallback onCriarPedido;

  const _GrupoFornecedorCard({
    required this.grupo,
    required this.criando,
    required this.onMudou,
    required this.onAdicionarProduto,
    required this.onCriarPedido,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final incluidos = grupo.itens.where((i) => i.incluido).length;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(grupo.fornecedorNome, style: Theme.of(context).textTheme.titleMedium),
                ),
                if (grupo.prazoEntregaDias != null)
                  Text('Prazo: ${grupo.prazoEntregaDias}d', style: TextStyle(color: colorScheme.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 8),
            for (final item in grupo.itens) _LinhaItem(item: item, onMudou: onMudou),
            TextButton.icon(
              onPressed: onAdicionarProduto,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Adicionar produto'),
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total: R\$ ${grupo.total.toStringAsFixed(2)} ($incluidos itens)',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (grupo.valorMinimoPedido != null)
                        Text(
                          grupo.atingiuMinimo
                              ? 'Mínimo de R\$ ${grupo.valorMinimoPedido!.toStringAsFixed(2)} atingido'
                              : 'Faltam R\$ ${(grupo.valorMinimoPedido! - grupo.total).toStringAsFixed(2)} pro mínimo de R\$ ${grupo.valorMinimoPedido!.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: grupo.atingiuMinimo ? Colors.green.shade700 : colorScheme.error,
                          ),
                        ),
                    ],
                  ),
                ),
                ElevatedButton(
                  onPressed: (criando || incluidos == 0) ? null : onCriarPedido,
                  child: criando
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Criar pedido'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LinhaItem extends StatefulWidget {
  final _ItemEditavel item;
  final VoidCallback onMudou;

  const _LinhaItem({required this.item, required this.onMudou});

  @override
  State<_LinhaItem> createState() => _LinhaItemState();
}

class _LinhaItemState extends State<_LinhaItem> {
  late final TextEditingController _qtdController;

  @override
  void initState() {
    super.initState();
    _qtdController = TextEditingController(text: widget.item.quantidadePedida.toString());
  }

  @override
  void dispose() {
    _qtdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final proxima = item.proximaFaixa;
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: item.incluido,
                onChanged: (v) {
                  setState(() => item.incluido = v ?? true);
                  widget.onMudou();
                },
              ),
              Expanded(
                child: Text(item.produtoNome, style: item.incluido ? null : TextStyle(color: colorScheme.onSurfaceVariant)),
              ),
              SizedBox(
                width: 64,
                child: TextField(
                  controller: _qtdController,
                  enabled: item.incluido,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8)),
                  onChanged: (v) {
                    item.quantidadePedida = int.tryParse(v) ?? 0;
                    setState(() {});
                    widget.onMudou();
                  },
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 76,
                child: Text('R\$${item.subtotal.toStringAsFixed(2)}', textAlign: TextAlign.right),
              ),
            ],
          ),
          if (item.quantidadeSugerida != null && item.quantidadeSugerida != item.quantidadePedida)
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: Text(
                'Sugerido: ${item.quantidadeSugerida}un',
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),
            ),
          if (proxima != null)
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: Text(
                'Peça mais ${proxima.unidadesFaltando}un e economize R\$${proxima.economiaPorUnidade.toStringAsFixed(2)}/un',
                style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.w600),
              ),
            ),
          if (item.variacaoVsUltimaCompra != null)
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: Text(
                item.variacaoVsUltimaCompra! > 0
                    ? '⚠ +${(item.variacaoVsUltimaCompra! * 100).toStringAsFixed(0)}% vs última compra (R\$${item.ultimaCompra!.custoUnitario.toStringAsFixed(2)} via ${item.ultimaCompra!.fornecedorNome}, ${_formatarDataCurta(item.ultimaCompra!.dataEntrada)})'
                    : '${(item.variacaoVsUltimaCompra!.abs() * 100).toStringAsFixed(0)}% mais barato que a última compra (R\$${item.ultimaCompra!.custoUnitario.toStringAsFixed(2)})',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: item.variacaoVsUltimaCompra! > 0.1 ? FontWeight.w600 : FontWeight.normal,
                  color: item.variacaoVsUltimaCompra! > 0.1
                      ? colorScheme.error
                      : (item.variacaoVsUltimaCompra! > 0 ? Colors.orange.shade800 : Colors.green.shade700),
                ),
              ),
            ),
          if (item.fornecedorMaisBarato != null)
            Padding(
              padding: const EdgeInsets.only(left: 40),
              child: Text(
                '💡 ${item.fornecedorMaisBarato!.fornecedorNome} vende por R\$${item.fornecedorMaisBarato!.custoUnitario.toStringAsFixed(2)} (mais barato)',
                style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
              ),
            ),
        ],
      ),
    );
  }
}

