import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/pausa_loja.dart';
import '../providers/auth_provider.dart';
import '../repositories/pausa_loja_repository.dart';

/// Configurações > Pausar Loja: pausa imediata ou agendada pro futuro,
/// valendo de uma vez pra site, WhatsApp e integrações de marketplace
/// (iFood/99Food) — a trava real fica no banco (`_finalizar_pedido_core`
/// bloqueia pedido imediato durante a pausa; o pg_cron
/// `processar-pausas-loja` promove/finaliza sozinho). Pedidos já em
/// andamento continuam normalmente — a pausa só impede pedido NOVO
/// imediato (Expressa/"Quero agora"); Agendado e Econômico continuam
/// disponíveis, só não podem cair dentro da janela pausada.
class PausarLojaScreen extends StatefulWidget {
  const PausarLojaScreen({super.key});

  @override
  State<PausarLojaScreen> createState() => _PausarLojaScreenState();
}

class _PausarLojaScreenState extends State<PausarLojaScreen> {
  final _repository = PausaLojaRepository();

  List<PausaLoja> _pausas = [];
  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final pausas = await _repository.listarAtivasOuAgendadas();
      if (mounted) setState(() => _pausas = pausas);
    } catch (e) {
      debugPrint('Erro ao carregar pausas da loja: $e');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  PausaLoja? get _pausaAtiva => _pausas.where((p) => p.ativa).firstOrNull;
  List<PausaLoja> get _proximasAgendadas => _pausas.where((p) => p.agendada).toList();

  Duration _ateOFimDoDia() {
    final agora = DateTime.now();
    final fimDoDia = DateTime(agora.year, agora.month, agora.day, 23, 59);
    return fimDoDia.difference(agora);
  }

  Future<void> _pausarAgora() async {
    final motivoController = TextEditingController();
    Duration duracaoEscolhida = const Duration(hours: 1);

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Pausar loja agora'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: motivoController,
                decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
              ),
              const SizedBox(height: 16),
              const Text('Por quanto tempo?', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  ('30 min', const Duration(minutes: 30)),
                  ('1 hora', const Duration(hours: 1)),
                  ('2 horas', const Duration(hours: 2)),
                  ('Resto do dia', null),
                ].map((opcao) {
                  final (rotulo, duracao) = opcao;
                  final selecionado =
                      duracao == duracaoEscolhida || (duracao == null && duracaoEscolhida == _ateOFimDoDia());
                  return ChoiceChip(
                    label: Text(rotulo),
                    selected: selecionado,
                    onSelected: (_) => setDialogState(() => duracaoEscolhida = duracao ?? _ateOFimDoDia()),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Pausar')),
          ],
        ),
      ),
    );
    if (confirmado != true) return;

    final agora = DateTime.now();
    await _salvar(motivo: motivoController.text.trim(), inicio: agora, fim: agora.add(duracaoEscolhida));
  }

  Future<void> _agendarPausa() async {
    final motivoController = TextEditingController();
    // Início e fim têm CADA UM sua própria data — antes só existia 1 data
    // pro dia inteiro, o que impedia pausar por vários dias seguidos
    // (ex: viagem, feriado prolongado). Reportado pelo usuário testando.
    DateTime dataInicio = DateTime.now();
    TimeOfDay horaInicio = const TimeOfDay(hour: 14, minute: 0);
    DateTime dataFim = DateTime.now();
    TimeOfDay horaFim = const TimeOfDay(hour: 16, minute: 0);

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Agendar pausa'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: motivoController,
                  decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
                ),
                const SizedBox(height: 16),
                const Text('Início', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(DateFormat('dd/MM/yyyy').format(dataInicio)),
                  leading: const Icon(Icons.calendar_today_outlined),
                  onTap: () async {
                    final escolhida = await showDatePicker(
                      context: ctx,
                      initialDate: dataInicio,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 90)),
                    );
                    if (escolhida != null) {
                      setDialogState(() {
                        dataInicio = escolhida;
                        // Fim nunca pode ficar antes do início — empurra junto.
                        if (dataFim.isBefore(dataInicio)) dataFim = dataInicio;
                      });
                    }
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('Hora: ${horaInicio.format(ctx)}'),
                  leading: const Icon(Icons.schedule_outlined),
                  onTap: () async {
                    final escolhida = await showTimePicker(context: ctx, initialTime: horaInicio);
                    if (escolhida != null) setDialogState(() => horaInicio = escolhida);
                  },
                ),
                const SizedBox(height: 12),
                const Text('Fim', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(DateFormat('dd/MM/yyyy').format(dataFim)),
                  leading: const Icon(Icons.calendar_today_outlined),
                  onTap: () async {
                    final escolhida = await showDatePicker(
                      context: ctx,
                      initialDate: dataFim.isBefore(dataInicio) ? dataInicio : dataFim,
                      firstDate: dataInicio,
                      lastDate: DateTime.now().add(const Duration(days: 90)),
                    );
                    if (escolhida != null) setDialogState(() => dataFim = escolhida);
                  },
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('Hora: ${horaFim.format(ctx)}'),
                  leading: const Icon(Icons.schedule_outlined),
                  onTap: () async {
                    final escolhida = await showTimePicker(context: ctx, initialTime: horaFim);
                    if (escolhida != null) setDialogState(() => horaFim = escolhida);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Agendar')),
          ],
        ),
      ),
    );
    if (confirmado != true) return;

    final inicio = DateTime(dataInicio.year, dataInicio.month, dataInicio.day, horaInicio.hour, horaInicio.minute);
    final fim = DateTime(dataFim.year, dataFim.month, dataFim.day, horaFim.hour, horaFim.minute);

    if (!fim.isAfter(inicio)) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('O fim precisa ser depois do início.')));
      }
      return;
    }
    if (!inicio.isAfter(DateTime.now())) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Pra pausar já a partir de agora, use "Pausar agora".')));
      }
      return;
    }

    await _salvar(motivo: motivoController.text.trim(), inicio: inicio, fim: fim);
  }

  Future<void> _salvar({required String motivo, required DateTime inicio, required DateTime fim}) async {
    final auth = context.read<AuthProvider>();
    final empresaId = auth.empresaId;
    if (empresaId == null) return;

    setState(() => _salvando = true);
    try {
      await _repository.criar(
        empresaId: empresaId,
        criadoPor: auth.usuarioAtual?.id,
        motivo: motivo.isEmpty ? null : motivo,
        inicio: inicio,
        fim: fim,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pausa salva.')));
      await _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível salvar.')));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _cancelar(PausaLoja pausa) async {
    try {
      await _repository.cancelar(pausa.id);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(pausa.ativa ? 'Loja reaberta.' : 'Pausa agendada cancelada.')));
      }
      await _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível cancelar.')));
    }
  }

  Widget _cardStatus() {
    final pausa = _pausaAtiva;
    final dateFormat = DateFormat('dd/MM HH:mm');

    if (pausa == null) {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.storefront, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 10),
              const Expanded(child: Text('Loja aberta normalmente')),
            ],
          ),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.pause_circle_outline, color: Colors.orange),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Loja em pausa${pausa.motivo != null ? ': ${pausa.motivo}' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('Volta às ${dateFormat.format(pausa.fim)}',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            TextButton(onPressed: () => _cancelar(pausa), child: const Text('Retomar agora')),
          ],
        ),
      ),
    );
  }

  Widget _listaAgendadas() {
    final agendadas = _proximasAgendadas;
    if (agendadas.isEmpty) return const SizedBox.shrink();

    final dateFormat = DateFormat('dd/MM HH:mm');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 8, bottom: 4),
          child: Text('Próximas pausas agendadas', style: TextStyle(fontWeight: FontWeight.w600)),
        ),
        ...agendadas.map((pausa) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.event_outlined),
                title: Text(pausa.motivo ?? 'Sem motivo informado'),
                subtitle: Text('${dateFormat.format(pausa.inicio)} — ${dateFormat.format(pausa.fim)}'),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cancelar',
                  onPressed: () => _cancelar(pausa),
                ),
              ),
            )),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pausar Loja')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Pausa vale pro site, WhatsApp e integrações (iFood/99Food) de uma vez só. '
                  'Pedidos já em andamento continuam normalmente — só bloqueia pedido novo imediato '
                  '(Expressa/"Quero agora"); Agendado e Econômico continuam disponíveis.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 12),
                _cardStatus(),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _salvando ? null : _pausarAgora,
                        icon: const Icon(Icons.pause_outlined),
                        label: const Text('Pausar agora'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _salvando ? null : _agendarPausa,
                        icon: const Icon(Icons.event_outlined),
                        label: const Text('Agendar pausa'),
                      ),
                    ),
                  ],
                ),
                _listaAgendadas(),
              ],
            ),
    );
  }
}
