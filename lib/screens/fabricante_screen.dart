import 'package:flutter/material.dart';
import '../config/supabase_config.dart';

/// Seletor + gerenciador de fabricantes — mesmo papel duplo que
/// [CategoriaScreen] (produto_categorias_screen.dart) já cumpre pra
/// categoria: usada tanto embutida no cadastro/edição de produto (retorna o
/// nome escolhido via Navigator.pop) quanto como tela de gerenciamento
/// standalone (a partir de Configurações do Produto).
///
/// Separado de `produtos.marca` de propósito — marca historicamente guarda o
/// FORNECEDOR/distribuidora nesse banco, não o fabricante real.
class FabricanteScreen extends StatefulWidget {
  final String? fabricanteSelecionado;

  const FabricanteScreen({this.fabricanteSelecionado, super.key});

  @override
  State<FabricanteScreen> createState() => _FabricanteScreenState();
}

class _FabricanteScreenState extends State<FabricanteScreen> {
  final TextEditingController _fabricanteController = TextEditingController();
  final TextEditingController _novoFabricanteController = TextEditingController();

  List<Map<String, dynamic>> _fabricantes = []; // {id, nome, ordem}
  String? _empresaId;

  @override
  void initState() {
    super.initState();
    if (widget.fabricanteSelecionado != null) {
      _fabricanteController.text = widget.fabricanteSelecionado!;
    }
    _carregarFabricantes();
  }

  Future<String?> _obterEmpresaId() async {
    if (_empresaId != null) return _empresaId;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return null;
    final usuario = await supabase.from('usuarios').select('empresa_id').eq('id', userId).maybeSingle();
    _empresaId = usuario?['empresa_id'] as String?;
    return _empresaId;
  }

  Future<void> _carregarFabricantes() async {
    try {
      final empresaId = await _obterEmpresaId();
      if (empresaId == null) return;

      final salvos =
          await supabase.from('fabricantes').select('id, nome, ordem').order('ordem', ascending: true);
      final fabricantes = List<Map<String, dynamic>>.from(salvos);

      // Mesmo backfill lazy que CategoriaScreen faz pra categoria: cobre
      // fabricantes já digitados em produtos que ainda não viraram linha
      // formal em `fabricantes`.
      final produtos = await supabase.from('produtos').select('fabricante');
      final fabricantesDeProdutos = (produtos as List)
          .map((p) => (p['fabricante'] as String?) ?? '')
          .where((f) => f.isNotEmpty)
          .toSet();

      for (final fab in fabricantesDeProdutos) {
        if (!fabricantes.any((f) => (f['nome'] as String).toLowerCase() == fab.toLowerCase())) {
          final nova = await supabase
              .from('fabricantes')
              .insert({'nome': fab, 'ordem': fabricantes.length, 'empresa_id': empresaId})
              .select()
              .single();
          fabricantes.add(nova);
        }
      }

      if (!mounted) return;
      setState(() => _fabricantes = fabricantes);
    } catch (e) {
      debugPrint('Erro ao carregar fabricantes: $e');
    }
  }

  Future<void> _adicionarFabricante(String nome) async {
    if (nome.isEmpty) return;
    if (_fabricantes.any((f) => (f['nome'] as String).toLowerCase() == nome.toLowerCase())) return;

    final empresaId = await _obterEmpresaId();
    if (empresaId == null) return;

    final proximaOrdem = _fabricantes.isNotEmpty
        ? _fabricantes.map((f) => f['ordem'] as int).reduce((a, b) => a > b ? a : b) + 1
        : 0;

    await supabase.from('fabricantes').insert({'nome': nome, 'ordem': proximaOrdem, 'empresa_id': empresaId});
    await _carregarFabricantes();
  }

  Future<void> _excluirFabricante(String? id) async {
    if (id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir fabricante'),
        content: const Text('Deseja realmente excluir? Os produtos que o utilizam ficarão sem fabricante.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    final antigoFabricante = _fabricantes.firstWhere((f) => f['id'] == id)['nome'] as String;
    await supabase.from('produtos').update({'fabricante': null}).eq('fabricante', antigoFabricante);
    await supabase.from('fabricantes').delete().eq('id', id);
    await _carregarFabricantes();
  }

  Future<void> _reordenarFabricantes(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final movido = _fabricantes.removeAt(oldIndex);
    _fabricantes.insert(newIndex, movido);

    for (var i = 0; i < _fabricantes.length; i++) {
      if (_fabricantes[i]['id'] != null) {
        await supabase.from('fabricantes').update({'ordem': i}).eq('id', _fabricantes[i]['id']);
      }
    }
    setState(() {});
  }

  void _editarFabricanteDialog(int index) {
    final controllerEdicao = TextEditingController(text: _fabricantes[index]['nome']);
    String? novoSelecionado;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Editar fabricante'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(controller: controllerEdicao, decoration: const InputDecoration(labelText: 'Novo nome')),
                  const SizedBox(height: 16),
                  DropdownButton<String>(
                    value: novoSelecionado,
                    hint: const Text('Selecionar outro fabricante para mesclar'),
                    isExpanded: true,
                    items: _fabricantes
                        .where((f) => f['id'] != _fabricantes[index]['id'])
                        .map<DropdownMenuItem<String>>(
                          (f) => DropdownMenuItem<String>(value: f['nome'] as String, child: Text(f['nome'] as String)),
                        )
                        .toList(),
                    onChanged: (val) => setStateDialog(() => novoSelecionado = val),
                  ),
                ],
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
                TextButton(
                  onPressed: () async {
                    final confirmar = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Confirmação'),
                        content: const Text('Excluir este fabricante? Produtos relacionados ficarão sem fabricante.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
                          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
                        ],
                      ),
                    );
                    if (confirmar == true) {
                      await _excluirFabricante(_fabricantes[index]['id']);
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                  child: const Text('Excluir', style: TextStyle(color: Colors.red)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final antigoNome = _fabricantes[index]['nome'] as String;
                    if (novoSelecionado != null) {
                      // Mescla produtos pro fabricante existente e exclui o antigo.
                      await supabase
                          .from('produtos')
                          .update({'fabricante': novoSelecionado}).eq('fabricante', antigoNome);
                      await supabase.from('fabricantes').delete().eq('id', _fabricantes[index]['id']);
                    } else if (controllerEdicao.text.isNotEmpty && controllerEdicao.text != antigoNome) {
                      await supabase
                          .from('fabricantes')
                          .update({'nome': controllerEdicao.text}).eq('id', _fabricantes[index]['id']);
                      await supabase
                          .from('produtos')
                          .update({'fabricante': controllerEdicao.text}).eq('fabricante', antigoNome);
                    }
                    if (context.mounted) Navigator.pop(context);
                    await _carregarFabricantes();
                  },
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _salvarEVoltar() {
    Navigator.pop(context, _fabricanteController.text);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fabricantes'),
        actions: [
          if (widget.fabricanteSelecionado != null)
            TextButton(onPressed: _salvarEVoltar, child: const Text('Salvar')),
        ],
      ),
      body: Column(
        children: [
          if (widget.fabricanteSelecionado != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _fabricanteController,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Fabricante selecionado',
                  suffixIcon: Icon(Icons.arrow_drop_down),
                ),
              ),
            ),
          Expanded(
            child: ReorderableListView(
              onReorder: _reordenarFabricantes,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (var index = 0; index < _fabricantes.length; index++)
                  Builder(
                    key: ValueKey(_fabricantes[index]['id'] ?? _fabricantes[index]['nome']),
                    builder: (context) {
                      final colorScheme = Theme.of(context).colorScheme;
                      final selecionado = _fabricanteController.text == _fabricantes[index]['nome'];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: selecionado ? colorScheme.primary.withValues(alpha: 0.1) : null,
                        child: ListTile(
                          title: Text(_fabricantes[index]['nome']),
                          leading: selecionado ? Icon(Icons.check_circle, color: colorScheme.primary) : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.edit_outlined, color: colorScheme.onSurfaceVariant),
                                tooltip: 'Editar',
                                onPressed: () => _editarFabricanteDialog(index),
                              ),
                              Icon(Icons.drag_handle, color: colorScheme.onSurfaceVariant),
                            ],
                          ),
                          onTap: widget.fabricanteSelecionado == null
                              ? null
                              : () => setState(() => _fabricanteController.text = _fabricantes[index]['nome']),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _novoFabricanteController,
                    decoration: const InputDecoration(labelText: 'Novo fabricante'),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () async {
                    if (_novoFabricanteController.text.isNotEmpty) {
                      await _adicionarFabricante(_novoFabricanteController.text);
                      _novoFabricanteController.clear();
                    }
                  },
                  child: const Text('Adicionar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
