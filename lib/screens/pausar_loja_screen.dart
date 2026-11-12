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
  /// Marketplaces ligados (id + nome) — canais além de 'proprios' (site + WhatsApp).
  List<({String id, String nome})> _marketplaces = [];
  /// Interrupções que as pausas ativas geraram em cada marketplace (status real da aplicação).
  List<Map<String, dynamic>> _interrupcoes = [];
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
      final marketplaces = await _repository.listarMarketplacesAtivos();
      final ativas = pausas.where((p) => p.ativa).map((p) => p.id).toList();
      final interrupcoes = ativas.isEmpty ? <Map<String, dynamic>>[] : await _repository.interrupcoesDasPausas(ativas);
      if (mounted) {
        setState(() {
          _pausas = pausas;
          _marketplaces = marketplaces;
          _interrupcoes = interrupcoes;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar pausas da loja: $e');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  List<PausaLoja> get _pausasAtivas => _pausas.where((p) => p.ativa).toList();

  /// Canais possíveis: 'proprios' (site + WhatsApp) + cada marketplace ligado.
  List<({String id, String nome})> get _canais => [(id: 'proprios', nome: 'Site e WhatsApp'), ..._marketplaces];

  bool _pausaValeNoCanal(PausaLoja p, String canal) => p.canais == null || p.canais!.contains(canal);

  String _rotuloCanais(PausaLoja p) {
    if (p.canais == null) return 'Todos os canais';
    return _canais.where((c) => p.canais!.contains(c.id)).map((c) => c.nome).join(', ');
  }

  /// Seletor de canais nos diálogos. Tudo marcado = null (todos, inclusive marketplaces ligados no futuro).
  Widget _seletorCanais(Set<String> escolhidos, void Function(void Function()) setDialogState) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Onde pausar?', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          children: _canais
              .map((c) => FilterChip(
                    label: Text(c.nome),
                    selected: escolhidos.contains(c.id),
                    onSelected: (v) => setDialogState(() => v ? escolhidos.add(c.id) : escolhidos.remove(c.id)),
                  ))
              .toList(),
        ),
      ],
    );
  }

  List<String>? _canaisParaSalvar(Set<String> escolhidos) =>
      escolhidos.length == _canais.length ? null : escolhidos.toList();
  List<PausaLoja> get _proximasAgendadas => _pausas.where((p) => p.agendada).toList();

  Duration _ateOFimDoDia() {
    final agora = DateTime.now();
    final fimDoDia = DateTime(agora.year, agora.month, agora.day, 23, 59);
    return fimDoDia.difference(agora);
  }

  Future<void> _pausarAgora() async {
    final motivoController = TextEditingController();
    Duration duracaoEscolhida = const Duration(hours: 1);
    final canaisEscolhidos = _canais.map((c) => c.id).toSet();

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
              const SizedBox(height: 16),
              _seletorCanais(canaisEscolhidos, setDialogState),
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
    if (canaisEscolhidos.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Escolha pelo menos um canal.')));
      return;
    }

    final agora = DateTime.now();
    await _salvar(
        motivo: motivoController.text.trim(),
        inicio: agora,
        fim: agora.add(duracaoEscolhida),
        canais: _canaisParaSalvar(canaisEscolhidos));
  }

  Future<void> _agendarPausa() async {
    final motivoController = TextEditingController();
    // Início e fim têm CADA UM sua própria data — antes só existia 1 data
    // pro dia inteiro, o que impedia pausar por vários dias seguidos
    // (ex: viagem, feriado prolongado). Reportado pelo usuário testando.
    // Sugestão: próxima hora cheia, por 2 h. Antes vinha fixo 14h–16h de
    // hoje e, aberto depois das 14h, o agendamento era recusado sem salvar
    // (visto em 11/11 às 16h14).
    final agora = DateTime.now();
    final sugestaoInicio = DateTime(agora.year, agora.month, agora.day, agora.hour).add(const Duration(hours: 1));
    final sugestaoFim = sugestaoInicio.add(const Duration(hours: 2));
    DateTime dataInicio = DateTime(sugestaoInicio.year, sugestaoInicio.month, sugestaoInicio.day);
    TimeOfDay horaInicio = TimeOfDay(hour: sugestaoInicio.hour, minute: 0);
    DateTime dataFim = DateTime(sugestaoFim.year, sugestaoFim.month, sugestaoFim.day);
    TimeOfDay horaFim = TimeOfDay(hour: sugestaoFim.hour, minute: 0);
    final canaisEscolhidos = _canais.map((c) => c.id).toSet();

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
                const SizedBox(height: 12),
                _seletorCanais(canaisEscolhidos, setDialogState),
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
    if (canaisEscolhidos.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Escolha pelo menos um canal.')));
      return;
    }

    var inicio = DateTime(dataInicio.year, dataInicio.month, dataInicio.day, horaInicio.hour, horaInicio.minute);
    final fim = DateTime(dataFim.year, dataFim.month, dataFim.day, horaFim.hour, horaFim.minute);
    final agoraConfirmado = DateTime.now();

    if (!fim.isAfter(inicio)) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('O fim precisa ser depois do início.')));
      }
      return;
    }
    if (!fim.isAfter(agoraConfirmado)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Esse horário já passou. Escolha um fim depois de agora.')));
      }
      return;
    }
    // Início já passou mas o fim ainda não: pausa a partir de agora até o fim
    // escolhido (o repositório grava como 'ativa'), em vez de recusar.
    final comecaAgora = !inicio.isAfter(agoraConfirmado);
    if (comecaAgora) inicio = agoraConfirmado;

    await _salvar(motivo: motivoController.text.trim(), inicio: inicio, fim: fim, canais: _canaisParaSalvar(canaisEscolhidos));
    if (comecaAgora && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('O início já tinha passado: a loja foi pausada agora, até ${DateFormat('dd/MM HH:mm').format(fim)}.')));
    }
  }

  Future<void> _salvar({required String motivo, required DateTime inicio, required DateTime fim, List<String>? canais}) async {
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
        canais: canais,
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

  /// Situação de cada canal: aberto, ou pausado até HH:mm (com aviso se a plataforma não aplicou).
  Widget _cardStatus() {
    final hora = DateFormat('dd/MM HH:mm');
    final cores = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Situação por canal', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ..._canais.map((c) {
              final pausas = _pausasAtivas.where((p) => _pausaValeNoCanal(p, c.id)).toList()
                ..sort((a, b) => b.fim.compareTo(a.fim));
              final pausa = pausas.firstOrNull;
              final interrupcao = pausa == null || c.id == 'proprios'
                  ? null
                  : _interrupcoes
                      .where((i) => i['origem_pausa_id'] == pausa.id && i['marketplace_id'].toString() == c.id)
                      .firstOrNull;
              final falhou = interrupcao != null && interrupcao['status'] == 'erro';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Icon(pausa == null ? Icons.check_circle : Icons.pause_circle_filled,
                        size: 18, color: pausa == null ? Colors.green : Colors.orange),
                    const SizedBox(width: 8),
                    Expanded(child: Text(c.nome)),
                    Text(
                      pausa == null ? 'Aberto' : 'Pausado até ${hora.format(pausa.fim)}',
                      style: TextStyle(
                          fontSize: 13,
                          color: pausa == null ? Colors.green : Colors.orange,
                          fontWeight: FontWeight.w600),
                    ),
                    if (falhou)
                      Tooltip(
                        message: interrupcao['erro']?.toString() ?? 'A plataforma não aceitou a pausa',
                        child: const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Text('⚠ não aplicou', style: TextStyle(fontSize: 12, color: Colors.red)),
                        ),
                      ),
                  ],
                ),
              );
            }),
            if (_pausasAtivas.isNotEmpty) ...[
              const Divider(height: 20),
              ..._pausasAtivas.map((p) => Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Pausa${p.motivo != null ? ': ${p.motivo}' : ''}',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            Text('${_rotuloCanais(p)} · volta às ${hora.format(p.fim)}',
                                style: TextStyle(fontSize: 12, color: cores.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      TextButton(onPressed: () => _cancelar(p), child: const Text('Retomar agora')),
                    ],
                  )),
            ],
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
                subtitle: Text('${dateFormat.format(pausa.inicio)} — ${dateFormat.format(pausa.fim)} · ${_rotuloCanais(pausa)}'),
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
                  'Escolha onde a pausa vale: site e WhatsApp, iFood, 99Food ou todos. '
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
