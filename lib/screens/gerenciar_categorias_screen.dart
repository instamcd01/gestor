import 'package:flutter/material.dart';
import '../config/supabase_config.dart';

/// Gerencia a hierarquia Departamento -> Categoria -> Subcategoria usada
/// pelo catálogo (Gestor e site público). Diferente de [CategoriaScreen]
/// (produto_categorias_screen.dart), que é um seletor embutido no cadastro
/// de produto, esta é a tela dedicada a organizar/editar a estrutura em si
/// — alcançada por "Configurações do Produto", não pelo cadastro.
class GerenciarCategoriasScreen extends StatefulWidget {
  const GerenciarCategoriasScreen({super.key});

  @override
  State<GerenciarCategoriasScreen> createState() => _GerenciarCategoriasScreenState();
}

class _GerenciarCategoriasScreenState extends State<GerenciarCategoriasScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String? _empresaId;
  bool _carregando = true;

  List<Map<String, dynamic>> _departamentos = []; // {id, nome, ordem}
  List<Map<String, dynamic>> _categorias = []; // {id, nome, ordem, departamento_id}

  String? _categoriaSelecionadaId;
  List<Map<String, dynamic>> _subcategorias = []; // {id, nome, ordem, categoria_id}

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _carregarTudo();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<String?> _obterEmpresaId() async {
    if (_empresaId != null) return _empresaId;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;
    final usuario = await supabase.from('usuarios').select('empresa_id').eq('id', userId).maybeSingle();
    _empresaId = usuario?['empresa_id'] as String?;
    return _empresaId;
  }

  Future<void> _carregarTudo() async {
    final empresaId = await _obterEmpresaId();
    if (empresaId == null) {
      if (mounted) setState(() => _carregando = false);
      return;
    }
    await _carregarDepartamentos();
    await _carregarCategorias();
    if (_categorias.isNotEmpty) {
      _categoriaSelecionadaId = _categorias.first['id'] as String;
      await _carregarSubcategorias();
    }
    if (mounted) setState(() => _carregando = false);
  }

  Future<void> _confirmarESetState(Future<void> Function() acao) async {
    await acao();
    if (mounted) setState(() {});
  }

  Future<bool> _confirmarExclusao(String titulo, String mensagem) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(titulo),
        content: Text(mensagem),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    return confirm == true;
  }

  // ---------------------------------------------------------------------
  // Departamentos
  // ---------------------------------------------------------------------

  Future<void> _carregarDepartamentos() async {
    final data =
        await supabase.from('departamentos').select('id, nome, ordem').order('ordem', ascending: true);
    _departamentos = List<Map<String, dynamic>>.from(data);
  }

  Future<void> _adicionarDepartamento(String nome) async {
    if (nome.isEmpty) return;
    if (_departamentos.any((d) => (d['nome'] as String).toLowerCase() == nome.toLowerCase())) return;
    final empresaId = await _obterEmpresaId();
    if (empresaId == null) return;
    final proximaOrdem = _departamentos.isNotEmpty
        ? _departamentos.map((d) => d['ordem'] as int).reduce((a, b) => a > b ? a : b) + 1
        : 0;
    await supabase.from('departamentos').insert({'nome': nome, 'ordem': proximaOrdem, 'empresa_id': empresaId});
    await _confirmarESetState(_carregarDepartamentos);
  }

  Future<void> _renomearDepartamento(String id, String novoNome) async {
    if (novoNome.isEmpty) return;
    await supabase.from('departamentos').update({'nome': novoNome}).eq('id', id);
    await _confirmarESetState(_carregarDepartamentos);
  }

  Future<void> _excluirDepartamento(String id) async {
    final confirmar = await _confirmarExclusao(
      'Excluir departamento',
      'As categorias desse departamento ficam sem departamento — aparecem em "Outros" no site até você atribuir um novo.',
    );
    if (!confirmar) return;
    await supabase.from('departamentos').delete().eq('id', id);
    await _confirmarESetState(() async {
      await _carregarDepartamentos();
      await _carregarCategorias();
    });
  }

  Future<void> _reordenarDepartamentos(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final item = _departamentos.removeAt(oldIndex);
    _departamentos.insert(newIndex, item);
    for (var i = 0; i < _departamentos.length; i++) {
      await supabase.from('departamentos').update({'ordem': i}).eq('id', _departamentos[i]['id']);
    }
    setState(() {});
  }

  void _editarDepartamentoDialog(Map<String, dynamic> departamento) {
    final controller = TextEditingController(text: departamento['nome'] as String);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar departamento'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Nome')),
        actions: [
          TextButton(
            child: const Text('Excluir', style: TextStyle(color: Colors.red)),
            onPressed: () async {
              Navigator.pop(ctx);
              await _excluirDepartamento(departamento['id'] as String);
            },
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            child: const Text('Salvar'),
            onPressed: () async {
              Navigator.pop(ctx);
              await _renomearDepartamento(departamento['id'] as String, controller.text);
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Categorias
  // ---------------------------------------------------------------------

  Future<void> _carregarCategorias() async {
    final data = await supabase
        .from('categorias')
        .select('id, nome, ordem, departamento_id, ncm, cest')
        .order('ordem', ascending: true);
    _categorias = List<Map<String, dynamic>>.from(data);
  }

  String? _nomeDepartamento(String? departamentoId) {
    if (departamentoId == null) return null;
    final match = _departamentos.where((d) => d['id'] == departamentoId);
    return match.isEmpty ? null : match.first['nome'] as String;
  }

  Future<void> _adicionarCategoria(String nome) async {
    if (nome.isEmpty) return;
    if (_categorias.any((c) => (c['nome'] as String).toLowerCase() == nome.toLowerCase())) return;
    final empresaId = await _obterEmpresaId();
    if (empresaId == null) return;
    final proximaOrdem = _categorias.isNotEmpty
        ? _categorias.map((c) => c['ordem'] as int).reduce((a, b) => a > b ? a : b) + 1
        : 0;
    await supabase.from('categorias').insert({'nome': nome, 'ordem': proximaOrdem, 'empresa_id': empresaId});
    await _confirmarESetState(_carregarCategorias);
  }

  Future<void> _editarCategoria(
    String id,
    String novoNome,
    String? departamentoId,
    String? ncm,
    String? cest,
  ) async {
    if (novoNome.isEmpty) return;
    final antigoNome = _categorias.firstWhere((c) => c['id'] == id)['nome'] as String;
    await supabase.from('categorias').update({
      'nome': novoNome,
      'departamento_id': departamentoId,
      'ncm': ncm?.isEmpty == true ? null : ncm,
      'cest': cest?.isEmpty == true ? null : cest,
    }).eq('id', id);
    if (novoNome != antigoNome) {
      await supabase.from('produtos').update({'categoria': novoNome}).eq('categoria', antigoNome);
    }
    await _confirmarESetState(_carregarCategorias);
  }

  Future<void> _excluirCategoria(String id) async {
    final confirmar = await _confirmarExclusao(
      'Excluir categoria',
      'Os produtos que a utilizam ficam como "Sem categoria". As subcategorias dela também são excluídas.',
    );
    if (!confirmar) return;
    final antigoNome = _categorias.firstWhere((c) => c['id'] == id)['nome'] as String;
    await supabase.from('produtos').update({'categoria': 'Sem categoria'}).eq('categoria', antigoNome);
    await supabase.from('categorias').delete().eq('id', id); // subcategorias caem via cascade
    await _confirmarESetState(_carregarCategorias);
  }

  Future<void> _reordenarCategorias(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final item = _categorias.removeAt(oldIndex);
    _categorias.insert(newIndex, item);
    for (var i = 0; i < _categorias.length; i++) {
      await supabase.from('categorias').update({'ordem': i}).eq('id', _categorias[i]['id']);
    }
    setState(() {});
  }

  void _editarCategoriaDialog(Map<String, dynamic> categoria) {
    final controller = TextEditingController(text: categoria['nome'] as String);
    final ncmController = TextEditingController(text: categoria['ncm'] as String? ?? '');
    final cestController = TextEditingController(text: categoria['cest'] as String? ?? '');
    String? departamentoSelecionado = categoria['departamento_id'] as String?;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setStateDialog) => AlertDialog(
          title: const Text('Editar categoria'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: controller, decoration: const InputDecoration(labelText: 'Nome')),
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  decoration: const InputDecoration(labelText: 'Departamento'),
                  initialValue: departamentoSelecionado,
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Sem departamento')),
                    for (final d in _departamentos)
                      DropdownMenuItem<String?>(value: d['id'] as String, child: Text(d['nome'] as String)),
                  ],
                  onChanged: (v) => setStateDialog(() => departamentoSelecionado = v),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ncmController,
                  decoration: const InputDecoration(
                    labelText: 'NCM (Opcional)',
                    helperText: 'Classificação fiscal — geralmente igual pra toda a categoria',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: cestController,
                  decoration: const InputDecoration(labelText: 'CEST (Opcional)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Excluir', style: TextStyle(color: Colors.red)),
              onPressed: () async {
                Navigator.pop(ctx);
                await _excluirCategoria(categoria['id'] as String);
              },
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              child: const Text('Salvar'),
              onPressed: () async {
                Navigator.pop(ctx);
                await _editarCategoria(
                  categoria['id'] as String,
                  controller.text,
                  departamentoSelecionado,
                  ncmController.text,
                  cestController.text,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // Subcategorias (sempre escopadas a uma categoria — o mesmo texto, ex.
  // "Adultos", significa coisas diferentes em categorias diferentes)
  // ---------------------------------------------------------------------

  Future<void> _carregarSubcategorias() async {
    if (_categoriaSelecionadaId == null) {
      _subcategorias = [];
      return;
    }
    final data = await supabase
        .from('subcategorias')
        .select('id, nome, ordem, categoria_id')
        .eq('categoria_id', _categoriaSelecionadaId!)
        .order('ordem', ascending: true);
    _subcategorias = List<Map<String, dynamic>>.from(data);
  }

  Future<void> _selecionarCategoriaParaSubcategorias(String categoriaId) async {
    _categoriaSelecionadaId = categoriaId;
    await _confirmarESetState(_carregarSubcategorias);
  }

  Future<void> _adicionarSubcategoria(String nome) async {
    if (nome.isEmpty || _categoriaSelecionadaId == null) return;
    if (_subcategorias.any((s) => (s['nome'] as String).toLowerCase() == nome.toLowerCase())) return;
    final empresaId = await _obterEmpresaId();
    if (empresaId == null) return;
    final proximaOrdem = _subcategorias.isNotEmpty
        ? _subcategorias.map((s) => s['ordem'] as int).reduce((a, b) => a > b ? a : b) + 1
        : 0;
    await supabase.from('subcategorias').insert({
      'nome': nome,
      'ordem': proximaOrdem,
      'empresa_id': empresaId,
      'categoria_id': _categoriaSelecionadaId,
    });
    await _confirmarESetState(_carregarSubcategorias);
  }

  Future<void> _editarSubcategoria(String id, String novoNome) async {
    if (novoNome.isEmpty || _categoriaSelecionadaId == null) return;
    final antigoNome = _subcategorias.firstWhere((s) => s['id'] == id)['nome'] as String;
    final categoriaNome = _categorias.firstWhere((c) => c['id'] == _categoriaSelecionadaId)['nome'] as String;
    await supabase.from('subcategorias').update({'nome': novoNome}).eq('id', id);
    if (novoNome != antigoNome) {
      await supabase
          .from('produtos')
          .update({'subcategoria': novoNome})
          .eq('categoria', categoriaNome)
          .eq('subcategoria', antigoNome);
    }
    await _confirmarESetState(_carregarSubcategorias);
  }

  Future<void> _excluirSubcategoria(String id) async {
    final confirmar = await _confirmarExclusao(
      'Excluir subcategoria',
      'Os produtos que a utilizam ficam sem subcategoria.',
    );
    if (!confirmar) return;
    final antigoNome = _subcategorias.firstWhere((s) => s['id'] == id)['nome'] as String;
    final categoriaNome = _categorias.firstWhere((c) => c['id'] == _categoriaSelecionadaId)['nome'] as String;
    await supabase
        .from('produtos')
        .update({'subcategoria': null})
        .eq('categoria', categoriaNome)
        .eq('subcategoria', antigoNome);
    await supabase.from('subcategorias').delete().eq('id', id);
    await _confirmarESetState(_carregarSubcategorias);
  }

  Future<void> _reordenarSubcategorias(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final item = _subcategorias.removeAt(oldIndex);
    _subcategorias.insert(newIndex, item);
    for (var i = 0; i < _subcategorias.length; i++) {
      await supabase.from('subcategorias').update({'ordem': i}).eq('id', _subcategorias[i]['id']);
    }
    setState(() {});
  }

  void _editarSubcategoriaDialog(Map<String, dynamic> subcategoria) {
    final controller = TextEditingController(text: subcategoria['nome'] as String);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Editar subcategoria'),
        content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Nome')),
        actions: [
          TextButton(
            child: const Text('Excluir', style: TextStyle(color: Colors.red)),
            onPressed: () async {
              Navigator.pop(ctx);
              await _excluirSubcategoria(subcategoria['id'] as String);
            },
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            child: const Text('Salvar'),
            onPressed: () async {
              Navigator.pop(ctx);
              await _editarSubcategoria(subcategoria['id'] as String, controller.text);
            },
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Categorias'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Departamentos'),
            Tab(text: 'Categorias'),
            Tab(text: 'Subcategorias'),
          ],
        ),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [_abaDepartamentos(), _abaCategorias(), _abaSubcategorias()],
            ),
    );
  }

  Widget _abaDepartamentos() {
    return _AbaLista(
      itens: _departamentos,
      subtitulo: (_) => null,
      onReorder: _reordenarDepartamentos,
      onTapEditar: _editarDepartamentoDialog,
      onAdicionar: _adicionarDepartamento,
      rotuloNovo: 'Novo departamento',
    );
  }

  Widget _abaCategorias() {
    return _AbaLista(
      itens: _categorias,
      subtitulo: (c) => _nomeDepartamento(c['departamento_id'] as String?) ?? 'Sem departamento',
      onReorder: _reordenarCategorias,
      onTapEditar: _editarCategoriaDialog,
      onAdicionar: _adicionarCategoria,
      rotuloNovo: 'Nova categoria',
    );
  }

  Widget _abaSubcategorias() {
    if (_categorias.isEmpty) {
      return const Center(child: Text('Cadastre uma categoria primeiro.'));
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: 'Categoria'),
            initialValue: _categoriaSelecionadaId,
            items: [
              for (final c in _categorias)
                DropdownMenuItem<String>(value: c['id'] as String, child: Text(c['nome'] as String)),
            ],
            onChanged: (v) {
              if (v != null) _selecionarCategoriaParaSubcategorias(v);
            },
          ),
        ),
        Expanded(
          child: _AbaLista(
            itens: _subcategorias,
            subtitulo: (_) => null,
            onReorder: _reordenarSubcategorias,
            onTapEditar: _editarSubcategoriaDialog,
            onAdicionar: _adicionarSubcategoria,
            rotuloNovo: 'Nova subcategoria',
          ),
        ),
      ],
    );
  }
}

/// Lista reordenável com adicionar/editar — mesmo esqueleto reaproveitado
/// pelas 3 abas (departamentos, categorias, subcategorias), com o texto do
/// subtítulo por item e a ação de adicionar customizados por quem chama.
class _AbaLista extends StatefulWidget {
  final List<Map<String, dynamic>> itens;
  final String? Function(Map<String, dynamic>) subtitulo;
  final void Function(int oldIndex, int newIndex) onReorder;
  final void Function(Map<String, dynamic>) onTapEditar;
  final void Function(String nome) onAdicionar;
  final String rotuloNovo;

  const _AbaLista({
    required this.itens,
    required this.subtitulo,
    required this.onReorder,
    required this.onTapEditar,
    required this.onAdicionar,
    required this.rotuloNovo,
  });

  @override
  State<_AbaLista> createState() => _AbaListaState();
}

class _AbaListaState extends State<_AbaLista> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: widget.itens.isEmpty
              ? const Center(child: Text('Nada cadastrado ainda.'))
              : ReorderableListView(
                  padding: const EdgeInsets.all(16),
                  onReorder: widget.onReorder,
                  children: [
                    for (final item in widget.itens)
                      Card(
                        key: ValueKey(item['id']),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(item['nome'] as String),
                          subtitle: widget.subtitulo(item) != null ? Text(widget.subtitulo(item)!) : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: 'Editar',
                                onPressed: () => widget.onTapEditar(item),
                              ),
                              const Icon(Icons.drag_handle),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: InputDecoration(labelText: widget.rotuloNovo),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () {
                  if (_controller.text.isNotEmpty) {
                    widget.onAdicionar(_controller.text);
                    _controller.clear();
                  }
                },
                child: const Text('Adicionar'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
