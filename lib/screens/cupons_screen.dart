import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/cupom.dart';
import '../models/produto.dart';
import '../providers/cupom_provider.dart';
import '../providers/produto_provider.dart';
import '../repositories/cupom_repository.dart';
import '../utils/formatadores_input.dart';
import '../utils/produto_validators.dart';
import '../widgets/estado_erro_lista.dart';
import '../widgets/form_section.dart';

class CuponsScreen extends StatefulWidget {
  const CuponsScreen({super.key});

  @override
  State<CuponsScreen> createState() => _CuponsScreenState();
}

class _CuponsScreenState extends State<CuponsScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Provider.of<CupomProvider>(context, listen: false).carregar();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Cupom> _filtrados(List<Cupom> todos) {
    final termo = _searchController.text.toLowerCase();
    if (termo.isEmpty) return todos;
    return todos.where((c) => c.codigo.toLowerCase().contains(termo)).toList();
  }

  Future<void> _abrirFormulario({Cupom? cupom}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _CupomFormScreen(cupom: cupom)),
    );
  }

  Future<void> _alternarAtivo(Cupom cupom) async {
    try {
      await context.read<CupomProvider>().alternarAtivo(cupom);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível alterar o cupom: $e')),
      );
    }
  }

  String _resumoLinha(Cupom c) {
    final valor = c.tipoDesconto == TipoDescontoCupom.percentual
        ? '${c.valor.toStringAsFixed(0)}%'
        : 'R\$ ${c.valor.toStringAsFixed(2)}';
    final escopo = switch (c.escopoTipo) {
      EscopoCupom.pedido => 'pedido todo',
      EscopoCupom.categoria => 'categoria "${c.escopoValor}"',
      EscopoCupom.subcategoria => 'subcategoria "${c.escopoValor}"',
      EscopoCupom.marca => 'marca "${c.escopoValor}"',
      EscopoCupom.produtos => 'produtos específicos',
    };
    final partes = <String>['$valor no $escopo', '${c.usos} uso${c.usos == 1 ? '' : 's'}'];
    if (c.clienteNome != null) partes.add('exclusivo de ${c.clienteNome}');
    if (c.vendedorNome != null) partes.add('indicação de ${c.vendedorNome}');
    return partes.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CupomProvider>();
    final cupons = _filtrados(provider.cupons);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cupons de desconto'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Novo cupom',
            onPressed: () => _abrirFormulario(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Pesquisar código...',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          if (provider.carregando)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (provider.erro != null)
            Expanded(
              child: EstadoErroLista(mensagem: provider.erro!, onTentarNovamente: provider.carregar),
            )
          else if (cupons.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.local_offer_outlined, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(height: 16),
                    Text(
                      _searchController.text.isNotEmpty ? 'Nenhum cupom encontrado' : 'Nenhum cupom cadastrado ainda',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _searchController.text.isNotEmpty
                          ? 'Tente buscar por outro código.'
                          : 'Toque no "+" pra criar o primeiro.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: provider.carregar,
                child: ListView.builder(
                  itemCount: cupons.length,
                  itemBuilder: (context, index) {
                    final cupom = cupons[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: cupom.ativo ? Colors.green.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.2),
                          child: Icon(Icons.local_offer, color: cupom.ativo ? Colors.green : Colors.grey, size: 20),
                        ),
                        title: Text(cupom.codigo, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text(_resumoLinha(cupom), maxLines: 2, overflow: TextOverflow.ellipsis),
                        isThreeLine: true,
                        onTap: () => _abrirFormulario(cupom: cupom),
                        trailing: Switch(
                          value: cupom.ativo,
                          onChanged: (_) => _alternarAtivo(cupom),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CupomFormScreen extends StatefulWidget {
  final Cupom? cupom;

  const _CupomFormScreen({this.cupom});

  @override
  State<_CupomFormScreen> createState() => _CupomFormScreenState();
}

class _CupomFormScreenState extends State<_CupomFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _codigoController;
  late final TextEditingController _valorController;
  late final TextEditingController _escopoValorController;
  late final TextEditingController _valorMinimoController;
  late final TextEditingController _usoMaximoController;
  late final TextEditingController _usoMaximoPorClienteController;
  late final TextEditingController _descricaoController;

  TipoDescontoCupom _tipoDesconto = TipoDescontoCupom.percentual;
  EscopoCupom _escopoTipo = EscopoCupom.pedido;
  DateTime? _dataExpiracao;
  bool _ativo = true;
  bool _salvando = false;
  List<Produto> _produtosSelecionados = [];
  bool _carregandoProdutos = false;

  bool get _editando => widget.cupom != null;

  @override
  void initState() {
    super.initState();
    final c = widget.cupom;
    _codigoController = TextEditingController(text: c?.codigo ?? '');
    _valorController = TextEditingController(text: c != null ? ProdutoValidators.formatarMoeda(c.valor) : '');
    _escopoValorController = TextEditingController(text: c?.escopoValor ?? '');
    _valorMinimoController = TextEditingController(
      text: c?.valorMinimoPedido != null ? ProdutoValidators.formatarMoeda(c!.valorMinimoPedido!) : '',
    );
    _usoMaximoController = TextEditingController(text: c?.usoMaximo?.toString() ?? '');
    _usoMaximoPorClienteController = TextEditingController(text: c?.usoMaximoPorCliente?.toString() ?? '');
    _descricaoController = TextEditingController(text: c?.descricao ?? '');
    _tipoDesconto = c?.tipoDesconto ?? TipoDescontoCupom.percentual;
    _escopoTipo = c?.escopoTipo ?? EscopoCupom.pedido;
    _dataExpiracao = c?.dataExpiracao;
    _ativo = c?.ativo ?? true;

    if (_editando && _escopoTipo == EscopoCupom.produtos) {
      _carregarProdutosSelecionados();
    }
  }

  Future<void> _carregarProdutosSelecionados() async {
    setState(() => _carregandoProdutos = true);
    try {
      final ids = await CupomRepository().listarProdutoIds(widget.cupom!.id!);
      if (!mounted) return;
      final todos = context.read<ProdutoProvider>().produtos;
      setState(() {
        _produtosSelecionados = todos.where((p) => ids.contains(p.id)).toList();
      });
    } catch (e) {
      debugPrint('Erro ao carregar produtos do cupom: $e');
    } finally {
      if (mounted) setState(() => _carregandoProdutos = false);
    }
  }

  @override
  void dispose() {
    _codigoController.dispose();
    _valorController.dispose();
    _escopoValorController.dispose();
    _valorMinimoController.dispose();
    _usoMaximoController.dispose();
    _usoMaximoPorClienteController.dispose();
    _descricaoController.dispose();
    super.dispose();
  }

  Future<void> _selecionarProdutos() async {
    final todos = context.read<ProdutoProvider>().produtos;
    final selecionadosIds = _produtosSelecionados.map((p) => p.id).toSet();

    final resultado = await showModalBottomSheet<List<Produto>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final buscaController = TextEditingController();
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            final filtrados = buscaController.text.isEmpty
                ? todos
                : todos.where((p) => p.nome.toLowerCase().contains(buscaController.text.toLowerCase())).toList();
            return SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.8,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: buscaController,
                      decoration: const InputDecoration(hintText: 'Buscar produto...', prefixIcon: Icon(Icons.search)),
                      onChanged: (_) => setModalState(() {}),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtrados.length,
                      itemBuilder: (ctx, i) {
                        final p = filtrados[i];
                        final marcado = selecionadosIds.contains(p.id);
                        return CheckboxListTile(
                          title: Text(p.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
                          value: marcado,
                          onChanged: (v) => setModalState(() {
                            if (v == true) {
                              selecionadosIds.add(p.id);
                            } else {
                              selecionadosIds.remove(p.id);
                            }
                          }),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(
                        ctx,
                        todos.where((p) => selecionadosIds.contains(p.id)).toList(),
                      ),
                      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                      child: Text('Confirmar (${selecionadosIds.length})'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (resultado != null && mounted) {
      setState(() => _produtosSelecionados = resultado);
    }
  }

  Future<void> _escolherDataExpiracao() async {
    final data = await showDatePicker(
      context: context,
      initialDate: _dataExpiracao ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (data != null) setState(() => _dataExpiracao = data);
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_escopoTipo == EscopoCupom.produtos && _produtosSelecionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione ao menos um produto pra esse cupom.')),
      );
      return;
    }

    setState(() => _salvando = true);

    final cupom = Cupom(
      id: widget.cupom?.id,
      codigo: _codigoController.text.trim(),
      tipoDesconto: _tipoDesconto,
      valor: ProdutoValidators.parseNumero(_valorController.text) ?? 0,
      escopoTipo: _escopoTipo,
      escopoValor: [EscopoCupom.categoria, EscopoCupom.subcategoria, EscopoCupom.marca].contains(_escopoTipo)
          ? _escopoValorController.text.trim()
          : null,
      clienteId: widget.cupom?.clienteId,
      vendedorId: widget.cupom?.vendedorId,
      origem: widget.cupom?.origem ?? 'manual',
      valorMinimoPedido: ProdutoValidators.parseNumero(_valorMinimoController.text),
      usoMaximo: int.tryParse(_usoMaximoController.text.trim()),
      usoMaximoPorCliente: int.tryParse(_usoMaximoPorClienteController.text.trim()),
      dataExpiracao: _dataExpiracao,
      ativo: _ativo,
      descricao: _descricaoController.text.trim().isEmpty ? null : _descricaoController.text.trim(),
    );

    final produtoIds = _escopoTipo == EscopoCupom.produtos ? _produtosSelecionados.map((p) => p.id!).toList() : null;

    try {
      final provider = context.read<CupomProvider>();
      if (_editando) {
        await provider.atualizar(cupom, produtoIds: produtoIds);
      } else {
        await provider.adicionar(cupom, produtoIds: produtoIds ?? []);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar cupom: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ehAutomatico = widget.cupom?.origem == 'auto_cliente' || widget.cupom?.origem == 'auto_vendedor';

    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar cupom' : 'Novo cupom')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (ehAutomatico)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        widget.cupom!.origem == 'auto_cliente'
                            ? 'Gerado automaticamente no cadastro de ${widget.cupom!.clienteNome ?? "um cliente"}.'
                            : 'Código de indicação automático de ${widget.cupom!.vendedorNome ?? "um vendedor"}.',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ),
              FormSection(
                titulo: 'Desconto',
                children: [
                  TextFormField(
                    controller: _codigoController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Código'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o código' : null,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<TipoDescontoCupom>(
                          initialValue: _tipoDesconto,
                          decoration: const InputDecoration(labelText: 'Tipo'),
                          items: const [
                            DropdownMenuItem(value: TipoDescontoCupom.percentual, child: Text('Percentual (%)')),
                            DropdownMenuItem(value: TipoDescontoCupom.fixo, child: Text('Valor fixo (R\$)')),
                          ],
                          onChanged: (v) => setState(() => _tipoDesconto = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _valorController,
                          decoration: InputDecoration(
                            labelText: 'Valor',
                            prefixText: _tipoDesconto == TipoDescontoCupom.fixo ? 'R\$ ' : null,
                            suffixText: _tipoDesconto == TipoDescontoCupom.percentual ? '%' : null,
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [DecimalInputFormatter()],
                          validator: (v) => (ProdutoValidators.parseNumero(v) ?? 0) > 0 ? null : 'Informe um valor',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FormSection(
                titulo: 'Onde vale',
                children: [
                  DropdownButtonFormField<EscopoCupom>(
                    initialValue: _escopoTipo,
                    decoration: const InputDecoration(labelText: 'Aplica em'),
                    items: const [
                      DropdownMenuItem(value: EscopoCupom.pedido, child: Text('Pedido inteiro')),
                      DropdownMenuItem(value: EscopoCupom.categoria, child: Text('Uma categoria')),
                      DropdownMenuItem(value: EscopoCupom.subcategoria, child: Text('Uma subcategoria')),
                      DropdownMenuItem(value: EscopoCupom.marca, child: Text('Uma marca')),
                      DropdownMenuItem(value: EscopoCupom.produtos, child: Text('Produtos específicos')),
                    ],
                    onChanged: (v) => setState(() => _escopoTipo = v!),
                  ),
                  if ([EscopoCupom.categoria, EscopoCupom.subcategoria, EscopoCupom.marca].contains(_escopoTipo))
                    TextFormField(
                      controller: _escopoValorController,
                      decoration: InputDecoration(
                        labelText: _escopoTipo == EscopoCupom.categoria
                            ? 'Nome da categoria'
                            : _escopoTipo == EscopoCupom.subcategoria
                                ? 'Nome da subcategoria'
                                : 'Nome da marca',
                        helperText: 'Precisa bater exatamente com o valor cadastrado no produto.',
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o valor' : null,
                    ),
                  if (_escopoTipo == EscopoCupom.produtos) ...[
                    const SizedBox(height: 4),
                    OutlinedButton.icon(
                      onPressed: _carregandoProdutos ? null : _selecionarProdutos,
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: Text(_produtosSelecionados.isEmpty
                          ? 'Selecionar produtos'
                          : '${_produtosSelecionados.length} produto${_produtosSelecionados.length == 1 ? '' : 's'} selecionado${_produtosSelecionados.length == 1 ? '' : 's'}'),
                    ),
                    if (_produtosSelecionados.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _produtosSelecionados
                              .map((p) => Chip(
                                    label: Text(p.nome, style: const TextStyle(fontSize: 12)),
                                    onDeleted: () => setState(() => _produtosSelecionados.remove(p)),
                                  ))
                              .toList(),
                        ),
                      ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              FormSection(
                titulo: 'Limites (opcional)',
                children: [
                  TextFormField(
                    controller: _valorMinimoController,
                    decoration: const InputDecoration(labelText: 'Valor mínimo do pedido', prefixText: 'R\$ '),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [DecimalInputFormatter()],
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _usoMaximoController,
                          decoration: const InputDecoration(labelText: 'Usos totais', helperText: 'Vazio = ilimitado'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _usoMaximoPorClienteController,
                          decoration: const InputDecoration(labelText: 'Usos por cliente', helperText: 'Vazio = ilimitado'),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Data de expiração'),
                    subtitle: Text(_dataExpiracao != null
                        ? '${_dataExpiracao!.day.toString().padLeft(2, '0')}/${_dataExpiracao!.month.toString().padLeft(2, '0')}/${_dataExpiracao!.year}'
                        : 'Sem expiração'),
                    trailing: Wrap(
                      children: [
                        if (_dataExpiracao != null)
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(() => _dataExpiracao = null),
                          ),
                        IconButton(
                          icon: const Icon(Icons.calendar_today_outlined),
                          onPressed: _escolherDataExpiracao,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FormSection(
                titulo: 'Outros',
                children: [
                  TextFormField(
                    controller: _descricaoController,
                    decoration: const InputDecoration(labelText: 'Descrição interna (Opcional)'),
                    maxLines: 2,
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Ativo'),
                    subtitle: const Text('Desligado impede novos usos, sem apagar o histórico.'),
                    value: _ativo,
                    onChanged: (v) => setState(() => _ativo = v),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _salvando ? null : _salvar,
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                child: _salvando
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary),
                      )
                    : const Text('Salvar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
