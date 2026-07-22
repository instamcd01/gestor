import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/supabase_config.dart';
import '../providers/auth_provider.dart';
import '../widgets/form_section.dart';

const metodosPagamentoDisponiveis = [
  'Dinheiro',
  'Cartão de Débito',
  'Cartão de Crédito',
  'Pix',
  'Link de Pagamento',
  'Outros',
];

/// Configurações > Opções de Pagamento: quais métodos aparecem na tela de
/// pagamento do balcão, e a chave Pix mostrada ao caixa (pagamento continua
/// sendo feito numa maquininha/Pix físico à parte — o app só registra).
class OpcoesPagamentoScreen extends StatefulWidget {
  const OpcoesPagamentoScreen({super.key});

  @override
  State<OpcoesPagamentoScreen> createState() => _OpcoesPagamentoScreenState();
}

class _OpcoesPagamentoScreenState extends State<OpcoesPagamentoScreen> {
  final _chavePixController = TextEditingController();
  final Set<String> _metodosAtivos = {...metodosPagamentoDisponiveis};
  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  @override
  void dispose() {
    _chavePixController.dispose();
    super.dispose();
  }

  Future<void> _carregarDados() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) {
      setState(() => _carregando = false);
      return;
    }

    try {
      final data = await supabase
          .from('empresas')
          .select('metodos_pagamento_ativos, chave_pix')
          .eq('id', empresaId)
          .single();

      final metodos = data['metodos_pagamento_ativos'] as List?;
      if (metodos != null) {
        _metodosAtivos
          ..clear()
          ..addAll(metodos.map((m) => m.toString()));
      }
      _chavePixController.text = data['chave_pix']?.toString() ?? '';
    } catch (e) {
      debugPrint('Erro ao carregar opções de pagamento: $e');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvar() async {
    if (_metodosAtivos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pelo menos uma forma de pagamento precisa ficar ativa.')),
      );
      return;
    }

    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;

    setState(() => _salvando = true);
    try {
      await supabase.from('empresas').update({
        'metodos_pagamento_ativos': _metodosAtivos.toList(),
        'chave_pix': _chavePixController.text.trim(),
      }).eq('id', empresaId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Opções de pagamento salvas com sucesso!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Opções de Pagamento'),
        actions: [
          _salvando
              ? Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary, strokeWidth: 2),
                  ),
                )
              : IconButton(icon: const Icon(Icons.save), onPressed: _carregando ? null : _salvar),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                FormSection(
                  titulo: 'Formas de pagamento aceitas no balcão',
                  children: [
                    Text(
                      'Desmarque as que sua loja não usa — elas somem da tela de pagamento.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                    ),
                    Column(
                      children: metodosPagamentoDisponiveis
                          .map((metodo) => CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(metodo),
                                value: _metodosAtivos.contains(metodo),
                                onChanged: (v) => setState(() {
                                  if (v == true) {
                                    _metodosAtivos.add(metodo);
                                  } else {
                                    _metodosAtivos.remove(metodo);
                                  }
                                }),
                              ))
                          .toList(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FormSection(
                  titulo: 'Pix',
                  children: [
                    TextField(
                      controller: _chavePixController,
                      decoration: const InputDecoration(
                        labelText: 'Chave Pix (Opcional)',
                        helperText: 'Mostrada ao caixa na tela de pagamento via Pix',
                      ),
                      inputFormatters: [FilteringTextInputFormatter.singleLineFormatter],
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _salvando ? null : _salvar,
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                  child: const Text('Salvar'),
                ),
              ],
            ),
    );
  }
}
