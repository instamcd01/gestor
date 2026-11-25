import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Acerto com os motoboys do entregador por oferta (25/11): rotas concluídas ainda não acertadas,
/// valor de cada uma, dinheiro que ele recebeu dos clientes e o saldo — positivo a loja paga, negativo
/// ele devolve. "Marcar acertado" fecha tudo (RPC entrega_oferta_acertar, só dono/gerente).
class EntregaOfertaAcertoScreen extends StatefulWidget {
  const EntregaOfertaAcertoScreen({super.key});

  @override
  State<EntregaOfertaAcertoScreen> createState() => _EntregaOfertaAcertoScreenState();
}

class _Rota {
  final DateTime quando;
  final int n;
  final double valor;
  final double dinheiro;
  _Rota(this.quando, this.n, this.valor, this.dinheiro);
}

class _Motoboy {
  final String id;
  final String nome;
  final List<_Rota> rotas = [];
  _Motoboy(this.id, this.nome);
  double get valor => rotas.fold(0, (s, r) => s + r.valor);
  double get dinheiro => rotas.fold(0, (s, r) => s + r.dinheiro);
  double get saldo => valor - dinheiro;
}

class _EntregaOfertaAcertoScreenState extends State<EntregaOfertaAcertoScreen> {
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  List<_Motoboy> _motoboys = [];
  bool _carregando = true;
  String? _erro;
  String? _acertando;

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
      final rows = await Supabase.instance.client
          .from('rotas_entrega')
          .select('entregador_id, finalizada_em, n_pedidos, valor_entregador, dinheiro_recebido, entregador:entregadores(nome)')
          .eq('origem', 'oferta')
          .eq('status', 'concluida')
          .isFilter('acertado_em', null)
          .not('entregador_id', 'is', null)
          .order('finalizada_em');
      final porId = <String, _Motoboy>{};
      for (final r in rows as List) {
        final id = r['entregador_id'] as String;
        final m = porId.putIfAbsent(id, () => _Motoboy(id, (r['entregador'] as Map?)?['nome']?.toString() ?? 'Motoboy'));
        m.rotas.add(_Rota(
          DateTime.tryParse(r['finalizada_em']?.toString() ?? '')?.toLocal() ?? DateTime.now(),
          (r['n_pedidos'] as num?)?.toInt() ?? 1,
          (r['valor_entregador'] as num?)?.toDouble() ?? 0,
          (r['dinheiro_recebido'] as num?)?.toDouble() ?? 0,
        ));
      }
      if (mounted) setState(() => _motoboys = porId.values.toList());
    } catch (e) {
      if (mounted) setState(() => _erro = 'Não foi possível carregar: $e');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  String _textoSaldo(double saldo) => saldo >= 0
      ? 'A loja paga ${_moeda.format(saldo)}'
      : 'Ele devolve ${_moeda.format(-saldo)}';

  Future<void> _acertar(_Motoboy m) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Acerto com ${m.nome}'),
        content: Text('${m.rotas.length} rota(s) · ${_textoSaldo(m.saldo)}.\n\nMarcar como acertado?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Acertado')),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;
    final mensageiro = ScaffoldMessenger.of(context);
    setState(() => _acertando = m.id);
    try {
      final r = await Supabase.instance.client.rpc('entrega_oferta_acertar', params: {'p_entregador_id': m.id})
          as Map<String, dynamic>?;
      mensageiro.showSnackBar(SnackBar(
          content: Text(r?['ok'] == true ? 'Acerto com ${m.nome} registrado.' : (r?['mensagem']?.toString() ?? 'Não deu.'))));
    } catch (e) {
      mensageiro.showSnackBar(SnackBar(content: Text('Não deu pra registrar: $e')));
    }
    if (mounted) setState(() => _acertando = null);
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Acerto com motoboys')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(child: Text(_erro!))
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: _motoboys.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 120),
                          Center(child: Text('Nenhuma rota esperando acerto.')),
                        ])
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            for (final m in _motoboys)
                              Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: ExpansionTile(
                                  title: Text(m.nome, style: const TextStyle(fontWeight: FontWeight.w700)),
                                  subtitle: Text(
                                    '${m.rotas.length} rota(s) · valor ${_moeda.format(m.valor)}'
                                    '${m.dinheiro > 0 ? ' · recebeu ${_moeda.format(m.dinheiro)} em dinheiro' : ''}\n'
                                    '${_textoSaldo(m.saldo)}',
                                    style: TextStyle(color: m.saldo >= 0 ? cores.primary : cores.error),
                                  ),
                                  children: [
                                    for (final r in m.rotas)
                                      ListTile(
                                        dense: true,
                                        title: Text(
                                            '${DateFormat('dd/MM HH:mm').format(r.quando)} · ${r.n} entrega${r.n == 1 ? '' : 's'}'),
                                        trailing: Text(
                                            '${_moeda.format(r.valor)}${r.dinheiro > 0 ? '\n− ${_moeda.format(r.dinheiro)} dinheiro' : ''}',
                                            textAlign: TextAlign.right),
                                      ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                                      child: FilledButton(
                                        onPressed: _acertando == null ? () => _acertar(m) : null,
                                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                                        child: Text(_acertando == m.id ? 'Registrando…' : 'Marcar acertado'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ),
    );
  }
}
