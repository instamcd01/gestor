import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../config/supabase_config.dart';
import '../providers/auth_provider.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _data = DateFormat('dd/MM HH:mm');

/// Aba "Indicações" de `CuponsHubScreen`: regras do "indique um amigo",
/// ranking de quem mais indica e cada uso do código com os sinais de fraude
/// calculados no banco (`relatorio_indicacoes`). Pedido ainda não entregue
/// aparece também — bloquear o código antes da entrega impede o PetCash
/// (trigger `gerar_petcash_indicacao` registra como "bloqueado").
class IndicacoesScreen extends StatefulWidget {
  const IndicacoesScreen({super.key});

  @override
  State<IndicacoesScreen> createState() => _IndicacoesScreenState();
}

class _IndicacoesScreenState extends State<IndicacoesScreen> {
  bool _carregando = true;
  String? _erro;
  int _dias = 90;
  List<Map<String, dynamic>> _indicadores = [];

  bool _ativo = false;
  double _valorAmigo = 10;
  double _valorIndicador = 10;
  double _pedidoMinimo = 89;
  int? _limiteMes;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _carregar());
  }

  Future<void> _carregar() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final cfg = await supabase
          .from('empresas')
          .select('indicacao_ativo, indicacao_valor_amigo, indicacao_valor_indicador, indicacao_pedido_minimo, indicacao_limite_mes')
          .eq('id', empresaId)
          .single();
      final rel = await supabase.rpc('relatorio_indicacoes', params: {'p_empresa_id': empresaId, 'p_dias': _dias});
      if (!mounted) return;
      setState(() {
        _ativo = cfg['indicacao_ativo'] == true;
        _valorAmigo = (cfg['indicacao_valor_amigo'] as num?)?.toDouble() ?? 10;
        _valorIndicador = (cfg['indicacao_valor_indicador'] as num?)?.toDouble() ?? 10;
        _pedidoMinimo = (cfg['indicacao_pedido_minimo'] as num?)?.toDouble() ?? 89;
        _limiteMes = (cfg['indicacao_limite_mes'] as num?)?.toInt();
        _indicadores = ((rel as List?) ?? []).cast<Map<String, dynamic>>();
      });
    } catch (e) {
      if (mounted) setState(() => _erro = 'Não foi possível carregar as indicações: $e');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _alternarCodigo(Map<String, dynamic> ind) async {
    final ativo = ind['codigo_ativo'] == true;
    if (ativo) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Bloquear o código ${ind['codigo']}?'),
          content: const Text(
            'Ninguém mais consegue usar esse código, e os pedidos com ele que ainda não foram entregues '
            'não vão gerar PetCash pra quem indicou. O PetCash que já caiu continua com o cliente.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Bloquear')),
          ],
        ),
      );
      if (ok != true) return;
    }
    try {
      await supabase.from('cupons').update({'ativo': !ativo}).eq('id', ind['cupom_id'] as String);
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível alterar o código: $e')));
    }
  }

  Future<void> _editarRegras() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;
    final amigo = TextEditingController(text: _valorAmigo.toStringAsFixed(0));
    final indicador = TextEditingController(text: _valorIndicador.toStringAsFixed(0));
    final minimo = TextEditingController(text: _pedidoMinimo.toStringAsFixed(0));
    final limite = TextEditingController(text: _limiteMes?.toString() ?? '');
    var ativo = _ativo;
    final digitos = [FilteringTextInputFormatter.digitsOnly];

    final salvar = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Regras da indicação'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Programa ligado'),
                  value: ativo,
                  onChanged: (v) => setD(() => ativo = v),
                ),
                TextField(controller: amigo, keyboardType: TextInputType.number, inputFormatters: digitos,
                    decoration: const InputDecoration(labelText: 'Desconto do amigo (R\$)')),
                TextField(controller: indicador, keyboardType: TextInputType.number, inputFormatters: digitos,
                    decoration: const InputDecoration(labelText: 'PetCash de quem indicou (R\$)')),
                TextField(controller: minimo, keyboardType: TextInputType.number, inputFormatters: digitos,
                    decoration: const InputDecoration(labelText: 'Pedido mínimo do amigo (R\$)')),
                TextField(controller: limite, keyboardType: TextInputType.number, inputFormatters: digitos,
                    decoration: const InputDecoration(
                        labelText: 'Máximo de amigos premiados por mês',
                        helperText: 'Vazio = sem limite. O site mostra "ganhe até R\$ X por mês".')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (salvar != true) return;
    try {
      await supabase.from('empresas').update({
        'indicacao_ativo': ativo,
        'indicacao_valor_amigo': double.tryParse(amigo.text) ?? _valorAmigo,
        'indicacao_valor_indicador': double.tryParse(indicador.text) ?? _valorIndicador,
        'indicacao_pedido_minimo': double.tryParse(minimo.text) ?? _pedidoMinimo,
        'indicacao_limite_mes': int.tryParse(limite.text),
      }).eq('id', empresaId);
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível salvar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_carregando && _indicadores.isEmpty) return const Center(child: CircularProgressIndicator());
    if (_erro != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_erro!, textAlign: TextAlign.center)));
    }

    final premiados = _indicadores.fold<int>(0, (s, i) => s + ((i['premiados'] as num?)?.toInt() ?? 0));
    final petcash = _indicadores.fold<double>(0, (s, i) => s + ((i['petcash_total'] as num?)?.toDouble() ?? 0));
    final alertas = _indicadores.where((i) => ((i['com_alerta'] as num?) ?? 0) > 0 || i['ritmo_alto'] == true).length;
    final tetoMes = _limiteMes == null ? null : _limiteMes! * _valorIndicador;

    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: ListTile(
              leading: Icon(_ativo ? Icons.card_giftcard : Icons.pause_circle_outline, color: _ativo ? cs.primary : cs.outline),
              title: Text(_ativo ? 'Indique um amigo ligado' : 'Indique um amigo desligado'),
              subtitle: Text(
                'Amigo ganha ${_moeda.format(_valorAmigo)} (pedido a partir de ${_moeda.format(_pedidoMinimo)}) • '
                'quem indica ganha ${_moeda.format(_valorIndicador)} de PetCash • '
                '${tetoMes == null ? 'sem limite por mês' : 'até ${_moeda.format(tetoMes)} por mês ($_limiteMes amigos)'}',
              ),
              trailing: IconButton(icon: const Icon(Icons.edit_outlined), tooltip: 'Editar regras', onPressed: _editarRegras),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final d in const [30, 90, 365])
                ChoiceChip(
                  label: Text(d == 365 ? '12 meses' : '$d dias'),
                  selected: _dias == d,
                  onSelected: (_) {
                    setState(() => _dias = d);
                    _carregar();
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _Resumo(rotulo: 'Quem indica', valor: '${_indicadores.length}'),
              _Resumo(rotulo: 'Amigos premiados', valor: '$premiados'),
              _Resumo(rotulo: 'PetCash pago', valor: _moeda.format(petcash)),
              _Resumo(rotulo: 'Com alerta', valor: '$alertas', destaque: alertas > 0),
            ],
          ),
          const SizedBox(height: 12),
          if (_indicadores.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text('Ninguém usou um código de indicação nesse período ainda.',
                  textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
            )
          else
            for (final ind in _indicadores) _CardIndicador(ind: ind, onAlternarCodigo: () => _alternarCodigo(ind)),
        ],
      ),
    );
  }
}

class _Resumo extends StatelessWidget {
  final String rotulo;
  final String valor;
  final bool destaque;
  const _Resumo({required this.rotulo, required this.valor, this.destaque = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Expanded(
      child: Card(
        color: destaque ? cs.errorContainer : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(
            children: [
              Text(valor, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              Text(rotulo, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardIndicador extends StatelessWidget {
  final Map<String, dynamic> ind;
  final VoidCallback onAlternarCodigo;
  const _CardIndicador({required this.ind, required this.onAlternarCodigo});

  static const _statusPedido = {
    'entregue': 'Entregue',
    'cancelado': 'Cancelado',
    'aguardando_pagamento': 'Aguardando pagamento',
  };
  static const _statusIndicacao = {
    'creditado': 'PetCash pago',
    'limite_mes': 'Passou do limite do mês',
    'mesma_pessoa': 'Mesma pessoa — não pago',
    'programa_desligado': 'Programa desligado',
    'bloqueado': 'Código bloqueado — não pago',
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final amigos = ((ind['amigos'] as List?) ?? []).cast<Map<String, dynamic>>();
    final comAlerta = ((ind['com_alerta'] as num?) ?? 0) > 0;
    final ritmo = ind['ritmo_alto'] == true;
    final ativo = ind['codigo_ativo'] == true;

    return Card(
      child: ExpansionTile(
        leading: Icon(
          comAlerta || ritmo ? Icons.warning_amber_rounded : Icons.person_outline,
          color: comAlerta || ritmo ? cs.error : cs.primary,
        ),
        title: Text('${ind['nome'] ?? 'Cliente'} • ${ind['codigo']}${ativo ? '' : ' (bloqueado)'}'),
        subtitle: Text(
          '${ind['premiados']} premiado(s) • ${_moeda.format((ind['petcash_total'] as num?) ?? 0)} de PetCash'
          '${((ind['a_caminho'] as num?) ?? 0) > 0 ? ' • ${ind['a_caminho']} a caminho' : ''}'
          '${ritmo ? ' • 3+ usos em 7 dias' : ''}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          for (final a in amigos)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text('#${a['numero']} • ${a['amigo'] ?? 'Cliente'} • ${_moeda.format((a['valor'] as num?) ?? 0)}'),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_data.format(DateTime.parse(a['data'] as String).toLocal())} • '
                    '${_statusIndicacao[a['indicacao_status']] ?? _statusPedido[a['status']] ?? 'A caminho — PetCash ainda não caiu'}',
                  ),
                  if (((a['alertas'] as List?) ?? []).isNotEmpty)
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final al in (a['alertas'] as List))
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: Text(al as String, style: TextStyle(fontSize: 11, color: cs.onErrorContainer)),
                            backgroundColor: cs.errorContainer,
                            side: BorderSide.none,
                          ),
                      ],
                    ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onAlternarCodigo,
              icon: Icon(ativo ? Icons.block : Icons.check_circle_outline),
              label: Text(ativo ? 'Bloquear código' : 'Desbloquear código'),
            ),
          ),
        ],
      ),
    );
  }
}
