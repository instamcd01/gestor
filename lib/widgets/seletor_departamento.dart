import 'package:flutter/material.dart';

import '../config/supabase_config.dart';

/// Departamento é o 1º nível do menu do site (Alimentação, Saúde...). Toda
/// categoria precisa de um — sem ele, os produtos caem num "Outros" no site.
/// Este seletor carrega os departamentos sozinho e tem o "+" pra criar um
/// novo ali mesmo, igual ao de subcategoria no cadastro de produto.
class SeletorDepartamento extends StatefulWidget {
  final String? valorInicial;
  final ValueChanged<String?> onChanged;

  const SeletorDepartamento({super.key, this.valorInicial, required this.onChanged});

  @override
  State<SeletorDepartamento> createState() => _SeletorDepartamentoState();
}

class _SeletorDepartamentoState extends State<SeletorDepartamento> {
  List<Map<String, dynamic>> _departamentos = [];
  bool _carregado = false;
  String? _selecionado;

  @override
  void initState() {
    super.initState();
    _selecionado = widget.valorInicial;
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final data = await supabase.from('departamentos').select('id, nome').order('ordem', ascending: true);
      if (!mounted) return;
      setState(() {
        _departamentos = List<Map<String, dynamic>>.from(data);
        _carregado = true;
      });
    } catch (e) {
      debugPrint('Erro ao carregar departamentos: $e');
      if (mounted) setState(() => _carregado = true);
    }
  }

  Future<void> _novo() async {
    final id = await mostrarNovoDepartamentoDialog(context);
    if (id == null) return;
    await _carregar();
    if (!mounted) return;
    setState(() => _selecionado = id);
    widget.onChanged(id);
  }

  @override
  Widget build(BuildContext context) {
    if (!_carregado) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final valor = _departamentos.any((d) => d['id'] == _selecionado) ? _selecionado : null;
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            key: ValueKey(valor),
            initialValue: valor,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Departamento',
              helperText: 'Onde ela aparece no menu do site',
            ),
            items: [
              for (final d in _departamentos)
                DropdownMenuItem(value: d['id'] as String, child: Text(d['nome'] as String)),
            ],
            onChanged: (v) {
              setState(() => _selecionado = v);
              widget.onChanged(v);
            },
            validator: (v) => v == null ? 'Escolha o departamento' : null,
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          tooltip: 'Novo departamento',
          icon: const Icon(Icons.add),
          onPressed: _novo,
        ),
      ],
    );
  }
}

/// Caixinha "Novo departamento". Devolve o id do departamento criado (ou do
/// já existente com o mesmo nome, sem diferenciar maiúsculas), ou null se
/// cancelar.
Future<String?> mostrarNovoDepartamentoDialog(BuildContext context) {
  return showDialog<String>(context: context, builder: (_) => const _NovoDepartamentoDialog());
}

class _NovoDepartamentoDialog extends StatefulWidget {
  const _NovoDepartamentoDialog();

  @override
  State<_NovoDepartamentoDialog> createState() => _NovoDepartamentoDialogState();
}

class _NovoDepartamentoDialogState extends State<_NovoDepartamentoDialog> {
  final _controller = TextEditingController();
  bool _salvando = false;
  String? _erro;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final nome = _controller.text.trim();
    if (nome.isEmpty) {
      setState(() => _erro = 'Digite o nome');
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      final id = await criarOuObterDepartamento(nome);
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      debugPrint('Erro ao criar departamento: $e');
      if (mounted) {
        setState(() {
          _salvando = false;
          _erro = 'Não foi possível salvar. Tente de novo.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Novo departamento'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        enabled: !_salvando,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(labelText: 'Nome', errorText: _erro),
        onSubmitted: (_) => _salvar(),
      ),
      actions: [
        TextButton(
          onPressed: _salvando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _salvando ? null : _salvar,
          child: _salvando
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Salvar'),
        ),
      ],
    );
  }
}

/// Cria o departamento (no fim da ordem) e devolve o id. Se já existir um com
/// o mesmo nome, sem diferenciar maiúsculas, devolve o id dele — a tabela não
/// tem índice único por nome, então a checagem é feita aqui.
Future<String> criarOuObterDepartamento(String nome) async {
  final nomeLimpo = nome.trim();
  final existentes =
      List<Map<String, dynamic>>.from(await supabase.from('departamentos').select('id, nome, ordem'));
  for (final d in existentes) {
    if ((d['nome'] as String).toLowerCase() == nomeLimpo.toLowerCase()) return d['id'] as String;
  }

  final userId = supabase.auth.currentUser?.id;
  if (userId == null) throw StateError('Sem usuário logado');
  final usuario = await supabase.from('usuarios').select('empresa_id').eq('id', userId).single();
  final proximaOrdem = existentes.isEmpty
      ? 0
      : existentes.map((d) => d['ordem'] as int).reduce((a, b) => a > b ? a : b) + 1;

  final novo = await supabase
      .from('departamentos')
      .insert({'nome': nomeLimpo, 'ordem': proximaOrdem, 'empresa_id': usuario['empresa_id']})
      .select('id')
      .single();
  return novo['id'] as String;
}
