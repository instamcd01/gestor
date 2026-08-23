import 'package:flutter/material.dart';
import '../config/supabase_config.dart';

/// Gerencia `termos_variacao` — o dicionário usado pelo caminho heurístico
/// de detecção de variantes (produtos sem campos estruturados preenchidos)
/// pra reconhecer sabor/cor/outros valores por texto no nome. Ver seção 3.2
/// da spec (docs/superpowers/specs/2026-08-03-variantes-produto-design.md).
///
/// Cadastrar um termo novo aqui já basta pro detector passar a reconhecê-lo
/// em produtos futuros, sem precisar de nenhuma mudança de código.
class GerenciarTermosVariacaoScreen extends StatefulWidget {
  const GerenciarTermosVariacaoScreen({super.key});

  @override
  State<GerenciarTermosVariacaoScreen> createState() => _GerenciarTermosVariacaoScreenState();
}

class _GerenciarTermosVariacaoScreenState extends State<GerenciarTermosVariacaoScreen> {
  final _termoController = TextEditingController();
  final _categoriaController = TextEditingController();

  List<Map<String, dynamic>> _termos = []; // {id, tipo_variacao, termo, categoria}
  List<String> _tipos = []; // tipos_variacao.nome já cadastrados
  String? _tipoSelecionado;
  String? _empresaId;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _termoController.dispose();
    _categoriaController.dispose();
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

  Future<void> _carregar() async {
    try {
      final tipos = await supabase.from('tipos_variacao').select('nome').order('nome', ascending: true);
      final termos = await supabase
          .from('termos_variacao')
          .select('id, tipo_variacao, termo, categoria')
          .order('tipo_variacao', ascending: true)
          .order('termo', ascending: true);

      if (!mounted) return;
      setState(() {
        _tipos = (tipos as List).map((t) => t['nome'] as String).toList();
        _termos = List<Map<String, dynamic>>.from(termos);
        _tipoSelecionado ??= _tipos.isNotEmpty ? _tipos.first : null;
        _carregando = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar termos de variação: $e');
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _adicionar() async {
    final tipo = _tipoSelecionado;
    final termo = _termoController.text.trim();
    if (tipo == null || termo.isEmpty) return;

    final empresaId = await _obterEmpresaId();
    if (empresaId == null) return;

    try {
      await supabase.from('termos_variacao').insert({
        'empresa_id': empresaId,
        'tipo_variacao': tipo,
        'termo': termo,
        'categoria': _categoriaController.text.trim().isEmpty ? null : _categoriaController.text.trim(),
      });
      _termoController.clear();
      _categoriaController.clear();
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao adicionar termo: $e')));
    }
  }

  Future<void> _excluir(String id) async {
    await supabase.from('termos_variacao').delete().eq('id', id);
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Termos de variante')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Termos que o sistema reconhece pra sugerir agrupamento de '
                    'variantes por semelhança de nome (ex: "Frango" pro tipo '
                    '"sabor"). Só afeta produtos sem cadastro estruturado.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ),
                Expanded(
                  child: _termos.isEmpty
                      ? Center(
                          child: Text(
                            'Nenhum termo cadastrado ainda',
                            style: TextStyle(color: colorScheme.onSurfaceVariant),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _termos.length,
                          itemBuilder: (context, index) {
                            final termo = _termos[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                title: Text(termo['termo'] as String),
                                subtitle: Text(
                                  termo['categoria'] != null
                                      ? '${termo['tipo_variacao']} · só em ${termo['categoria']}'
                                      : '${termo['tipo_variacao']} · qualquer categoria',
                                ),
                                trailing: IconButton(
                                  icon: Icon(Icons.delete_outline, color: colorScheme.error),
                                  tooltip: 'Excluir',
                                  onPressed: () => _excluir(termo['id'] as String),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              initialValue: _tipoSelecionado,
                              decoration: const InputDecoration(labelText: 'Tipo'),
                              items: _tipos
                                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                                  .toList(),
                              onChanged: (v) => setState(() => _tipoSelecionado = v),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: _termoController,
                              decoration: const InputDecoration(labelText: 'Termo (ex: Frango)'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _categoriaController,
                        decoration: const InputDecoration(
                          labelText: 'Restringir a uma categoria (opcional)',
                        ),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(onPressed: _adicionar, child: const Text('Adicionar termo')),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
