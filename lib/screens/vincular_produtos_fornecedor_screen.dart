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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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

    final candidatos = produtos.where((p) {
      if (p.id == null) return false;
      if (p.ehKit) return false;
      if (widget.produtosJaVinculados.contains(p.id)) return false;
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
          _abaSelecionar(candidatos),
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

  Widget _abaSelecionar(List<Produto> candidatos) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
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
        Expanded(
          child: candidatos.isEmpty
              ? const Center(child: Text('Nenhum produto disponível pra vincular (já vinculados ficam de fora).'))
              : ListView.builder(
                  itemCount: candidatos.length,
                  itemBuilder: (context, i) {
                    final produto = candidatos[i];
                    final marcado = _selecionados.contains(produto.id);
                    return CheckboxListTile(
                      value: marcado,
                      onChanged: (v) => _alternarSelecao(produto, v),
                      title: Text(produto.nome, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${produto.categoria} • custo atual: R\$ ${produto.custo.toStringAsFixed(2)}'),
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
