import 'package:flutter/material.dart';
import '../config/supabase_config.dart';
import '../widgets/seletor_departamento.dart';

class CategoriaScreen extends StatefulWidget {
  final String? categoriaSelecionada;

  const CategoriaScreen({this.categoriaSelecionada, Key? key}) : super(key: key);

  @override
  _CategoriaScreenState createState() => _CategoriaScreenState();
}

class _CategoriaScreenState extends State<CategoriaScreen> {
  final TextEditingController _categoriaController = TextEditingController();

  List<Map<String, dynamic>> _categorias = []; // {id, nome, ordem, departamento_id}
  Map<String, String> _nomesDepartamentos = {}; // id -> nome
  String? _empresaId;

  @override
  void initState() {
    super.initState();
    if (widget.categoriaSelecionada != null) {
      _categoriaController.text = widget.categoriaSelecionada!;
    }
    _carregarCategorias();
  }

  Future<String?> _obterEmpresaId() async {
    if (_empresaId != null) return _empresaId;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;
    final usuario = await supabase
        .from('usuarios')
        .select('empresa_id')
        .eq('id', userId)
        .maybeSingle();
    _empresaId = usuario?['empresa_id'] as String?;
    return _empresaId;
  }

  Future<void> _carregarCategorias() async {
    try {
      final empresaId = await _obterEmpresaId();
      if (empresaId == null) return;

      // 1️⃣ Carrega categorias já cadastradas
      final categoriasSalvas = await supabase
          .from('categorias')
          .select('id, nome, ordem, departamento_id')
          .order('ordem', ascending: true);
      final departamentos = await supabase.from('departamentos').select('id, nome');

      List<Map<String, dynamic>> categorias =
          List<Map<String, dynamic>>.from(categoriasSalvas);

      // 2️⃣ Busca categorias já usadas em produtos que ainda não estão cadastradas
      final produtos = await supabase.from('produtos').select('categoria');
      final categoriasDeProdutos = (produtos as List)
          .map((p) => (p['categoria'] as String?) ?? '')
          .where((c) => c.isNotEmpty)
          .toSet();

      for (var catProduto in categoriasDeProdutos) {
        if (!categorias.any((c) => (c['nome'] as String).toLowerCase() == catProduto.toLowerCase())) {
          final nova = await supabase
              .from('categorias')
              .insert({
                'nome': catProduto,
                'ordem': categorias.length,
                'empresa_id': empresaId,
              })
              .select()
              .single();
          categorias.add(nova);
        }
      }

      if (!mounted) return;
      setState(() {
        _categorias = categorias;
        _nomesDepartamentos = {
          for (final d in departamentos) d['id'] as String: d['nome'] as String,
        };
      });
    } catch (e) {
      debugPrint('Erro ao carregar categorias: $e');
    }
  }

  Future<void> _adicionarCategoria(String nome, {String? departamentoId}) async {
    if (nome.isEmpty) return;
    if (_categorias.any((c) => (c['nome'] as String).toLowerCase() == nome.toLowerCase())) return;

    final empresaId = await _obterEmpresaId();
    if (empresaId == null) return;

    final proximaOrdem = _categorias.isNotEmpty
        ? _categorias.map((c) => c['ordem'] as int).reduce((a, b) => a > b ? a : b) + 1
        : 0;

    await supabase.from('categorias').insert({
      'nome': nome,
      'ordem': proximaOrdem,
      'empresa_id': empresaId,
      'departamento_id': departamentoId,
    });
    await _carregarCategorias();
  }

  Future<void> _editarCategoria(String? id, String novoNome, {String? departamentoId}) async {
    if (novoNome.isEmpty) return;

    if (_categorias.any(
      (c) => (c['nome'] as String).toLowerCase() == novoNome.toLowerCase() && c['id'] != id,
    )) {
      return;
    }

    if (id != null) {
      final antigaCategoria = _categorias.firstWhere((c) => c['id'] == id)['nome'] as String;

      await supabase.from('categorias').update({
        'nome': novoNome,
        if (departamentoId != null) 'departamento_id': departamentoId,
      }).eq('id', id);

      // Atualiza todos os produtos que usam essa categoria
      await supabase
          .from('produtos')
          .update({'categoria': novoNome})
          .eq('categoria', antigaCategoria);
    } else {
      await _adicionarCategoria(novoNome, departamentoId: departamentoId);
    }

    await _carregarCategorias();
  }

  Future<void> _excluirCategoria(String? id) async {
    if (id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("Excluir categoria"),
        content: Text(
            "Deseja realmente excluir esta categoria? Os produtos que a utilizam ficarão como 'Sem categoria'."),
        actions: [
          TextButton(
            child: Text("Cancelar"),
            onPressed: () => Navigator.pop(context, false),
          ),
          ElevatedButton(
            child: Text("Excluir"),
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final antigaCategoria = _categorias.firstWhere((c) => c['id'] == id)['nome'] as String;

    await supabase
        .from('produtos')
        .update({'categoria': 'Sem categoria'})
        .eq('categoria', antigaCategoria);

    await supabase.from('categorias').delete().eq('id', id);
    await _carregarCategorias();
  }

  Future<void> _reordenarCategorias(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final movedItem = _categorias.removeAt(oldIndex);
    _categorias.insert(newIndex, movedItem);

    for (int i = 0; i < _categorias.length; i++) {
      if (_categorias[i]['id'] != null) {
        await supabase.from('categorias').update({'ordem': i}).eq('id', _categorias[i]['id']);
      }
    }
    setState(() {});
  }

  void _editarCategoriaDialog(int index) {
    final controllerEdicao = TextEditingController(text: _categorias[index]['nome']);
    String? novaSelecionada;
    String? departamentoId = _categorias[index]['departamento_id'] as String?;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text("Editar Categoria"),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controllerEdicao,
                    decoration: InputDecoration(labelText: "Novo nome"),
                  ),
                  SizedBox(height: 16),
                  // Mesclando, a categoria some — departamento não se aplica.
                  if (novaSelecionada == null) ...[
                    Form(
                      key: formKey,
                      child: SeletorDepartamento(
                        valorInicial: departamentoId,
                        onChanged: (v) => departamentoId = v,
                      ),
                    ),
                    SizedBox(height: 16),
                  ],
                  DropdownButton<String>(
                    value: novaSelecionada,
                    hint: Text("Selecionar outra categoria para mesclar"),
                    isExpanded: true,
                    items: _categorias
                        .where((c) => c['id'] != _categorias[index]['id'])
                        .map<DropdownMenuItem<String>>(
                          (c) => DropdownMenuItem<String>(
                            value: c['nome'] as String,
                            child: Text(c['nome'] as String),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      setStateDialog(() {
                        novaSelecionada = val;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  child: Text("Cancelar"),
                  onPressed: () => Navigator.pop(context),
                ),
                TextButton(
                  child: Text("Excluir", style: TextStyle(color: Colors.red)),
                  onPressed: () async {
                    bool confirmar = await showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text("Confirmação"),
                        content: Text(
                            "Deseja realmente excluir esta categoria? Produtos relacionados ficarão como 'Sem categoria'."),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text("Cancelar")),
                          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: Text("Confirmar")),
                        ],
                      ),
                    );
                    if (confirmar) {
                      await _excluirCategoria(_categorias[index]['id']);
                      Navigator.pop(context);
                    }
                  },
                ),
                ElevatedButton(
                  child: Text("Salvar"),
                  onPressed: () async {
                    String antigoNome = _categorias[index]['nome'];
                    if (novaSelecionada != null) {
                      // Mescla produtos pra categoria existente e exclui a antiga
                      await supabase
                          .from('produtos')
                          .update({'categoria': novaSelecionada}).eq('categoria', antigoNome);
                      await supabase.from('categorias').delete().eq('id', _categorias[index]['id']);
                    } else {
                      if (!formKey.currentState!.validate()) return;
                      await _editarCategoria(
                        _categorias[index]['id'],
                        controllerEdicao.text,
                        departamentoId: departamentoId,
                      );
                    }
                    Navigator.pop(context);
                    await _carregarCategorias();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Sem departamento a categoria cai num "Outros" no menu do site — fica
  /// em destaque pra ser corrigida.
  Widget _subtituloDepartamento(Map<String, dynamic> categoria, ColorScheme colorScheme) {
    final nome = _nomesDepartamentos[categoria['departamento_id']];
    if (nome != null) return Text(nome);
    return Text('Sem departamento — aparece em "Outros" no site', style: TextStyle(color: colorScheme.error));
  }

  /// Nova categoria pede nome E departamento juntos: criada só com o nome,
  /// ela ia pro site em "Outros" sem ninguém perceber. Já volta selecionada.
  Future<void> _novaCategoriaDialog() async {
    final nomeController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String? departamentoId;
    final criada = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nova categoria'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nomeController,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Nome'),
                validator: (v) {
                  final nome = v?.trim() ?? '';
                  if (nome.isEmpty) return 'Digite o nome';
                  if (_categorias.any((c) => (c['nome'] as String).toLowerCase() == nome.toLowerCase())) {
                    return 'Já existe uma categoria com esse nome';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              SeletorDepartamento(onChanged: (v) => departamentoId = v),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) Navigator.pop(ctx, nomeController.text.trim());
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (criada == null) return;
    await _adicionarCategoria(criada, departamentoId: departamentoId);
    if (mounted) setState(() => _categoriaController.text = criada);
  }

  void _salvarEVoltar() {
    Navigator.pop(context, _categoriaController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Categorias"),
        actions: [
          TextButton(
            onPressed: _salvarEVoltar,
            // Sem isso o texto sai na cor da marca sobre a AppBar da mesma
            // cor (appBarTheme usa colorScheme.primary) — botão invisível.
            style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onPrimary),
            child: Text("Salvar"),
          )
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _categoriaController,
              readOnly: true,
              decoration: const InputDecoration(
                labelText: "Categoria selecionada",
                suffixIcon: Icon(Icons.arrow_drop_down),
              ),
            ),
          ),
          Expanded(
            child: ReorderableListView(
              onReorder: _reordenarCategorias,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (int index = 0; index < _categorias.length; index++)
                  Builder(
                    key: ValueKey(_categorias[index]['id'] ?? _categorias[index]['nome']),
                    builder: (context) {
                      final colorScheme = Theme.of(context).colorScheme;
                      final selecionada = _categoriaController.text == _categorias[index]['nome'];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: selecionada ? colorScheme.primary.withValues(alpha: 0.1) : null,
                        child: ListTile(
                          title: Text(_categorias[index]['nome']),
                          subtitle: _subtituloDepartamento(_categorias[index], colorScheme),
                          leading: selecionada ? Icon(Icons.check_circle, color: colorScheme.primary) : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_categorias[index]['id'] != null)
                                IconButton(
                                  icon: Icon(Icons.edit_outlined, color: colorScheme.onSurfaceVariant),
                                  tooltip: 'Editar',
                                  onPressed: () => _editarCategoriaDialog(index),
                                ),
                              Icon(Icons.drag_handle, color: colorScheme.onSurfaceVariant),
                            ],
                          ),
                          onTap: () {
                            setState(() {
                              _categoriaController.text = _categorias[index]['nome'];
                            });
                          },
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.tonalIcon(
                onPressed: _novaCategoriaDialog,
                icon: const Icon(Icons.add),
                label: const Text('Nova categoria'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
