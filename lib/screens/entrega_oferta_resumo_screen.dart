import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Resumo do entregador por oferta (25/11): valeu a pena? Frete cobrado × pago aos motoboys, custo por
/// entrega, quantas ofertas foram aceitas e em quanto tempo, e a confiabilidade de cada motoboy
/// (recusas, desistências, saiu atrasado, não entregues). RPC entrega_oferta_resumo(dias).
class EntregaOfertaResumoScreen extends StatefulWidget {
  const EntregaOfertaResumoScreen({super.key});

  @override
  State<EntregaOfertaResumoScreen> createState() => _EntregaOfertaResumoScreenState();
}

class _EntregaOfertaResumoScreenState extends State<EntregaOfertaResumoScreen> {
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  int _dias = 7;
  Map<String, dynamic>? _r;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final r = await Supabase.instance.client.rpc('entrega_oferta_resumo', params: {'p_dias': _dias});
      if (mounted) setState(() => _r = Map<String, dynamic>.from(r as Map));
    } catch (e) {
      debugPrint('Erro no resumo: $e');
    }
    if (mounted) setState(() => _carregando = false);
  }

  double _n(String k) => (_r?[k] as num?)?.toDouble() ?? 0;

  Widget _numero(String rotulo, String valor, {Color? cor, String? ajuda}) => Expanded(
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rotulo, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 4),
                Text(valor, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: cor)),
                if (ajuda != null) Text(ajuda, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final entregas = _n('entregas');
    final pago = _n('pago_motoboys');
    final frete = _n('frete_cobrado');
    final saldo = frete - pago;
    final ofertadas = _n('ofertadas');
    final aceitas = _n('aceitas');
    final motoboys = (_r?['motoboys'] as List?) ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Resumo das entregas')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final d in [1, 7, 30])
                        ChoiceChip(
                          label: Text(d == 1 ? 'Hoje' : '$d dias'),
                          selected: _dias == d,
                          onSelected: (_) {
                            setState(() => _dias = d);
                            _carregar();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    _numero('Frete cobrado', _moeda.format(frete)),
                    _numero('Pago aos motoboys', _moeda.format(pago)),
                  ]),
                  Row(children: [
                    _numero(saldo >= 0 ? 'Sobrou do frete' : 'Faltou do frete', _moeda.format(saldo.abs()),
                        cor: saldo >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                        ajuda: saldo >= 0 ? null : 'A entrega saiu do lucro dos produtos'),
                    _numero('Custo por entrega', entregas == 0 ? '—' : _moeda.format(pago / entregas),
                        ajuda: '${entregas.toInt()} entregas · ${_n('rotas_concluidas').toInt()} rotas'),
                  ]),
                  Row(children: [
                    _numero('Ofertas aceitas', ofertadas == 0 ? '—' : '${(aceitas / ofertadas * 100).round()}%',
                        ajuda: '${aceitas.toInt()} de ${ofertadas.toInt()} rotas'),
                    _numero('Tempo até aceitar', _r?['min_ate_aceite'] == null ? '—' : '${_r!['min_ate_aceite']} min',
                        ajuda: '${_n('sem_motoboy').toInt()} ficaram sem motoboy'),
                  ]),
                  const SizedBox(height: 16),
                  Text('Motoboys', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (motoboys.isEmpty) const Text('Nenhum motoboy recebendo ofertas.'),
                  for (final m in motoboys)
                    Card(
                      child: ListTile(
                        title: Text(m['nome']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text([
                          '${m['rotas']} rota(s)',
                          if ((m['recusas'] as num? ?? 0) > 0) '${m['recusas']} recusa(s)',
                          if ((m['sem_responder'] as num? ?? 0) > 0) '${m['sem_responder']} sem responder',
                          if ((m['desistencias'] as num? ?? 0) > 0) '${m['desistencias']} desistência(s)',
                          if ((m['saiu_atrasado'] as num? ?? 0) > 0) '${m['saiu_atrasado']} saída(s) atrasada(s)',
                          if ((m['nao_entregues'] as num? ?? 0) > 0) '${m['nao_entregues']} não entregue(s)',
                        ].join(' · ')),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
