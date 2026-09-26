import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../repositories/frete_economico_bairro_repository.dart';
import '../utils/cliente_validators.dart';
import '../utils/formatadores_input.dart';

/// Lista de valores da entrega econômica por bairro (dentro da seção
/// "Entrega econômica" do Catálogo Online). Cada alteração salva na hora —
/// não depende do "Salvar" da tela. Bairro fora da lista usa o valor
/// padrão configurado logo acima.
class FreteEconomicoBairrosSection extends StatefulWidget {
  const FreteEconomicoBairrosSection({super.key});

  @override
  State<FreteEconomicoBairrosSection> createState() => _FreteEconomicoBairrosSectionState();
}

class _FreteEconomicoBairrosSectionState extends State<FreteEconomicoBairrosSection> {
  final _repo = FreteEconomicoBairroRepository();
  List<FreteEconomicoBairro> _itens = [];
  List<String> _sugestoes = [];
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final itens = await _repo.listar();
      final sugestoes = await _repo.bairrosDosClientes();
      if (!mounted) return;
      setState(() {
        _itens = itens;
        _sugestoes = sugestoes;
        _carregando = false;
        _erro = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = 'Não foi possível carregar os bairros: $e';
      });
    }
  }

  Future<void> _editar([FreteEconomicoBairro? existente]) async {
    final resultado = await showDialog<FreteEconomicoBairro>(
      context: context,
      builder: (_) => _DialogBairro(existente: existente, sugestoes: _sugestoes),
    );
    if (resultado == null || !mounted) return;
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;
    try {
      await _repo.salvar(resultado, empresaId: empresaId);
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      final duplicado = e.toString().contains('23505') || e.toString().contains('duplicate');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(duplicado ? 'Esse bairro já está na lista — edite o que já existe.' : 'Erro ao salvar: $e'),
      ));
    }
  }

  Future<void> _excluir(FreteEconomicoBairro item) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover bairro?'),
        content: Text('${item.bairro} volta a usar o valor padrão da entrega econômica.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remover')),
        ],
      ),
    );
    if (confirmou != true || item.id == null) return;
    try {
      await _repo.excluir(item.id!);
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao remover: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text('Valor por bairro', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'Bairro que não estiver aqui usa o valor padrão acima. Alterações nesta lista '
          'são salvas na hora e valem pro site e pro WhatsApp.',
          style: TextStyle(fontSize: 12, color: cores.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        if (_carregando)
          const Center(child: Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator()))
        else if (_erro != null)
          Text(_erro!, style: TextStyle(color: cores.error))
        else
          for (final item in _itens)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item.bairro),
              subtitle: Text(
                item.atende ? 'R\$ ${ClienteValidators.formatarMoeda(item.valor)}' : 'Não oferece entrega econômica',
                style: TextStyle(color: item.atende ? null : cores.error),
              ),
              onTap: () => _editar(item),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remover',
                onPressed: () => _excluir(item),
              ),
            ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _carregando ? null : () => _editar(),
            icon: const Icon(Icons.add),
            label: const Text('Adicionar bairro'),
          ),
        ),
      ],
    );
  }
}

class _DialogBairro extends StatefulWidget {
  final FreteEconomicoBairro? existente;
  final List<String> sugestoes;

  const _DialogBairro({this.existente, required this.sugestoes});

  @override
  State<_DialogBairro> createState() => _DialogBairroState();
}

class _DialogBairroState extends State<_DialogBairro> {
  late String _bairro = widget.existente?.bairro ?? '';
  late final _valorController = TextEditingController(
    text: widget.existente?.valor != null ? ClienteValidators.formatarMoeda(widget.existente!.valor) : '',
  );
  late bool _atende = widget.existente?.atende ?? true;
  String? _erro;

  @override
  void dispose() {
    _valorController.dispose();
    super.dispose();
  }

  void _confirmar() {
    final bairro = _bairro.trim();
    final valor = ClienteValidators.parseNumero(_valorController.text);
    if (bairro.isEmpty) {
      setState(() => _erro = 'Informe o bairro.');
      return;
    }
    if (_atende && (valor == null || valor < 0)) {
      setState(() => _erro = 'Informe o valor da entrega econômica pra esse bairro.');
      return;
    }
    Navigator.pop(
      context,
      FreteEconomicoBairro(id: widget.existente?.id, bairro: bairro, valor: _atende ? valor : null, atende: _atende),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existente == null ? 'Adicionar bairro' : 'Editar bairro'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Autocomplete<String>(
              initialValue: TextEditingValue(text: _bairro),
              optionsBuilder: (valor) {
                final termo = valor.text.trim().toLowerCase();
                if (termo.isEmpty) return widget.sugestoes.take(8);
                return widget.sugestoes.where((b) => b.toLowerCase().contains(termo)).take(8);
              },
              onSelected: (b) => _bairro = b,
              fieldViewBuilder: (context, controller, focusNode, _) => TextField(
                controller: controller,
                focusNode: focusNode,
                autofocus: widget.existente == null,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Bairro', hintText: 'Ex: Santa Cruz'),
                onChanged: (v) => _bairro = v,
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Oferecer entrega econômica'),
              value: _atende,
              onChanged: (v) => setState(() => _atende = v),
            ),
            if (_atende)
              TextField(
                controller: _valorController,
                decoration: const InputDecoration(labelText: 'Valor (R\$)', prefixText: 'R\$ '),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [MoedaInputFormatter()],
              ),
            if (_erro != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_erro!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _confirmar, child: const Text('Salvar')),
      ],
    );
  }
}
