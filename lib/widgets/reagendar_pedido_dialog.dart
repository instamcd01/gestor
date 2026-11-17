import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/venda.dart';
import '../providers/auth_provider.dart';
import '../providers/historico_vendas_provider.dart';
import '../utils/agendamento_utils.dart';

/// Agendar (ou mudar o horário de) um pedido já criado — ex: cliente fechou
/// o pedido e depois pediu pra receber das 18h às 19h. Mesmas janelas de 1h
/// do agendamento na hora da venda e do checkout do site
/// (`agendamento_utils.dart`). Retorna true se salvou.
Future<bool> reagendarPedido(BuildContext context, Venda venda) async {
  final salvou = await showDialog<bool>(
    context: context,
    builder: (_) => _ReagendarPedidoDialog(venda: venda),
  );
  return salvou == true;
}

class _ReagendarPedidoDialog extends StatefulWidget {
  final Venda venda;
  const _ReagendarPedidoDialog({required this.venda});

  @override
  State<_ReagendarPedidoDialog> createState() => _ReagendarPedidoDialogState();
}

class _ReagendarPedidoDialogState extends State<_ReagendarPedidoDialog> {
  Map<String, dynamic>? _horario;
  bool _carregando = true;
  bool _salvando = false;
  String? _erro;
  OpcaoDataAgendamento? _data;
  JanelaHorarioAgendamento? _janela;

  @override
  void initState() {
    super.initState();
    _carregarHorario();
  }

  Future<void> _carregarHorario() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    try {
      if (empresaId != null) {
        final data = await Supabase.instance.client
            .from('empresas')
            .select('horario_funcionamento')
            .eq('id', empresaId)
            .single();
        _horario = data['horario_funcionamento'] as Map<String, dynamic>?;
      }
    } catch (e) {
      debugPrint('Horário de funcionamento não carregado: $e');
    }
    if (!mounted) return;
    final opcoes = gerarOpcoesData(_horario);
    setState(() {
      _data = opcoes.isNotEmpty ? opcoes.first : null;
      _carregando = false;
    });
  }

  Future<void> _salvar() async {
    final janela = _janela;
    if (janela == null || widget.venda.idVenda == null) return;
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await context.read<HistoricoVendasProvider>().reagendarPedido(widget.venda.idVenda!, janela.inicio, janela.fim);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _salvando = false;
        _erro = e is PostgrestException ? e.message : 'Não foi possível salvar. Tente de novo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final opcoesData = gerarOpcoesData(_horario);
    final janelas = _data != null ? gerarJanelasHorario(_data!.data, _data!.diaSemana, _horario) : <JanelaHorarioAgendamento>[];
    final ehRetirada = !widget.venda.temEntrega;
    final numero = widget.venda.numeroSequencial != null ? ' #${widget.venda.numeroSequencial}' : '';

    return AlertDialog(
      title: Text('Agendar ${ehRetirada ? 'retirada' : 'entrega'}$numero'),
      content: SizedBox(
        width: 420,
        child: _carregando
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Dia', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final opcao in opcoesData)
                          ChoiceChip(
                            label: Text(opcao.label),
                            selected: _data?.data == opcao.data,
                            onSelected: (_) => setState(() {
                              _data = opcao;
                              _janela = null;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text('Horário', style: TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    if (janelas.isEmpty)
                      Text('Sem horário disponível nesse dia.', style: TextStyle(color: cores.onSurfaceVariant))
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final janela in janelas)
                            ChoiceChip(
                              label: Text(janela.label),
                              selected: _janela?.inicio == janela.inicio,
                              onSelected: (_) => setState(() => _janela = janela),
                            ),
                        ],
                      ),
                    if (_erro != null) ...[
                      const SizedBox(height: 12),
                      Text(_erro!, style: TextStyle(color: cores.error)),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(onPressed: _salvando ? null : () => Navigator.pop(context, false), child: const Text('Cancelar')),
        FilledButton(
          onPressed: _janela == null || _salvando ? null : _salvar,
          child: Text(_salvando ? 'Salvando…' : 'Agendar'),
        ),
      ],
    );
  }
}
