import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/fornecedor.dart';
import '../models/produto.dart';
import '../models/produto_fornecedor.dart';
import '../providers/auth_provider.dart';
import '../providers/produto_provider.dart';
import '../repositories/produto_fornecedor_repository.dart';
import '../utils/busca_utils.dart';
import '../utils/produto_validators.dart';

/// Vincula vários produtos de uma vez a um fornecedor — o inverso de
/// `VinculosFornecedorScreen` (que desvincula em massa). Sem isso, só dava
/// pra vincular 1 produto por vez, dentro da edição do próprio produto.
class VincularProdutosFornecedorScreen extends StatefulWidget {
  final Fornecedor fornecedor;

  /// Ids de produtos que já têm vínculo com esse fornecedor — excluídos da
  /// busca (constraint única `produto_id, fornecedor_id` no banco impede
  /// vincular de novo, então nem oferece a opção).
  final Set<String> produtosJaVinculados;

  const VincularProdutosFornecedorScreen({
    super.key,
    required this.fornecedor,
    required this.produtosJaVinculados,
  });

  @override
  State<VincularProdutosFornecedorScreen> createState() => _VincularProdutosFornecedorScreenState();
}

enum _FiltroVinculo { todos, semFornecedor, comFornecedor }

class _ConfigVinculo {
  final custoController = TextEditingController();
  final codigoController = TextEditingController();
  bool principal = false;
  String? erro;

  void dispose() {
    custoController.dispose();
    codigoController.dispose();
  }
}

class _VincularProdutosFornecedorScreenState extends State<VincularProdutosFornecedorScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _buscaController = TextEditingController();
  final Set<String> _selecionados = {};
  final Map<String, _ConfigVinculo> _configs = {};
  bool _vinculando = false;

  String _categoriaSelecionada = 'Tudo';
  _FiltroVinculo _filtroVinculo = _FiltroVinculo.todos;

  /// Produto -> fornecedores que já compram dele, de QUALQUER fornecedor
  /// (não só o atual) — carregado uma vez ao abrir a tela.
  Map<String, List<String>> _fornecedoresPorProduto = {};
  bool _carregandoVinculos = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _carregarVinculosExistentes();
  }

  Future<void> _carregarVinculosExistentes() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;
    final mapa = await ProdutoFornecedorRepository().listarFornecedoresPorProduto(
      empresaId,
      excetoFornecedorId: widget.fornecedor.id,
    );
    if (!mounted) return;
    setState(() {
      _fornecedoresPorProduto = mapa;
      _carregandoVinculos = false;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _buscaController.dispose();
    for (final config in _configs.values) {
      config.dispose();
    }
    super.dispose();
  }

  void _alternarSelecao(Produto produto, bool? marcado) {
    setState(() {
      if (marcado == true) {
        _selecionados.add(produto.id!);
        final config = _ConfigVinculo();
        if (produto.custo > 0) {
          config.custoController.text = produto.custo.toStringAsFixed(2).replaceAll('.', ',');
        }
        _configs[produto.id!] = config;
      } else {
        _selecionados.remove(produto.id!);
        _configs.remove(produto.id!)?.dispose();
      }
    });
  }

  Future<void> _vincularTodos(List<Produto> produtos) async {
    var temErro = false;
    setState(() {
      for (final id in _selecionados) {
        final config = _configs[id]!;
        final custo = ProdutoValidators.parseNumero(config.custoController.text);
        config.erro = (custo == null || custo <= 0) ? 'Informe um custo maior que zero.' : null;
        if (config.erro != null) temErro = true;
      }
    });

    if (temErro) {
      _tabController.animateTo(1);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Corrija os campos destacados antes de continuar.')),
      );
      return;
    }

    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;

    setState(() => _vinculando = true);
    final repository = ProdutoFornecedorRepository();
    final falhas = <String>[];
    final idsVinculados = <String>[];

    for (final id in _selecionados.toList()) {
      final produto = produtos.firstWhere((p) => p.id == id);
      final config = _configs[id]!;
      final codigo = config.codigoController.text.trim();
      try {
        await repository.criar(
          ProdutoFornecedor(
            produtoId: id,
            fornecedorId: widget.fornecedor.id!,
            custoUnitario: ProdutoValidators.parseNumero(config.custoController.text)!,
            codigoProdutoFornecedor: codigo.isEmpty ? null : codigo,
            principal: config.principal,
          ),
          empresaId: empresaId,
        );
        idsVinculados.add(id);
      } catch (e) {
        falhas.add('${produto.nome}: $e');
      }
    }

    setState(() {
      for (final id in idsVinculados) {
        _selecionados.remove(id);
        _configs.remove(id)?.dispose();
      }
      _vinculando = false;
    });

    if (!mounted) return;

    if (falhas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${idsVinculados.length} produto(s) vinculado(s).')),
      );
      Navigator.of(context).pop(true);
    } else {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('${idsVinculados.length} vinculado(s), ${falhas.length} falharam'),
          content: SingleChildScrollView(child: Text(falhas.join('\n\n'))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendi')),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final produtos = context.watch<ProdutoProvider>().produtos;
    final busca = _buscaController.text;

    final categorias = ['Tudo', ...(produtos.map((p) => p.categoria).toSet().toList()..sort())];

    final candidatos = produtos.where((p) {
      if (p.id == null) return false;
      if (p.ehKit) return false;
      if (widget.produtosJaVinculados.contains(p.id)) return false;
      if (_categoriaSelecionada != 'Tudo' && p.categoria != _categoriaSelecionada) return false;
      final temOutroFornecedor = _fornecedoresPorProduto.containsKey(p.id);
      if (_filtroVinculo == _FiltroVinculo.semFornecedor && temOutroFornecedor) return false;
      if (_filtroVinculo == _FiltroVinculo.comFornecedor && !temOutroFornecedor) return false;
      return contemTodasPalavras(p.nome, busca) || p.codigoBarras.toLowerCase().contains(busca.toLowerCase());
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Vincular a "${widget.fornecedor.nome}"'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            const Tab(text: 'Selecionar'),
            Tab(text: 'Configurar (${_selecionados.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _abaSelecionar(candidatos, categorias),
          _abaConfigurar(produtos),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            onPressed: _selecionados.isEmpty || _vinculando ? null : () => _vincularTodos(produtos),
            icon: _vinculando
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.link),
            label: Text(_vinculando ? 'Vinculando...' : 'Vincular ${_selecionados.length} produto(s)'),
          ),
        ),
      ),
    );
  }

  Widget _abaSelecionar(List<Produto> candidatos, List<String> categorias) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: TextField(
            controller: _buscaController,
            decoration: const InputDecoration(
              hintText: 'Buscar produto (nome ou código de barras)',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
            onChanged: (_) => setState(() {}),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: SegmentedButton<_FiltroVinculo>(
            segments: const [
              ButtonSegment(value: _FiltroVinculo.todos, label: Text('Todos')),
              ButtonSegment(value: _FiltroVinculo.semFornecedor, label: Text('Sem fornecedor')),
              ButtonSegment(value: _FiltroVinculo.comFornecedor, label: Text('Já tem fornecedor')),
            ],
            selected: {_filtroVinculo},
            onSelectionChanged: (s) => setState(() => _filtroVinculo = s.first),
          ),
        ),
        SizedBox(
          height: 40,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            scrollDirection: Axis.horizontal,
            itemCount: categorias.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final categoria = categorias[i];
              return ChoiceChip(
                label: Text(categoria),
                selected: _categoriaSelecionada == categoria,
                onSelected: (_) => setState(() => _categoriaSelecionada = categoria),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _carregandoVinculos
              ? const Center(child: CircularProgressIndicator())
              : candidatos.isEmpty
                  ? const Center(child: Text('Nenhum produto encontrado com esses filtros.'))
                  : ListView.builder(
                      itemCount: candidatos.length,
                      itemBuilder: (context, i) {
                        final produto = candidatos[i];
                        final marcado = _selecionados.contains(produto.id);
                        final outrosFornecedores = _fornecedoresPorProduto[produto.id];
                        return CheckboxListTile(
                          value: marcado,
                          onChanged: (v) => _alternarSelecao(produto, v),
                          title: Text(produto.nome, maxLines: 2, overflow: TextOverflow.ellipsis),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${produto.categoria} • custo atual: R\$ ${produto.custo.toStringAsFixed(2)}'),
                              if (outrosFornecedores != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Row(
                                    children: [
                                      Icon(Icons.link, size: 14, color: Theme.of(context).colorScheme.tertiary),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          'Já compra de: ${outrosFornecedores.join(', ')}',
                                          style: TextStyle(
                                            color: Theme.of(context).colorScheme.tertiary,
                                            fontWeight: FontWeight.w600,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          isThreeLine: outrosFornecedores != null,
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _abaConfigurar(List<Produto> produtos) {
    if (_selecionados.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nenhum produto selecionado ainda. Volte pra aba "Selecionar" e marque os produtos que você compra desse fornecedor.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        for (final id in _selecionados)
          _CardConfigVinculo(
            produto: produtos.firstWhere((p) => p.id == id),
            config: _configs[id]!,
            onRemover: () => _alternarSelecao(produtos.firstWhere((p) => p.id == id), false),
          ),
      ],
    );
  }
}

class _CardConfigVinculo extends StatefulWidget {
  final Produto produto;
  final _ConfigVinculo config;
  final VoidCallback onRemover;

  const _CardConfigVinculo({required this.produto, required this.config, required this.onRemover});

  @override
  State<_CardConfigVinculo> createState() => _CardConfigVinculoState();
}

class _CardConfigVinculoState extends State<_CardConfigVinculo> {
  @override
  Widget build(BuildContext context) {
    final config = widget.config;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(widget.produto.nome, style: const TextStyle(fontWeight: FontWeight.w600))),
                IconButton(icon: const Icon(Icons.close), onPressed: widget.onRemover, tooltip: 'Remover'),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: config.custoController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Custo unitário nesse fornecedor (R\$)'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: config.codigoController,
              decoration: const InputDecoration(
                labelText: 'Código do produto no fornecedor (opcional)',
                helperText: 'Referência interna do fornecedor, se houver.',
              ),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Fornecedor principal desse produto'),
              value: config.principal,
              onChanged: (v) => setState(() => config.principal = v ?? false),
            ),
            if (config.erro != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(config.erro!, style: const TextStyle(color: Colors.red)),
              ),
          ],
        ),
      ),
    );
  }
}
