import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/supabase_config.dart';

/// "Robôs do iFood": liga/desliga e edita os dois robôs que mexem no iFood
/// por fora da API oficial.
///
/// - Robô do Portal: em domingo e feriado troca o pedido mínimo e a
///   pré-configuração de entrega e sai das promoções que a loja paga; às
///   23:25 volta tudo ao normal. Configuração em `empresas.ifood_portal_robo`,
///   gravada por `ifood_portal_salvar_config` (reprograma a agenda sem nunca
///   apagar as tarefas de volta ao normal).
/// - Robô do Separador: manda mensagem no chat do pedido pedindo o WhatsApp
///   do cliente (`ifood_chat_conexoes.enviar_mensagens`).
class RobosIfoodScreen extends StatefulWidget {
  const RobosIfoodScreen({super.key});

  @override
  State<RobosIfoodScreen> createState() => _RobosIfoodScreenState();
}

class _PromocaoEditavel {
  final TextEditingController nome;
  String mecanica;
  _PromocaoEditavel(String nome, this.mecanica) : nome = TextEditingController(text: nome);
}

class _RobosIfoodScreenState extends State<RobosIfoodScreen> {
  static const _mecanicas = {
    'free-delivery': 'Entrega grátis',
    'voucher-discounts': 'Cupom / desconto',
  };

  bool _carregando = true;
  bool _salvando = false;
  String? _erro;
  Map<String, dynamic> _painel = {};

  bool _portalAtivo = false;
  final _minNormal = TextEditingController();
  final _minDomingo = TextEditingController();
  final _minFeriado = TextEditingController();
  final _preNormal = TextEditingController();
  final _preDomingo = TextEditingController();
  final _preFeriado = TextEditingController();
  final List<_PromocaoEditavel> _promocoes = [];
  DateTime? _sairDomingoAte;
  bool _alterado = false;

  bool? _enviarMensagens;
  bool _mudandoMensagens = false;

  final _data = DateFormat('dd/MM HH:mm');

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    for (final c in [_minNormal, _minDomingo, _minFeriado, _preNormal, _preDomingo, _preFeriado]) {
      c.dispose();
    }
    for (final p in _promocoes) {
      p.nome.dispose();
    }
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final r = await supabase.rpc('ifood_robos_painel');
      final painel = Map<String, dynamic>.from(r as Map);
      if (!mounted) return;
      setState(() {
        _painel = painel;
        _preencher(Map<String, dynamic>.from((painel['portal_config'] as Map?) ?? {}));
        final sep = painel['separador'] as Map?;
        _enviarMensagens = sep == null ? null : sep['enviar_mensagens'] == true;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = '$e';
        _carregando = false;
      });
    }
  }

  void _preencher(Map<String, dynamic> cfg) {
    String valor(dynamic v) => v is num ? v.toStringAsFixed(v % 1 == 0 ? 0 : 2).replaceAll('.', ',') : '';
    _portalAtivo = cfg['ativo'] == true;
    _minNormal.text = valor(cfg['pedido_minimo_normal']);
    _minDomingo.text = valor(cfg['pedido_minimo_domingo']);
    _minFeriado.text = valor(cfg['pedido_minimo_feriado']);
    _preNormal.text = cfg['preconfig_normal']?.toString() ?? '';
    _preDomingo.text = cfg['preconfig_domingo']?.toString() ?? '';
    _preFeriado.text = cfg['preconfig_feriado']?.toString() ?? '';
    for (final p in _promocoes) {
      p.nome.dispose();
    }
    _promocoes
      ..clear()
      ..addAll(((cfg['promocoes_pagas_loja'] as List?) ?? []).map((p) {
        final m = Map<String, dynamic>.from(p as Map);
        final mec = m['mecanica']?.toString() ?? 'free-delivery';
        return _PromocaoEditavel(m['nome']?.toString() ?? '', _mecanicas.containsKey(mec) ? mec : 'free-delivery');
      }));
    final ate = cfg['sair_promocoes_domingo_ate']?.toString();
    _sairDomingoAte = ate == null || ate.isEmpty ? null : DateTime.tryParse(ate);
    _alterado = false;
  }

  double? _lerValor(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll('R\$', '').replaceAll(' ', '').replaceAll(',', '.'));

  Future<void> _salvarPortal({bool? ativo}) async {
    final valores = [_lerValor(_minNormal), _lerValor(_minDomingo), _lerValor(_minFeriado)];
    if (valores.any((v) => v == null)) {
      _aviso('Preencha os 3 pedidos mínimos (ex.: 30).');
      return;
    }
    if (_promocoes.any((p) => p.nome.text.trim().isEmpty)) {
      _aviso('Tem promoção sem nome — preencha ou tire da lista.');
      return;
    }
    final novoAtivo = ativo ?? _portalAtivo;
    setState(() => _salvando = true);
    try {
      await supabase.rpc('ifood_portal_salvar_config', params: {
        'p_cfg': {
          'ativo': novoAtivo,
          'pedido_minimo_normal': valores[0],
          'pedido_minimo_domingo': valores[1],
          'pedido_minimo_feriado': valores[2],
          'preconfig_normal': _preNormal.text.trim(),
          'preconfig_domingo': _preDomingo.text.trim(),
          'preconfig_feriado': _preFeriado.text.trim(),
          'promocoes_pagas_loja': _promocoes.map((p) => {'nome': p.nome.text.trim(), 'mecanica': p.mecanica}).toList(),
          'sair_promocoes_domingo_ate':
              _sairDomingoAte == null ? null : DateFormat('yyyy-MM-dd').format(_sairDomingoAte!),
        },
      });
      if (!mounted) return;
      _aviso(ativo == null
          ? 'Configuração salva. A agenda do robô foi refeita.'
          : (novoAtivo
              ? 'Robô do Portal ligado.'
              : 'Robô do Portal desligado. Se hoje é domingo/feriado, ele ainda volta tudo ao normal às 23:25.'));
      await _carregar();
    } catch (e) {
      _aviso('Não foi possível salvar: ${_mensagemErro(e)}');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _definirMensagens(bool enviar) async {
    setState(() => _mudandoMensagens = true);
    try {
      await supabase.rpc('ifood_chat_definir_envio', params: {'p_enviar': enviar});
      if (!mounted) return;
      setState(() => _enviarMensagens = enviar);
      _aviso(enviar ? 'Mensagens no chat do iFood ligadas.' : 'Mensagens no chat do iFood desligadas.');
    } catch (e) {
      _aviso('Não foi possível mudar: ${_mensagemErro(e)}');
    } finally {
      if (mounted) setState(() => _mudandoMensagens = false);
    }
  }

  String _mensagemErro(Object e) {
    final s = e.toString();
    final m = RegExp(r'message: ([^,]+)').firstMatch(s);
    return m?.group(1) ?? s;
  }

  void _aviso(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  DateTime? _dataHora(dynamic v) => v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

  /// O robô do Portal entra com a sessão do Separador (dura 48 h e se renova
  /// sozinha); a do Portal é reserva.
  ({bool ok, String texto}) _estadoSessao() {
    final sep = _painel['separador'] as Map?;
    final portal = _painel['portal_conexao'] as Map?;
    final agora = DateTime.now();
    final sepAte = _dataHora(sep?['valida_ate']);
    final portalAte = _dataHora(portal?['valida_ate']);
    if (sepAte != null && sepAte.isAfter(agora)) {
      return (ok: true, texto: 'Conectado ao iFood (sessão do Separador, renova sozinha — válida até ${_data.format(sepAte)})');
    }
    if (portalAte != null && portalAte.isAfter(agora)) {
      return (ok: true, texto: 'Conectado pela sessão do Portal até ${_data.format(portalAte)}');
    }
    return (ok: false, texto: 'Desconectado do iFood — precisa conectar de novo pelo favorito "Conectar iFood".');
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_alterado,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final sair = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Sair sem salvar?'),
            content: const Text('Você mudou a configuração do robô do Portal e ainda não salvou.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Continuar editando')),
              TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sair sem salvar')),
            ],
          ),
        );
        if (sair == true && context.mounted) {
          setState(() => _alterado = false);
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Robôs do iFood'),
          actions: [IconButton(onPressed: _carregando ? null : _carregar, icon: const Icon(Icons.refresh))],
        ),
        body: _carregando
            ? const Center(child: CircularProgressIndicator())
            : _erro != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Não foi possível carregar: $_erro', textAlign: TextAlign.center),
                    ),
                  )
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 820),
                      child: ListView(
                        padding: const EdgeInsets.all(12),
                        children: [
                          _cardPortal(),
                          _cardSeparador(),
                          _cardTarefas('Próximas ações do robô do Portal', _painel['proximas'] as List? ?? [],
                              vazio: 'Nada agendado agora. As ações de domingo/feriado aparecem aqui na véspera.'),
                          _cardTarefas('Últimas ações', _painel['recentes'] as List? ?? [], vazio: 'Nenhuma ainda.'),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }

  Widget _cardPortal() {
    final cs = Theme.of(context).colorScheme;
    final sessao = _estadoSessao();
    void marcar() => setState(() => _alterado = true);

    Widget campo(TextEditingController c, String rotulo, {bool dinheiro = false}) => Expanded(
          child: TextField(
            controller: c,
            onChanged: (_) => marcar(),
            keyboardType: dinheiro ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
            decoration: InputDecoration(
              labelText: rotulo,
              prefixText: dinheiro ? 'R\$ ' : null,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _portalAtivo,
              onChanged: _salvando
                  ? null
                  : (v) async {
                      if (!v) {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Desligar o robô do Portal?'),
                            content: const Text(
                                'Ele para de mudar pedido mínimo, entrega e promoções em domingos e feriados. '
                                'Se hoje já é domingo/feriado, ele ainda volta tudo ao normal às 23:25.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
                              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Desligar')),
                            ],
                          ),
                        );
                        if (ok != true) return;
                      }
                      await _salvarPortal(ativo: v);
                    },
              title: const Text('Robô do Portal do Parceiro', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Em domingo e feriado muda pedido mínimo e entrega e sai das promoções que a loja paga. '
                  'Às 23:25 volta tudo ao normal.'),
            ),
            Row(
              children: [
                Icon(sessao.ok ? Icons.check_circle : Icons.error, size: 18, color: sessao.ok ? Colors.green : cs.error),
                const SizedBox(width: 6),
                Expanded(child: Text(sessao.texto, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant))),
              ],
            ),
            const Divider(height: 28),
            Text('Pedido mínimo no iFood', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(children: [
              campo(_minNormal, 'Dia normal', dinheiro: true),
              const SizedBox(width: 8),
              campo(_minDomingo, 'Domingo', dinheiro: true),
              const SizedBox(width: 8),
              campo(_minFeriado, 'Feriado', dinheiro: true),
            ]),
            const SizedBox(height: 16),
            Text('Pré-configuração de entrega (nome igual ao do Portal)', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(children: [
              campo(_preNormal, 'Dia normal'),
              const SizedBox(width: 8),
              campo(_preDomingo, 'Domingo'),
              const SizedBox(width: 8),
              campo(_preFeriado, 'Feriado'),
            ]),
            const SizedBox(height: 4),
            Text('No domingo o robô hoje só troca o pedido mínimo; a pré-configuração de entrega muda no feriado.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 16),
            Text('Promoções que a loja paga', style: Theme.of(context).textTheme.titleSmall),
            Text('Sai delas às 00:05 do feriado e volta às 23:27. Nome exatamente como aparece no card do Portal.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            for (final (i, p) in _promocoes.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: p.nome,
                        onChanged: (_) => marcar(),
                        decoration: const InputDecoration(
                            labelText: 'Nome da promoção', border: OutlineInputBorder(), isDense: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 170,
                      child: DropdownButtonFormField<String>(
                        initialValue: p.mecanica,
                        isDense: true,
                        decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                        items: _mecanicas.entries
                            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                            .toList(),
                        onChanged: (v) => setState(() {
                          p.mecanica = v ?? p.mecanica;
                          _alterado = true;
                        }),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Tirar da lista',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => setState(() {
                        _promocoes.removeAt(i).nome.dispose();
                        _alterado = true;
                      }),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  _promocoes.add(_PromocaoEditavel('', 'free-delivery'));
                  _alterado = true;
                }),
                icon: const Icon(Icons.add),
                label: const Text('Adicionar promoção'),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Sair das promoções também no domingo'),
              subtitle: Text(_sairDomingoAte == null
                  ? 'Desligado — no domingo fica nas promoções'
                  : 'Até ${DateFormat('dd/MM/yyyy').format(_sairDomingoAte!)} (depois disso, só no feriado)'),
              trailing: Wrap(
                children: [
                  if (_sairDomingoAte != null)
                    IconButton(
                      tooltip: 'Desligar',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _sairDomingoAte = null;
                        _alterado = true;
                      }),
                    ),
                  IconButton(
                    tooltip: 'Escolher até quando',
                    icon: const Icon(Icons.event),
                    onPressed: () async {
                      final hoje = DateTime.now();
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _sairDomingoAte != null && _sairDomingoAte!.isAfter(hoje)
                            ? _sairDomingoAte!
                            : hoje.add(const Duration(days: 7)),
                        firstDate: hoje,
                        lastDate: hoje.add(const Duration(days: 365)),
                      );
                      if (d != null) {
                        setState(() {
                          _sairDomingoAte = d;
                          _alterado = true;
                        });
                      }
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_alterado)
                  TextButton(
                    onPressed: _salvando ? null : () => setState(() => _preencher(Map<String, dynamic>.from((_painel['portal_config'] as Map?) ?? {}))),
                    child: const Text('Desfazer'),
                  ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _salvando || !_alterado ? null : () => _salvarPortal(),
                  icon: _salvando
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save_outlined),
                  label: const Text('Salvar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardSeparador() {
    final cs = Theme.of(context).colorScheme;
    final sep = _painel['separador'] as Map?;
    final ate = _dataHora(sep?['valida_ate']);
    final conectado = ate != null && ate.isAfter(DateTime.now());
    final msgs = _painel['mensagens_7d'] as Map?;
    final enviadas = (msgs?['enviadas'] as num?)?.toInt() ?? 0;
    final responderam = (msgs?['responderam'] as num?)?.toInt() ?? 0;
    final erro = sep?['ultimo_erro']?.toString();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _enviarMensagens == true,
              onChanged: sep == null || _mudandoMensagens ? null : _definirMensagens,
              title: const Text('Robô do Separador (chat do pedido)', style: TextStyle(fontWeight: FontWeight.w600)),
              subtitle: const Text('Quando o pedido é confirmado, pede o WhatsApp do cliente no chat do iFood. '
                  'Mensagens do cliente no chat viram aviso aqui no Gestor.'),
            ),
            Row(
              children: [
                Icon(conectado ? Icons.check_circle : Icons.error, size: 18, color: conectado ? Colors.green : cs.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    sep == null
                        ? 'Nunca conectado.'
                        : conectado
                            ? 'Conectado — renova sozinho (válido até ${_data.format(ate)})'
                            : 'Desconectado — precisa conectar de novo pelo favorito "Conectar iFood".',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            if (erro != null && erro.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Último erro: $erro', style: TextStyle(fontSize: 12, color: cs.error)),
            ],
            const SizedBox(height: 8),
            Text(
              'Últimos 7 dias: $enviadas ${enviadas == 1 ? 'pedido recebeu' : 'pedidos receberam'} a mensagem, '
              '$responderam ${responderam == 1 ? 'mandou' : 'mandaram'} o WhatsApp'
              '${enviadas > 0 ? ' (${(responderam * 100 / enviadas).round()}%)' : ''}.',
              style: TextStyle(fontSize: 13, color: cs.onSurface),
            ),
            const SizedBox(height: 4),
            Text('O robô do Portal usa a mesma conexão: desligar as mensagens não desliga a conexão.',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  String _descreverTarefa(Map t) {
    final p = Map<String, dynamic>.from((t['parametros'] as Map?) ?? {});
    switch (t['acao']) {
      case 'pedido_minimo':
        final v = (p['valor'] as num?)?.toDouble();
        return 'Pedido mínimo → R\$ ${v == null ? '?' : v.toStringAsFixed(2).replaceAll('.', ',')}';
      case 'usar_preconfig':
        return 'Usar pré-configuração "${p['nome'] ?? '?'}"';
      case 'promocao':
        return '${p['modo'] == 'sair' ? 'Sair da' : 'Voltar pra'} promoção "${p['nome'] ?? '?'}"';
      default:
        return t['acao']?.toString() ?? '?';
    }
  }

  Widget _cardTarefas(String titulo, List tarefas, {required String vazio}) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(titulo, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            if (tarefas.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(vazio, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              ),
            for (final raw in tarefas)
              Builder(builder: (_) {
                final t = Map<String, dynamic>.from(raw as Map);
                final quando = _dataHora(t['executar_em']);
                final status = t['status']?.toString() ?? '';
                final (icone, cor) = switch (status) {
                  'ok' => (Icons.check_circle_outline, Colors.green),
                  'erro' => (Icons.error_outline, cs.error),
                  'cancelada' => (Icons.block, cs.onSurfaceVariant),
                  'executando' => (Icons.sync, cs.primary),
                  _ => (Icons.schedule, cs.onSurfaceVariant),
                };
                final erro = t['erro']?.toString();
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(icone, color: cor, size: 20),
                  title: Text(_descreverTarefa(t)),
                  subtitle: Text([
                    if (quando != null) _data.format(quando),
                    if ((t['motivo'] ?? '').toString().isNotEmpty) t['motivo'].toString(),
                    if (status == 'erro' && erro != null) erro,
                    if (status == 'cancelada' && erro != null) 'cancelada: $erro',
                  ].join(' · ')),
                );
              }),
          ],
        ),
      ),
    );
  }
}
