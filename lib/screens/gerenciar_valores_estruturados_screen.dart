import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/supabase_config.dart';
import '../providers/auth_provider.dart';
import '../repositories/valor_estruturado_repository.dart';

/// Gerencia o vocabulário curado dos 8 campos estruturados de variante
/// (`valores_estruturados_variante`) — renomear um valor cascateia pra
/// todos os produtos que o usam (mesmo padrão de `CategoriaScreen` em
/// produto_categorias_screen.dart), e excluir só tira da lista de
/// sugestões (produtos que já usam o valor mantêm o texto deles). Diferente
/// de categoria, aqui existem 8 campos e cada um pode ser escopado a uma
/// categoria específica ou "global" — por isso os dois seletores no topo.
class GerenciarValoresEstruturadosScreen extends StatefulWidget {
  /// Categoria da tela que abriu esta ("Sabor" faz mais sentido mostrado já
  /// filtrado pra "Ração" do que pra "qualquer categoria"). `null`/vazio
  /// abre em "Global".
  final String? categoriaInicial;

  const GerenciarValoresEstruturadosScreen({super.key, this.categoriaInicial});

  @override
  State<GerenciarValoresEstruturadosScreen> createState() => _GerenciarValoresEstruturadosScreenState();
}

class _GerenciarValoresEstruturadosScreenState extends State<GerenciarValoresEstruturadosScreen> {
  final _repository = ValorEstruturadoRepository();
  final _novoValorController = TextEditingController();

  String _campo = 'sabor';
  String? _categoriaEscopo;
  List<String> _categoriasDisponiveis = [];
  List<Map<String, dynamic>> _valores = [];
  bool _carregando = true;
  bool _processando = false;

  @override
  void initState() {
    super.initState();
    _categoriaEscopo = (widget.categoriaInicial?.isNotEmpty ?? false) ? widget.categoriaInicial : null;
    _carregarCategorias();
    _carregarValores();
  }

  @override
  void dispose() {
    _novoValorController.dispose();
    super.dispose();
  }

  Future<void> _carregarCategorias() async {
    try {
      final data = await supabase.from('categorias').select('nome').order('nome');
      if (!mounted) return;
      setState(() => _categoriasDisponiveis = (data as List).map((c) => c['nome'] as String).toList());
    } catch (e) {
      debugPrint('Erro ao carregar categorias: $e');
    }
  }

  Future<void> _carregarValores() async {
    setState(() => _carregando = true);
    try {
      final valores = await _repository.listar(campo: _campo, categoria: _categoriaEscopo);
      if (!mounted) return;
      setState(() {
        _valores = valores;
        _carregando = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar valores estruturados: $e');
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _adicionar() async {
    final valor = _novoValorController.text.trim();
    if (valor.isEmpty) return;
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;

    setState(() => _processando = true);
    try {
      await _repository.adicionar(empresaId: empresaId, campo: _campo, categoria: _categoriaEscopo, valor: valor);
      _novoValorController.clear();
      await _carregarValores();
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _excluir(Map<String, dynamic> item) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir valor'),
        content: Text(
          'Remove "${item['valor']}" da lista de sugestões. Produtos que já usam esse valor não são alterados.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmou != true) return;

    setState(() => _processando = true);
    try {
      await _repository.excluir(item['id'] as String);
      await _carregarValores();
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _editarDialog(Map<String, dynamic> item) async {
    final controllerEdicao = TextEditingController(text: item['valor'] as String);
    String? mesclarCom;

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Editar valor'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controllerEdicao,
                decoration: const InputDecoration(labelText: 'Novo texto'),
                enabled: mesclarCom == null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: mesclarCom,
                decoration: const InputDecoration(labelText: 'Ou mesclar com um já existente'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Não mesclar')),
                  for (final outro in _valores.where((v) => v['id'] != item['id']))
                    DropdownMenuItem(value: outro['valor'] as String, child: Text(outro['valor'] as String)),
                ],
                onChanged: (v) => setStateDialog(() => mesclarCom = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (confirmou != true) return;

    final novoValor = mesclarCom ?? controllerEdicao.text.trim();
    if (novoValor.isEmpty) return;

    setState(() => _processando = true);
    try {
      await _repository.renomear(
        id: item['id'] as String,
        campo: _campo,
        categoria: _categoriaEscopo,
        valorAntigo: item['valor'] as String,
        novoValor: novoValor,
      );
      // Mesclar: o valor antigo vira duplicata do escolhido — some da lista.
      if (mesclarCom != null) await _repository.excluir(item['id'] as String);
      await _carregarValores();
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Valores sugeridos')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _campo,
                    decoration: const InputDecoration(labelText: 'Campo'),
                    items: [
                      for (final entrada in rotulosCamposEstruturados.entries)
                        DropdownMenuItem(value: entrada.key, child: Text(entrada.value)),
                    ],
                    onChanged: (v) {
                      setState(() => _campo = v!);
                      _carregarValores();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: _categoriaEscopo,
                    decoration: const InputDecoration(labelText: 'Categoria'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Global (qualquer categoria)')),
                      for (final categoria in _categoriasDisponiveis)
                        DropdownMenuItem(value: categoria, child: Text(categoria)),
                    ],
                    onChanged: (v) {
                      setState(() => _categoriaEscopo = v);
                      _carregarValores();
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Valores globais aparecem como sugestão em qualquer categoria, '
                'além dos específicos da categoria escolhida.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : _valores.isEmpty
                    ? const Center(child: Text('Nenhum valor cadastrado ainda pra esse campo/categoria'))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        itemCount: _valores.length,
                        itemBuilder: (context, index) {
                          final item = _valores[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              title: Text(item['valor'] as String),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Editar',
                                    icon: const Icon(Icons.edit_outlined),
                                    onPressed: _processando ? null : () => _editarDialog(item),
                                  ),
                                  IconButton(
                                    tooltip: 'Excluir',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: _processando ? null : () => _excluir(item),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _novoValorController,
                      decoration: const InputDecoration(labelText: 'Novo valor'),
                      onSubmitted: (_) => _adicionar(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _processando ? null : _adicionar,
                    child: const Text('Adicionar'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
