import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/fornecedor.dart';
import '../providers/fornecedor_provider.dart';
import '../utils/formatadores_input.dart';
import '../utils/produto_validators.dart';
import '../widgets/estado_erro_lista.dart';
import '../widgets/form_section.dart';

class FornecedoresScreen extends StatefulWidget {
  const FornecedoresScreen({super.key});

  @override
  State<FornecedoresScreen> createState() => _FornecedoresScreenState();
}

class _FornecedoresScreenState extends State<FornecedoresScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Provider.of<FornecedorProvider>(context, listen: false).carregar();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Fornecedor> _filtrados(List<Fornecedor> todos) {
    final termo = _searchController.text.toLowerCase();
    if (termo.isEmpty) return todos;
    return todos.where((f) => f.nome.toLowerCase().contains(termo)).toList();
  }

  Future<void> _abrirFormulario({Fornecedor? fornecedor}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _FornecedorFormScreen(fornecedor: fornecedor)),
    );
  }

  Future<void> _excluir(Fornecedor fornecedor) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Fornecedor'),
        content: Text('Tem certeza que deseja excluir "${fornecedor.nome}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    try {
      await context.read<FornecedorProvider>().excluir(fornecedor.id!);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível excluir: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<FornecedorProvider>();
    final fornecedores = _filtrados(provider.fornecedores);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fornecedores'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Novo fornecedor',
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
                hintText: 'Pesquisar fornecedor...',
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
          else if (fornecedores.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.business_outlined, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    const SizedBox(height: 16),
                    Text(
                      _searchController.text.isNotEmpty ? 'Nenhum fornecedor encontrado' : 'Nenhum fornecedor cadastrado ainda',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _searchController.text.isNotEmpty
                          ? 'Tente buscar por outro termo.'
                          : 'Toque no "+" pra cadastrar o primeiro.',
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
                  itemCount: fornecedores.length,
                  itemBuilder: (context, index) {
                    final fornecedor = fornecedores[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: ListTile(
                        title: Text(fornecedor.nome),
                        subtitle: Text(
                          [fornecedor.telefone, fornecedor.cnpjCpf].where((s) => s.isNotEmpty).join(' • '),
                        ),
                        onTap: () => _abrirFormulario(fornecedor: fornecedor),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _excluir(fornecedor),
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

class _FornecedorFormScreen extends StatefulWidget {
  final Fornecedor? fornecedor;

  const _FornecedorFormScreen({this.fornecedor});

  @override
  State<_FornecedorFormScreen> createState() => _FornecedorFormScreenState();
}

class _FornecedorFormScreenState extends State<_FornecedorFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nomeController;
  late final TextEditingController _telefoneController;
  late final TextEditingController _cnpjCpfController;
  late final TextEditingController _emailController;
  late final TextEditingController _observacoesController;
  late final TextEditingController _fatorCustoController;
  bool _salvando = false;

  bool get _editando => widget.fornecedor != null;

  @override
  void initState() {
    super.initState();
    final f = widget.fornecedor;
    _nomeController = TextEditingController(text: f?.nome ?? '');
    _telefoneController = TextEditingController(text: f?.telefone ?? '');
    _cnpjCpfController = TextEditingController(text: f?.cnpjCpf ?? '');
    _emailController = TextEditingController(text: f?.email ?? '');
    _observacoesController = TextEditingController(text: f?.observacoes ?? '');
    _fatorCustoController = TextEditingController(text: ProdutoValidators.formatarMoeda(f?.fatorCusto ?? 1.0));
  }

  @override
  void dispose() {
    _nomeController.dispose();
    _telefoneController.dispose();
    _cnpjCpfController.dispose();
    _emailController.dispose();
    _observacoesController.dispose();
    _fatorCustoController.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _salvando = true);
    final fornecedor = Fornecedor(
      id: widget.fornecedor?.id,
      nome: _nomeController.text.trim(),
      telefone: _telefoneController.text.trim(),
      cnpjCpf: _cnpjCpfController.text.trim(),
      email: _emailController.text.trim(),
      observacoes: _observacoesController.text.trim(),
      fatorCusto: ProdutoValidators.parseNumero(_fatorCustoController.text) ?? 1.0,
    );

    try {
      final provider = context.read<FornecedorProvider>();
      if (_editando) {
        await provider.atualizar(fornecedor);
      } else {
        await provider.adicionar(fornecedor);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar fornecedor: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar Fornecedor' : 'Novo Fornecedor')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FormSection(
                titulo: 'Dados do fornecedor',
                children: [
                  TextFormField(
                    controller: _nomeController,
                    decoration: const InputDecoration(labelText: 'Nome'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
                  ),
                  TextFormField(
                    controller: _telefoneController,
                    decoration: const InputDecoration(labelText: 'Telefone (Opcional)'),
                    keyboardType: TextInputType.phone,
                    inputFormatters: [TelefoneInputFormatter()],
                  ),
                  TextFormField(
                    controller: _cnpjCpfController,
                    decoration: const InputDecoration(labelText: 'CNPJ/CPF (Opcional)'),
                    keyboardType: TextInputType.number,
                  ),
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(labelText: 'E-mail (Opcional)'),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  TextFormField(
                    controller: _observacoesController,
                    decoration: const InputDecoration(labelText: 'Observações (Opcional)'),
                    maxLines: 3,
                  ),
                  TextFormField(
                    controller: _fatorCustoController,
                    decoration: const InputDecoration(
                      labelText: 'Fator de custo',
                      helperText: 'Multiplica o custo unitário da NF-e ao importar. 1,00 = usa o valor da nota sem ajuste.',
                      helperMaxLines: 2,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [DecimalInputFormatter()],
                    validator: (v) => (ProdutoValidators.parseNumero(v) ?? 0) > 0 ? null : 'Informe um valor maior que zero',
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
