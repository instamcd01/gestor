import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/kit_produto.dart';
import '../models/produto.dart';
import '../providers/kit_produto_provider.dart';
import '../providers/produto_provider.dart';
import '../utils/busca_utils.dart';
import '../utils/formatadores_input.dart';
import '../utils/produto_validators.dart';
import '../widgets/form_section.dart';
import 'gerenciar_midias_produto_screen.dart';

class KitProdutoFormScreen extends StatefulWidget {
  final KitProduto? kitInicial;

  const KitProdutoFormScreen({super.key, this.kitInicial});

  @override
  State<KitProdutoFormScreen> createState() => _KitProdutoFormScreenState();
}

class _KitProdutoFormScreenState extends State<KitProdutoFormScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nomeController = TextEditingController();
  final _descricaoController = TextEditingController();
  final _categoriaController = TextEditingController();
  final _precoController = TextEditingController();
  final _precoPromocionalController = TextEditingController();

  bool _ativo = true;
  bool _destacar = false;
  bool _exibirNoCatalogo = true;
  bool _isLoading = false;

  List<ComponenteKit> _componentes = [];
  List<String> _categorias = [];
  bool _categoriasCarregadas = false;

  bool get _editando => widget.kitInicial != null;

  @override
  void initState() {
    super.initState();
    final inicial = widget.kitInicial;
    if (inicial != null) {
      _nomeController.text = inicial.nome;
      _descricaoController.text = inicial.descricao;
      _categoriaController.text = inicial.categoria;
      _precoController.text = ProdutoValidators.formatarMoeda(inicial.preco);
      if (inicial.precoPromocional != null) {
        _precoPromocionalController.text = ProdutoValidators.formatarMoeda(inicial.precoPromocional!);
      }
      _ativo = inicial.ativo;
      _destacar = inicial.destacar;
      _exibirNoCatalogo = inicial.exibirNoCatalogo;
      _componentes = List.of(inicial.componentes);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final categorias = await context.read<ProdutoProvider>().listarCategoriasDisponiveis();
      if (!mounted) return;
      setState(() {
        _categorias = categorias;
        _categoriasCarregadas = true;
      });
    });
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _descricaoController.dispose();
    _categoriaController.dispose();
    _precoController.dispose();
    _precoPromocionalController.dispose();
    super.dispose();
  }

  double get _precoCheioComponentes =>
      _componentes.fold(0.0, (soma, c) => soma + c.preco * c.quantidade);

  Future<void> _adicionarComponente() async {
    final produtos = context.read<ProdutoProvider>().produtos;
    final escolhido = await showModalBottomSheet<Produto>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _SeletorProdutoSheet(produtos: produtos),
    );
    if (escolhido == null || !mounted) return;

    final quantidade = await _pedirQuantidade();
    if (quantidade == null || quantidade <= 0) return;

    setState(() {
      final index = _componentes.indexWhere((c) => c.produtoId == escolhido.id);
      final novoComponente = ComponenteKit(
        produtoId: escolhido.id!,
        nome: escolhido.nome,
        preco: escolhido.precoPromocional ?? escolhido.preco,
        custo: escolhido.custo,
        quantidade: quantidade,
      );
      if (index != -1) {
        _componentes[index] = novoComponente;
      } else {
        _componentes.add(novoComponente);
      }
    });
  }

  Future<int?> _pedirQuantidade() async {
    final controller = TextEditingController(text: '1');
    return showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Quantidade no kit'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [InteiroInputFormatter()],
          decoration: const InputDecoration(labelText: 'Quantidade'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(context, int.tryParse(controller.text) ?? 0),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
  }

  void _removerComponente(String produtoId) {
    setState(() => _componentes.removeWhere((c) => c.produtoId == produtoId));
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_componentes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Adicione pelo menos 1 produto ao kit.')),
      );
      return;
    }

    setState(() => _isLoading = true);

    final kit = KitProduto(
      id: widget.kitInicial?.id,
      nome: _nomeController.text,
      descricao: _descricaoController.text,
      categoria: _categoriaController.text,
      preco: ProdutoValidators.parseNumero(_precoController.text) ?? 0.0,
      precoPromocional: ProdutoValidators.parseNumero(_precoPromocionalController.text),
      imagemUrl: widget.kitInicial?.imagemUrl ?? '',
      imagemUrlSecundaria: widget.kitInicial?.imagemUrlSecundaria,
      ativo: _ativo,
      exibirNoCatalogo: _exibirNoCatalogo,
      destacar: _destacar,
      componentes: _componentes,
    );

    try {
      final kitProvider = context.read<KitProdutoProvider>();
      if (_editando) {
        await kitProvider.atualizarKit(kit);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kit atualizado!')));
          Navigator.of(context).pop();
        }
      } else {
        final kitCriado = await kitProvider.adicionarKit(kit);
        if (mounted && kitCriado.id != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Kit criado! Agora adicione uma foto.')),
          );
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => GerenciarMidiasProdutoScreen(produtoId: kitCriado.id!)),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar kit: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final precoCheio = _precoCheioComponentes;
    final precoKit = ProdutoValidators.parseNumero(_precoController.text) ?? 0.0;
    final economia = precoCheio > 0 && precoKit > 0 && precoKit < precoCheio
        ? ((precoCheio - precoKit) / precoCheio * 100)
        : null;

    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar Kit' : 'Novo Kit')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FormSection(
                titulo: 'Identificação',
                children: [
                  TextFormField(
                    controller: _nomeController,
                    decoration: const InputDecoration(labelText: 'Nome do Kit'),
                    validator: ProdutoValidators.nome,
                  ),
                  !_categoriasCarregadas
                      ? const Center(child: CircularProgressIndicator())
                      : DropdownButtonFormField<String>(
                          decoration: const InputDecoration(labelText: 'Categoria'),
                          value: _categorias.contains(_categoriaController.text)
                              ? _categoriaController.text
                              : null,
                          items: [
                            for (final categoria in _categorias)
                              DropdownMenuItem(value: categoria, child: Text(categoria)),
                          ],
                          onChanged: (value) => setState(() => _categoriaController.text = value ?? ''),
                          validator: ProdutoValidators.categoria,
                        ),
                  TextFormField(
                    controller: _descricaoController,
                    decoration: const InputDecoration(labelText: 'Descrição'),
                    maxLines: 3,
                    validator: ProdutoValidators.descricao,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              FormSection(
                titulo: 'Componentes do kit',
                children: [
                  if (_componentes.isEmpty)
                    Text(
                      'Nenhum produto adicionado ainda.',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  for (final c in _componentes)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(c.nome),
                      subtitle: Text('${c.quantidade}x  •  R\$ ${c.preco.toStringAsFixed(2)} cada'),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => _removerComponente(c.produtoId),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: _adicionarComponente,
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar produto'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              FormSection(
                titulo: 'Preço',
                children: [
                  TextFormField(
                    controller: _precoController,
                    decoration: const InputDecoration(labelText: 'Preço do Kit (R\$)', prefixText: 'R\$ '),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [MoedaInputFormatter()],
                    validator: ProdutoValidators.precoVenda,
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_componentes.isNotEmpty)
                    Text(
                      economia != null
                          ? 'Soma dos componentes: R\$ ${precoCheio.toStringAsFixed(2)} — economia de ${economia.toStringAsFixed(0)}%'
                          : 'Soma dos componentes: R\$ ${precoCheio.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: economia != null ? colorScheme.primary : colorScheme.onSurfaceVariant,
                        fontWeight: economia != null ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  TextFormField(
                    controller: _precoPromocionalController,
                    decoration: const InputDecoration(
                      labelText: 'Preço Promocional (R\$) (Opcional)',
                      prefixText: 'R\$ ',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [MoedaInputFormatter()],
                    validator: (value) => ProdutoValidators.precoPromocional(value, _precoController.text),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              FormSection(
                titulo: 'Opções',
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Kit Ativo'),
                    value: _ativo,
                    onChanged: (v) => setState(() => _ativo = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Destacar Kit'),
                    value: _destacar,
                    onChanged: (v) => setState(() => _destacar = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Exibir no Catálogo'),
                    value: _exibirNoCatalogo,
                    onChanged: (v) => setState(() => _exibirNoCatalogo = v),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _salvar,
                      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                      child: Text(_editando ? 'Salvar Alterações' : 'Criar Kit'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeletorProdutoSheet extends StatefulWidget {
  final List<Produto> produtos;
  const _SeletorProdutoSheet({required this.produtos});

  @override
  State<_SeletorProdutoSheet> createState() => _SeletorProdutoSheetState();
}

class _SeletorProdutoSheetState extends State<_SeletorProdutoSheet> {
  String _busca = '';

  @override
  Widget build(BuildContext context) {
    final filtrados = widget.produtos.where((p) => contemTodasPalavras(p.nome, _busca)).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Buscar produto',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _busca = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: filtrados.length,
                itemBuilder: (context, i) {
                  final produto = filtrados[i];
                  return ListTile(
                    title: Text(produto.nome),
                    subtitle: Text('R\$ ${produto.preco.toStringAsFixed(2)}'),
                    onTap: () => Navigator.pop(context, produto),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
