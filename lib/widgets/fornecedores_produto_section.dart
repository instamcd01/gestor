import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/produto_fornecedor.dart';
import '../providers/auth_provider.dart';
import '../providers/fornecedor_provider.dart';
import '../repositories/entrada_repository.dart';
import '../repositories/produto_fornecedor_repository.dart';
import '../utils/formatadores_input.dart';
import '../utils/produto_validators.dart';
import 'form_section.dart';

/// Seção "Fornecedores deste produto" na tela de editar produto — cada
/// produto pode ter vários fornecedores vinculados, cada um com custo,
/// código próprio e faixas de desconto por quantidade. `principal` marca o
/// fornecedor usado por padrão na sugestão automática de compra.
///
/// Diferente de `CanaisMarketplaceSection`, persiste cada alteração na hora
/// (não espera o botão "Salvar" do produto) — mais simples de manter
/// correto com uma sublista dinâmica (faixas de desconto) dentro de cada
/// vínculo, e evita perder a edição se o usuário voltar sem salvar o resto.
class FornecedoresProdutoSection extends StatefulWidget {
  final String produtoId;

  const FornecedoresProdutoSection({super.key, required this.produtoId});

  @override
  State<FornecedoresProdutoSection> createState() => _FornecedoresProdutoSectionState();
}

class _FornecedoresProdutoSectionState extends State<FornecedoresProdutoSection> {
  final _repository = ProdutoFornecedorRepository();
  List<ProdutoFornecedor> _vinculos = [];
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final vinculos = await _repository.listarPorProduto(widget.produtoId);
      if (!mounted) return;
      setState(() {
        _vinculos = vinculos;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Erro ao carregar fornecedores do produto: $e';
        _carregando = false;
      });
    }
  }

  Future<void> _abrirFormulario({ProdutoFornecedor? vinculo}) async {
    final salvou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => _VinculoFornecedorFormScreen(
          produtoId: widget.produtoId,
          vinculo: vinculo,
          outrosVinculos: _vinculos.where((v) => v.id != vinculo?.id).toList(),
        ),
      ),
    );
    if (salvou == true) _carregar();
  }

  Future<void> _excluir(ProdutoFornecedor vinculo) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover vínculo'),
        content: Text('Remover "${vinculo.fornecedorNome}" da lista de fornecedores deste produto?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remover')),
        ],
      ),
    );
    if (confirmou != true) return;
    try {
      await _repository.excluir(vinculo.id!);
      _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao remover: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FormSection(
      titulo: 'Fornecedores deste produto',
      children: [
        if (_carregando)
          const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
        else if (_erro != null)
          Padding(padding: const EdgeInsets.all(8), child: Text(_erro!, style: TextStyle(color: colorScheme.error)))
        else if (_vinculos.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Nenhum fornecedor vinculado ainda — sem isso o produto não entra na sugestão automática de compra.',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          )
        else
          ...(_vinculos.map((v) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Row(
                    children: [
                      Expanded(child: Text(v.fornecedorNome ?? '—')),
                      if (v.principal)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('Principal', style: TextStyle(fontSize: 11, color: colorScheme.onPrimaryContainer)),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    [
                      'R\$ ${v.custoUnitario.toStringAsFixed(2)}/un',
                      if (v.codigoProdutoFornecedor?.isNotEmpty == true) 'cód. ${v.codigoProdutoFornecedor}',
                      if (v.faixasDesconto.isNotEmpty) '${v.faixasDesconto.length} faixa(s) de desconto',
                    ].join(' • '),
                  ),
                  onTap: () => _abrirFormulario(vinculo: v),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () => _excluir(v),
                  ),
                ),
              ))),
        OutlinedButton.icon(
          onPressed: () => _abrirFormulario(),
          icon: const Icon(Icons.add),
          label: const Text('Vincular fornecedor'),
        ),
      ],
    );
  }
}

class _VinculoFornecedorFormScreen extends StatefulWidget {
  final String produtoId;
  final ProdutoFornecedor? vinculo;
  final List<ProdutoFornecedor> outrosVinculos;

  const _VinculoFornecedorFormScreen({required this.produtoId, this.vinculo, this.outrosVinculos = const []});

  @override
  State<_VinculoFornecedorFormScreen> createState() => _VinculoFornecedorFormScreenState();
}

class _VinculoFornecedorFormScreenState extends State<_VinculoFornecedorFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _repository = ProdutoFornecedorRepository();

  String? _fornecedorId;
  late TextEditingController _custoController;
  late TextEditingController _codigoController;
  late TextEditingController _multiploController;
  bool _principal = false;
  bool _salvando = false;
  ({double custoUnitario, String fornecedorNome, DateTime dataEntrada})? _ultimaCompra;

  final List<({TextEditingController quantidade, TextEditingController custo})> _faixas = [];

  bool get _editando => widget.vinculo != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<FornecedorProvider>();
      if (provider.fornecedores.isEmpty) provider.carregar();
    });
    final v = widget.vinculo;
    _fornecedorId = v?.fornecedorId;
    _custoController = TextEditingController(text: v != null ? ProdutoValidators.formatarMoeda(v.custoUnitario) : '');
    _codigoController = TextEditingController(text: v?.codigoProdutoFornecedor ?? '');
    _multiploController = TextEditingController(text: v?.multiploCompra?.toString() ?? '');
    _principal = v?.principal ?? false;
    for (final faixa in v?.faixasDesconto ?? []) {
      _faixas.add((
        quantidade: TextEditingController(text: faixa.quantidadeMinima.toString()),
        custo: TextEditingController(text: ProdutoValidators.formatarMoeda(faixa.custoUnitario)),
      ));
    }
    _carregarUltimaCompra();
  }

  Future<void> _carregarUltimaCompra() async {
    try {
      final resultado = await EntradaRepository().buscarUltimoCustoPorProduto([widget.produtoId]);
      if (!mounted) return;
      setState(() => _ultimaCompra = resultado[widget.produtoId]);
    } catch (_) {
      // Sem histórico de compra, segue sem o aviso.
    }
  }

  @override
  void dispose() {
    _custoController.dispose();
    _codigoController.dispose();
    _multiploController.dispose();
    for (final faixa in _faixas) {
      faixa.quantidade.dispose();
      faixa.custo.dispose();
    }
    super.dispose();
  }

  void _adicionarFaixa() {
    setState(() {
      _faixas.add((quantidade: TextEditingController(), custo: TextEditingController()));
    });
  }

  void _removerFaixa(int index) {
    setState(() {
      _faixas[index].quantidade.dispose();
      _faixas[index].custo.dispose();
      _faixas.removeAt(index);
    });
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_fornecedorId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Escolha um fornecedor')));
      return;
    }

    final faixas = _faixas
        .map((f) => FaixaDescontoProdutoFornecedor(
              quantidadeMinima: int.tryParse(f.quantidade.text.trim()) ?? 0,
              custoUnitario: ProdutoValidators.parseNumero(f.custo.text) ?? 0,
            ))
        .where((f) => f.quantidadeMinima > 0 && f.custoUnitario > 0)
        .toList();

    final vinculo = ProdutoFornecedor(
      id: widget.vinculo?.id,
      produtoId: widget.produtoId,
      fornecedorId: _fornecedorId!,
      custoUnitario: ProdutoValidators.parseNumero(_custoController.text) ?? 0,
      codigoProdutoFornecedor: _codigoController.text.trim().isEmpty ? null : _codigoController.text.trim(),
      multiploCompra: int.tryParse(_multiploController.text.trim()),
      principal: _principal,
      faixasDesconto: faixas,
    );

    setState(() => _salvando = true);
    try {
      final empresaId = context.read<AuthProvider>().empresaId!;
      if (_editando) {
        await _repository.atualizar(vinculo);
      } else {
        await _repository.criar(vinculo, empresaId: empresaId);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar vínculo: $e')));
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fornecedores = context.watch<FornecedorProvider>().fornecedores.where((f) => f.ativo).toList();

    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar Fornecedor do Produto' : 'Vincular Fornecedor')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Fornecedor'),
                isExpanded: true,
                value: fornecedores.any((f) => f.id == _fornecedorId) ? _fornecedorId : null,
                items: fornecedores
                    .map((f) => DropdownMenuItem(
                          value: f.id,
                          child: Text(f.nome, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                selectedItemBuilder: (context) => fornecedores
                    .map((f) => Text(f.nome, overflow: TextOverflow.ellipsis, maxLines: 1))
                    .toList(),
                onChanged: _editando ? null : (value) => setState(() => _fornecedorId = value),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _custoController,
                decoration: const InputDecoration(labelText: 'Custo unitário (R\$)', prefixText: 'R\$ '),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [MoedaInputFormatter()],
                validator: (v) => (ProdutoValidators.parseNumero(v) ?? 0) > 0 ? null : 'Informe um custo maior que zero',
              ),
              if (_ultimaCompra != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                    'Última compra: R\$${_ultimaCompra!.custoUnitario.toStringAsFixed(2)} via ${_ultimaCompra!.fornecedorNome} '
                    '(${_ultimaCompra!.dataEntrada.day.toString().padLeft(2, '0')}/${_ultimaCompra!.dataEntrada.month.toString().padLeft(2, '0')})',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              if (widget.outrosVinculos.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    'Outros fornecedores desse produto: ${widget.outrosVinculos.map((v) => '${v.fornecedorNome} R\$${v.custoUnitario.toStringAsFixed(2)}').join(', ')}',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              TextFormField(
                controller: _codigoController,
                decoration: const InputDecoration(labelText: 'Código do produto no fornecedor (Opcional)'),
              ),
              TextFormField(
                controller: _multiploController,
                decoration: const InputDecoration(
                  labelText: 'Múltiplo de compra (Opcional)',
                  helperText: 'Se o fornecedor só vende em caixa fechada de N unidades',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [InteiroInputFormatter()],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Fornecedor principal'),
                subtitle: const Text('Usado por padrão na sugestão automática de compra'),
                value: _principal,
                onChanged: (v) => setState(() => _principal = v),
              ),
              const SizedBox(height: 16),
              Text('Desconto em cascata por quantidade', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                'A partir de X unidades pedidas, o custo unitário passa a ser este valor.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _faixas.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _faixas[i].quantidade,
                          decoration: const InputDecoration(labelText: 'A partir de (un)'),
                          keyboardType: TextInputType.number,
                          inputFormatters: [InteiroInputFormatter()],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _faixas[i].custo,
                          decoration: const InputDecoration(labelText: 'Custo unitário (R\$)'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [MoedaInputFormatter()],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                        onPressed: () => _removerFaixa(i),
                      ),
                    ],
                  ),
                ),
              OutlinedButton.icon(
                onPressed: _adicionarFaixa,
                icon: const Icon(Icons.add),
                label: const Text('Adicionar faixa de desconto'),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _salvando ? null : _salvar,
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                child: _salvando
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Salvar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
