import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/auth_provider.dart';
import '../repositories/datas_especiais_repository.dart';

/// Feriados e datas especiais: o calendário da loja (feriados nacionais e da
/// cidade, datas do mundo pet, datas e temporadas de vendas). Nos feriados o
/// dono escolhe em 1 toque como a loja funciona — normal, horário especial
/// ou fechada — e isso vale no site, WhatsApp, iFood e 99Food.
/// O banco avisa (notificação 'data_especial', 08:00) com antecedência.
class DatasEspeciaisScreen extends StatefulWidget {
  const DatasEspeciaisScreen({super.key});

  @override
  State<DatasEspeciaisScreen> createState() => _DatasEspeciaisScreenState();
}

class _DatasEspeciaisScreenState extends State<DatasEspeciaisScreen> {
  final _repo = DatasEspeciaisRepository();
  List<DataEspecial> _datas = [];
  /// Recomendação por feriado (chave = id|data). Carrega depois da lista.
  final Map<String, Map<String, dynamic>> _recs = {};
  bool _carregando = true;
  String? _erro;

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
      final datas = await _repo.proximas(dias: 120);
      if (mounted) setState(() => _datas = datas);
      _carregarRecomendacoes(datas);
    } catch (e) {
      if (mounted) setState(() => _erro = 'Não deu pra carregar o calendário. Puxe pra tentar de novo.');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  String _chave(DataEspecial d) => '${d.id}|${d.inicio.toIso8601String()}';

  Future<void> _carregarRecomendacoes(List<DataEspecial> datas) async {
    for (final d in datas.where((d) => d.ehFeriado && d.diasPara >= 0 && d.diasPara <= 45)) {
      try {
        final r = await _repo.recomendar(d.id, d.inicio);
        if (r != null && mounted) setState(() => _recs[_chave(d)] = r);
      } catch (_) {
        // Sem recomendação, a tela segue funcionando.
      }
    }
  }

  String _textoRecomendacao(Map<String, dynamic> r) {
    final ped = (r['pedidos'] as num?)?.round() ?? 0;
    switch (r['modo']) {
      case 'fechada':
        return 'Recomendado: fechar';
      case 'normal':
        return 'Recomendado: horário normal · ~$ped pedidos · R\$ ${r['lucro']}';
      default:
        return 'Recomendado: ${r['abre']}–${r['fecha']} · ~$ped pedidos · R\$ ${r['lucro']}';
    }
  }

  static const _semana = ['', 'seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];

  String _quando(DataEspecial d) {
    final dia = '${_semana[d.inicio.weekday]}, ${DateFormat('dd/MM').format(d.inicio)}';
    if (d.fim.isAfter(d.inicio)) {
      final ate = DateFormat('dd/MM').format(d.fim);
      if (d.emAndamento) return 'Em andamento · até $ate';
      return '$dia até $ate';
    }
    if (d.diasPara == 0) return 'Hoje · $dia';
    if (d.diasPara == 1) return 'Amanhã · $dia';
    return 'Em ${d.diasPara} dias · $dia';
  }

  String _rotuloFuncionamento(DataEspecial d) {
    switch (d.funcionamento) {
      case 'normal':
        final h = d.horarioNormal;
        return h != null && h['aberto'] == true ? 'Horário normal (${h['abre']}–${h['fecha']})' : 'Horário normal';
      case 'especial':
        return 'Horário especial: ${d.abre}–${d.fecha}';
      case 'fechada':
        return 'Loja fechada';
      default:
        return 'Toque pra escolher o horário';
    }
  }

  TimeOfDay _parse(String? s, TimeOfDay padrao) {
    if (s == null) return padrao;
    final p = s.split(':');
    if (p.length < 2) return padrao;
    return TimeOfDay(hour: int.tryParse(p[0]) ?? padrao.hour, minute: int.tryParse(p[1]) ?? padrao.minute);
  }

  String _fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _escolherFuncionamento(DataEspecial d) async {
    final auth = context.read<AuthProvider>();
    if (!(auth.isDono || auth.isGerente)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Só o dono ou o gerente pode mudar o horário da loja.')),
      );
      return;
    }
    final normal = d.horarioNormal;
    var abre = _parse(d.abre ?? normal?['abre']?.toString(), const TimeOfDay(hour: 9, minute: 0));
    var fecha = _parse(d.fecha ?? normal?['fecha']?.toString(), const TimeOfDay(hour: 14, minute: 0));
    final rec = _recs[_chave(d)];
    var modo = d.funcionamento ?? (rec?['modo'] as String?) ?? 'especial';
    if (d.funcionamento == null && rec != null && rec['modo'] == 'especial') {
      abre = _parse(rec['abre']?.toString(), abre);
      fecha = _parse(rec['fecha']?.toString(), fecha);
    }

    final confirmado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(d.nome, style: Theme.of(ctx).textTheme.titleMedium),
                Text('${_semana[d.inicio.weekday]}, ${DateFormat('dd/MM/yyyy').format(d.inicio)}',
                    style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                if (d.dica != null) ...[
                  const SizedBox(height: 8),
                  Text(d.dica!, style: const TextStyle(fontSize: 13)),
                ],
                if (rec != null) ...[
                  const SizedBox(height: 12),
                  _blocoRecomendacao(ctx, rec, () => setSheet(() {
                        modo = rec['modo'] as String;
                        if (modo == 'especial') {
                          abre = _parse(rec['abre']?.toString(), abre);
                          fecha = _parse(rec['fecha']?.toString(), fecha);
                        }
                      })),
                ],
                const SizedBox(height: 16),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'normal', label: Text('Normal')),
                    ButtonSegment(value: 'especial', label: Text('Especial')),
                    ButtonSegment(value: 'fechada', label: Text('Fechada')),
                  ],
                  selected: {modo},
                  onSelectionChanged: (s) => setSheet(() => modo = s.first),
                ),
                const SizedBox(height: 12),
                if (modo == 'normal')
                  Text(
                    normal != null && normal['aberto'] == true
                        ? 'Abre no horário de sempre: ${normal['abre']}–${normal['fecha']}.'
                        : 'Segue o horário de funcionamento cadastrado.',
                  ),
                if (modo == 'fechada')
                  const Text('Site e WhatsApp não aceitam pedido pra agora, e iFood e 99Food ficam pausados o dia todo. '
                      'Pedido econômico e agendado pra outro dia continuam entrando.'),
                if (modo == 'especial') ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.login, size: 18),
                          label: Text('Abre ${_fmt(abre)}'),
                          onPressed: () async {
                            final t = await showTimePicker(context: ctx, initialTime: abre);
                            if (t != null) setSheet(() => abre = t);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.logout, size: 18),
                          label: Text('Fecha ${_fmt(fecha)}'),
                          onPressed: () async {
                            final t = await showTimePicker(context: ctx, initialTime: fecha);
                            if (t != null) setSheet(() => fecha = t);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('Fora desse horário a loja fica em pausa no site, WhatsApp, iFood e 99Food.',
                      style: TextStyle(fontSize: 12)),
                ],
                const SizedBox(height: 16),
                FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
              ],
            ),
          ),
        ),
      ),
    );
    if (confirmado != true || !mounted) return;

    if (modo == 'especial' && (abre.hour * 60 + abre.minute) >= (fecha.hour * 60 + fecha.minute)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('O horário de abrir tem que ser antes do de fechar.')));
      return;
    }
    try {
      await _repo.definirFuncionamento(
        dataEspecialId: d.id,
        data: d.inicio,
        modo: modo,
        abre: modo == 'especial' ? _fmt(abre) : null,
        fecha: modo == 'especial' ? _fmt(fecha) : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${d.nome}: horário salvo em todos os canais.')));
      _carregar();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não deu pra salvar. Tente de novo.')));
    }
  }

  Widget _blocoRecomendacao(BuildContext ctx, Map<String, dynamic> r, VoidCallback usar) {
    final cs = Theme.of(ctx).colorScheme;
    final faixas = (r['faixas'] as List? ?? []).cast<Map>();
    final motivos = (r['motivos'] as List? ?? []).cast<String>();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Color.alphaBlend(cs.primary.withValues(alpha: 0.08), cs.surface),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.insights_outlined, size: 18, color: cs.primary),
            const SizedBox(width: 6),
            Expanded(child: Text(_textoRecomendacao(r), style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
          const SizedBox(height: 8),
          ...faixas.map((f) {
            final lucro = (f['lucro'] as num?) ?? 0;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(children: [
                SizedBox(width: 120, child: Text('${f['faixa']} ${f['de']}–${f['ate']}', style: const TextStyle(fontSize: 12))),
                Expanded(child: Text('~${(f['pedidos'] as num).toStringAsFixed(1).replaceAll('.', ',')} pedidos', style: const TextStyle(fontSize: 12))),
                Text('${lucro < 0 ? '-' : ''}R\$ ${lucro.abs()}',
                    style: TextStyle(fontSize: 12, color: lucro < 0 ? Colors.red : null, fontWeight: FontWeight.w600)),
              ]),
            );
          }),
          Theme(
            data: Theme.of(ctx).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              dense: true,
              title: Text('Por quê? (confiança ${r['confianca']})', style: const TextStyle(fontSize: 12)),
              children: motivos
                  .map((m) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('•  ', style: TextStyle(fontSize: 12)),
                          Expanded(child: Text(m, style: const TextStyle(fontSize: 12))),
                        ]),
                      ))
                  .toList(),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: usar, child: const Text('Usar recomendação')),
          ),
        ],
      ),
    );
  }

  (IconData, Color) _iconeCor(String categoria) {
    switch (categoria) {
      case 'feriado':
        return (Icons.event_busy_outlined, Colors.deepOrange);
      case 'pet':
        return (Icons.pets_outlined, Colors.teal);
      case 'vendas':
        return (Icons.local_offer_outlined, Colors.indigo);
      default:
        return (Icons.wb_sunny_outlined, Colors.amber.shade800);
    }
  }

  Widget _secao(String titulo, String subtitulo, List<DataEspecial> itens) {
    if (itens.isEmpty) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(titulo, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        Text(subtitulo, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 8),
        ...itens.map(_cartao),
      ],
    );
  }

  Widget _cartao(DataEspecial d) {
    final (icone, cor) = _iconeCor(d.categoria);
    final cs = Theme.of(context).colorScheme;
    final pendente = d.ehFeriado && !d.decidido;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: d.ehFeriado ? () => _escolherFuncionamento(d) : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icone, color: cor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(_quando(d), style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                    if (d.ehFeriado && !d.decidido && _recs[_chave(d)] != null) ...[
                      const SizedBox(height: 4),
                      Text(_textoRecomendacao(_recs[_chave(d)]!),
                          style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary)),
                    ],
                    if (d.ehFeriado) ...[
                      const SizedBox(height: 4),
                      Text(
                        _rotuloFuncionamento(d),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: pendente ? FontWeight.w600 : FontWeight.normal,
                          color: pendente ? Colors.deepOrange : null,
                        ),
                      ),
                    ],
                    if (d.dica != null && !d.ehFeriado) ...[
                      const SizedBox(height: 4),
                      Text(d.dica!, style: const TextStyle(fontSize: 13)),
                    ],
                  ],
                ),
              ),
              if (d.ehFeriado) const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final feriados = _datas.where((d) => d.ehFeriado).toList();
    final temporadas = _datas.where((d) => d.categoria == 'temporada').toList();
    final datas = _datas.where((d) => d.categoria == 'pet' || d.categoria == 'vendas').toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Feriados e datas especiais')),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: _carregando
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                children: [
                  if (_erro != null)
                    Padding(padding: const EdgeInsets.only(top: 24), child: Text(_erro!, textAlign: TextAlign.center)),
                  _secao('Feriados', 'Escolha como a loja funciona. Vale no site, WhatsApp, iFood e 99Food.', feriados),
                  _secao('Temporadas de venda', 'Épocas em que alguns produtos vendem mais.', temporadas),
                  _secao('Datas do mundo pet e de vendas', 'Boas datas pra post, promoção ou ação com clientes.', datas),
                  const SizedBox(height: 16),
                  Text('Você recebe um aviso no app alguns dias antes de cada data.',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
      ),
    );
  }
}
