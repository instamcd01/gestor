import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../providers/auth_provider.dart';

/// Domingo e feriado: o que muda sozinho no site/WhatsApp (prazo, taxa,
/// mínimo do frete grátis — aplica 00:05 e volta à meia-noite), o que está
/// valendo hoje e como fica o iFood (pré-configurações DOMINGO/FERIADO no
/// Portal + verificação automática do domingo).
class ModoDomingoFeriadoScreen extends StatefulWidget {
  const ModoDomingoFeriadoScreen({super.key});

  @override
  State<ModoDomingoFeriadoScreen> createState() => _ModoDomingoFeriadoScreenState();
}

class _ModoDomingoFeriadoScreenState extends State<ModoDomingoFeriadoScreen> {
  Map<String, dynamic>? _dados;
  final Map<String, Map<String, dynamic>> _perfis = {};
  bool _carregando = true;
  bool _salvando = false;
  bool _alterado = false;
  String? _erro;

  static const _padrao = {'ativo': true, 'prazo': 30, 'frete_gratis': 20, 'taxa_ate3km': 1, 'taxa_acima3km': 2};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final r = Map<String, dynamic>.from(await supabase.rpc('modo_domingo_feriado_resumo') as Map);
      final perfis = r['perfis'] == null ? <String, dynamic>{} : Map<String, dynamic>.from(r['perfis'] as Map);
      _perfis
        ..['domingo'] = Map<String, dynamic>.from((perfis['domingo'] as Map?) ?? _padrao)
        ..['feriado'] = Map<String, dynamic>.from((perfis['feriado'] as Map?) ?? _padrao);
      if (mounted) setState(() => _dados = r);
    } catch (e) {
      if (mounted) setState(() => _erro = 'Não deu pra carregar. Puxe pra tentar de novo.');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    try {
      await supabase.rpc('salvar_modo_domingo_feriado', params: {'p_perfis': _perfis});
      if (!mounted) return;
      setState(() => _alterado = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Salvo. Vale a partir do próximo domingo ou feriado.')),
      );
    } on PostgrestException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  num _n(Map<String, dynamic> p, String k) => (p[k] as num?) ?? 0;

  String _r(num v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  Widget _passo(String rotulo, String perfil, String chave, num passo, String Function(num) fmt, {num max = 200}) {
    final p = _perfis[perfil]!;
    final v = _n(p, chave);
    final podeEditar = context.read<AuthProvider>().podeVerFinancas;
    return Row(
      children: [
        Expanded(child: Text(rotulo, style: const TextStyle(fontSize: 14))),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: !podeEditar || v - passo < 0 ? null : () => setState(() {
                p[chave] = v - passo;
                _alterado = true;
              }),
        ),
        SizedBox(width: 72, child: Text(fmt(v), textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600))),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: !podeEditar || v + passo > max ? null : () => setState(() {
                p[chave] = v + passo;
                _alterado = true;
              }),
        ),
      ],
    );
  }

  Widget _cartaoPerfil(String perfil, String titulo, String quando) {
    final p = _perfis[perfil]!;
    final ativo = p['ativo'] != false;
    final podeEditar = context.read<AuthProvider>().podeVerFinancas;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(quando, style: const TextStyle(fontSize: 12)),
              value: ativo,
              onChanged: !podeEditar
                  ? null
                  : (v) => setState(() {
                        p['ativo'] = v;
                        _alterado = true;
                      }),
            ),
            if (ativo) ...[
              _passo('Prazo de entrega', perfil, 'prazo', 5, (v) => '+${v.toInt()} min', max: 120),
              _passo('Mínimo do frete grátis', perfil, 'frete_gratis', 5, (v) => '+R\$ ${v.toInt()}'),
              _passo('Taxa até 3 km', perfil, 'taxa_ate3km', 1, (v) => '+R\$ ${v.toInt()}', max: 30),
              _passo('Taxa acima de 3 km', perfil, 'taxa_acima3km', 1, (v) => '+R\$ ${v.toInt()}', max: 30),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tabelaFaixas() {
    final faixas = ((_dados?['faixas'] as List?) ?? []).cast<Map>();
    final dom = _perfis['domingo']!;
    final hojeAtivo = ((_dados?['hoje'] as List?) ?? []).any((a) => a['status'] == 'ativo');
    if (faixas.isEmpty) return const SizedBox.shrink();
    const estilo = TextStyle(fontSize: 12);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Como fica no domingo (por faixa)', style: TextStyle(fontWeight: FontWeight.w600)),
            if (hojeAtivo)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('Hoje o modo está ligado: os valores "normal" abaixo já incluem o ajuste.', style: TextStyle(fontSize: 12, color: Colors.deepOrange)),
              ),
            const SizedBox(height: 8),
            Table(
              columnWidths: const {0: FlexColumnWidth(1.3)},
              children: [
                const TableRow(children: [
                  Text('Faixa', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  Text('Taxa', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  Text('Grátis acima de', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  Text('Prazo', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
                ...faixas.map((f) {
                  final perto = ((f['max_km'] as num?) ?? 99) <= 3;
                  final taxa = (f['taxa'] as num? ?? 0) + (perto ? _n(dom, 'taxa_ate3km') : _n(dom, 'taxa_acima3km'));
                  final fg = (f['frete_gratis'] as num?) == null ? null : (f['frete_gratis'] as num) + _n(dom, 'frete_gratis');
                  final pMin = (f['prazo_min'] as num? ?? 0) + _n(dom, 'prazo');
                  final pMax = (f['prazo_max'] as num? ?? 0) + _n(dom, 'prazo');
                  return TableRow(children: [
                    Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Text(f['nome'] as String, style: estilo)),
                    Text('${_r(f['taxa'] as num? ?? 0)} → ${_r(taxa)}', style: estilo),
                    Text(fg == null ? '—' : '${_r(f['frete_gratis'] as num)} → ${_r(fg)}', style: estilo),
                    Text('${pMin.toInt()}–${pMax.toInt()} min', style: estilo),
                  ]);
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cartaoHoje() {
    final hoje = ((_dados?['hoje'] as List?) ?? []).cast<Map>();
    final ativos = hoje.where((a) => a['status'] == 'ativo').length;
    final pulados = hoje.where((a) => a['status'] == 'pulado').length;
    final origem = hoje.map((a) => (a['detalhe'] as String?) ?? '').firstWhere((d) => d.startsWith('automático'), orElse: () => '');
    final String texto;
    if (hoje.isEmpty) {
      texto = 'Hoje está tudo no normal.';
    } else if (ativos > 0) {
      texto = 'Ligado hoje${origem.isNotEmpty ? ' (${origem.replaceFirst('automático: ', 'modo ')})' : ''}: $ativos ajuste(s) valendo, voltam à meia-noite.'
          '${pulados > 0 ? ' $pulados não voltaram porque você mudou à mão.' : ''}';
    } else {
      texto = 'Os ajustes de hoje já voltaram ao normal.';
    }
    return Card(
      child: ListTile(
        leading: Icon(ativos > 0 ? Icons.toggle_on : Icons.toggle_off_outlined, color: ativos > 0 ? Colors.green : null),
        title: const Text('Hoje no site e no WhatsApp'),
        subtitle: Text(texto),
      ),
    );
  }

  Widget _cartaoIfood() {
    final v = _dados?['ultima_verificacao_ifood'] as Map?;
    String verificacao = 'Ainda não houve verificação (roda aos domingos, 8h30–14h30).';
    if (v != null) {
      final status = v['status'];
      verificacao = switch (status) {
        'ok' => '${v['data']}: pré-configuração DOMINGO ativa ✅ (menor prazo ${v['menor_prazo_visto']} min).',
        'nao_aplicada' => '${v['data']}: DOMINGO NÃO entrou ⚠️ (um pedido saiu com ${v['menor_prazo_visto']} min).',
        'sem_pedidos' => '${v['data']}: sem pedidos do iFood até 13h pra conferir.',
        _ => '${v['data']}: aguardando o primeiro pedido do iFood.',
      };
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('iFood (configurado no Portal do Parceiro)', style: TextStyle(fontWeight: FontWeight.w600)),
            SizedBox(height: 8),
            Text('• DOMINGO — agendada todo domingo: prazo 59 a 109 min, frete R\$ 4,99 a R\$ 31,99.', style: TextStyle(fontSize: 13)),
            Text('• FERIADO — ligada no dia do feriado: prazo 59 a 109 min, frete R\$ 4,99 a R\$ 34,99.', style: TextStyle(fontSize: 13)),
            Text('• Pedido mínimo: R\$ 40 no domingo e R\$ 50 no feriado (robô do Portal muda na véspera às 23h30 e volta às 23h25).', style: TextStyle(fontSize: 13)),
            Text('• Promoção de frete grátis paga pela loja: o robô sai no feriado (e nos domingos de teste até 29/11) e volta às 23h27.', style: TextStyle(fontSize: 13)),
          ],
        ).copyWithVerificacao(verificacao),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final podeEditar = context.watch<AuthProvider>().podeVerFinancas;
    return Scaffold(
      appBar: AppBar(title: const Text('Domingo e feriado')),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  if (_erro != null) Padding(padding: const EdgeInsets.all(24), child: Text(_erro!, textAlign: TextAlign.center)),
                  if (_dados != null) ...[
                    const Text(
                      'No site e no WhatsApp, entra sozinho às 00:05 e volta à meia-noite. Em feriado com a loja fechada, não liga.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    _cartaoHoje(),
                    _cartaoPerfil('domingo', 'Domingo', 'Todo domingo'),
                    _cartaoPerfil('feriado', 'Feriado', 'Feriado em que a loja abre (tem prioridade sobre o domingo)'),
                    if (podeEditar && _alterado)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: FilledButton(
                          onPressed: _salvando ? null : _salvar,
                          child: Text(_salvando ? 'Salvando…' : 'Salvar'),
                        ),
                      ),
                    _tabelaFaixas(),
                    _cartaoIfood(),
                  ],
                ],
              ),
      ),
    );
  }
}

extension on Column {
  /// Acrescenta a linha da última verificação no fim do cartão do iFood.
  Column copyWithVerificacao(String texto) => Column(
        crossAxisAlignment: crossAxisAlignment,
        children: [
          ...children,
          const SizedBox(height: 8),
          Text('Verificação automática: $texto', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      );
}
