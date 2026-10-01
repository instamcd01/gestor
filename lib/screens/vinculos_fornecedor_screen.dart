import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/fornecedor.dart';
import '../models/produto.dart';
import '../models/produto_fornecedor.dart';
import '../providers/auth_provider.dart';
import '../providers/produto_provider.dart';
import '../repositories/produto_fornecedor_repository.dart';
import '../utils/busca_utils.dart';
import '../widgets/busca_produto_sheet.dart';
import 'vincular_produtos_fornecedor_screen.dart';

/// Lista todos os produtos vinculados a um fornecedor (`produto_fornecedores`)
/// e permite desvincular vários de uma vez — não existia forma de fazer isso
/// em massa antes, só produto a produto dentro da edição do próprio produto.
/// Desvincular aqui só remove a linha de `produto_fornecedores` (custo,
/// código próprio, faixas de desconto) — não mexe no produto nem no
/// fornecedor em si.
class VinculosFornecedorScreen extends StatefulWidget {
  final Fornecedor fornecedor;

  const VinculosFornecedorScreen({super.key, required this.fornecedor});

  @override
  State<VinculosFornecedorScreen> createState() => _VinculosFornecedorScreenState();
}

class _VinculosFornecedorScreenState extends State<VinculosFornecedorScreen> {
  final _repository = ProdutoFornecedorRepository();
  final _buscaController = TextEditingController();
  List<ProdutoFornecedor> _vinculos = [];
  bool _carregando = true;
  String? _erro;
  final Set<String> _selecionados = {};
  bool _desvinculando = false;

  Future<void> _abrirVincular() async {
    final resultado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => VincularProdutosFornecedorScreen(
          fornecedor: widget.fornecedor,
          produtosJaVinculados: _vinculos.map((v) => v.produtoId).toSet(),
        ),
      ),
    );
    if (resultado == true) _carregar();
  }

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final vinculos = await _repository.listarPorFornecedor(widget.fornecedor.id!);
      setState(() {
        _vinculos = vinculos;
        _selecionados.removeWhere((id) => !vinculos.any((v) => v.id == id));
      });
    } catch (e) {
      setState(() => _erro = 'Erro ao carregar produtos: $e');
    } finally {
      setState(() => _carregando = false);
    }
  }

  List<ProdutoFornecedor> get _filtrados {
    final termo = _buscaController.text;
    if (termo.isEmpty) return _vinculos;
    return _vinculos
        .where((v) =>
            contemTodasPalavras(v.produtoNome ?? '', termo) ||
            (v.produtoCodigoBarras ?? '').toLowerCase().contains(termo.toLowerCase()))
        .toList();
  }

  /// Troca o produto vinculado sem apagar custo/código/faixas de desconto
  /// já cadastrados (ver `ProdutoFornecedorRepository.trocarProdutoDoVinculo`)
  /// — pedido explícito do usuário depois de vincular um código de
  /// fornecedor no produto errado (achado real 22/09) e não ter como
  /// corrigir sem sair da tela de Conferência.
  Future<void> _trocarProduto(ProdutoFornecedor vinculo) async {
    final produtos = context.read<ProdutoProvider>().produtos.where((p) => p.ativo && p.id != null).toList()
      ..sort((a, b) => a.nome.compareTo(b.nome));
    final novoProduto = await showModalBottomSheet<Produto>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BuscaProdutoSheet(produtos: produtos),
    );
    if (novoProduto == null || novoProduto.id == null || novoProduto.id == vinculo.produtoId || !mounted) return;

    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;

    try {
      await _repository.trocarProdutoDoVinculo(
        vinculoAtual: vinculo,
        novoProdutoId: novoProduto.id!,
        empresaId: empresaId,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao trocar produto: $e')));
      return;
    }
    if (!mounted) return;
    await _carregar();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Vínculo movido de "${vinculo.produtoNome}" pra "${novoProduto.nome}".')),
    );
  }

  Future<void> _desvincularSelecionados() async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Desvincular produtos'),
        content: Text(
          'Desvincular ${_selecionados.length} produto(s) de "${widget.fornecedor.nome}"? '
          'Isso remove o custo/código cadastrado pra esse fornecedor nesses produtos — o produto em si não é afetado.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Desvincular')),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    setState(() => _desvinculando = true);
    final falharam = await _repository.excluirEmLote(_selecionados.toList());
    setState(() {
      _selecionados.clear();
      _desvinculando = false;
    });
    await _carregar();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          falharam.isEmpty
              ? 'Produtos desvinculados.'
              : '${falharam.length} não puderam ser desvinculados.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _filtrados;
    final todosMarcados = filtrados.isNotEmpty && filtrados.every((v) => _selecionados.contains(v.id));

    return Scaffold(
      appBar: AppBar(
        title: Text('Produtos de "${widget.fornecedor.nome}"'),
        actions: [
          IconButton(icon: const Icon(Icons.add_link), tooltip: 'Vincular produtos', onPressed: _abrirVincular),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(child: Text(_erro!))
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: TextField(
                        controller: _buscaController,
                        decoration: const InputDecoration(
                          hintText: 'Buscar produto',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    if (filtrados.isNotEmpty)
                      CheckboxListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                        dense: true,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text('Selecionar todos (${filtrados.length})'),
                        value: todosMarcados,
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selecionados.addAll(filtrados.map((f) => f.id!));
                          } else {
                            _selecionados.removeAll(filtrados.map((f) => f.id!));
                          }
                        }),
                      ),
                    Expanded(
                      child: filtrados.isEmpty
                          ? const Center(child: Text('Nenhum produto vinculado a esse fornecedor.'))
                          : ListView.builder(
                              itemCount: filtrados.length,
                              itemBuilder: (context, i) {
                                final vinculo = filtrados[i];
                                return CheckboxListTile(
                                  value: _selecionados.contains(vinculo.id),
                                  onChanged: (v) => setState(() {
                                    if (v == true) {
                                      _selecionados.add(vinculo.id!);
                                    } else {
                                      _selecionados.remove(vinculo.id!);
                                    }
                                  }),
                                  title: Text(vinculo.produtoNome ?? '(produto removido)'),
                                  subtitle: Text(
                                    'R\$ ${vinculo.custoUnitario.toStringAsFixed(2)}'
                                    '${vinculo.principal ? ' • principal' : ''}'
                                    '${(vinculo.codigoProdutoFornecedor?.isNotEmpty ?? false) ? ' • cód. ${vinculo.codigoProdutoFornecedor}' : ''}',
                                  ),
                                  secondary: IconButton(
                                    icon: const Icon(Icons.swap_horiz),
                                    tooltip: 'Trocar o produto vinculado',
                                    onPressed: () => _trocarProduto(vinculo),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
      bottomNavigationBar: _selecionados.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: _desvinculando ? null : _desvincularSelecionados,
                  icon: _desvinculando
                      ? const SizedBox(
                          width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.link_off),
                  label: Text(_desvinculando ? 'Desvinculando...' : 'Desvincular ${_selecionados.length} produto(s)'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                ),
              ),
            ),
    );
  }
}
