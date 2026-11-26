import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/rota_oferta_fila.dart';
import 'entrega_oferta_acerto_screen.dart';
import 'entrega_oferta_resumo_screen.dart';

/// Rotas do entregador por oferta (25/11, visão do lojista): todas as rotas abertas num lugar só e o
/// controle da loja — entregar ao motoboy, aumentar o valor e oferecer de novo, trocar o motoboy,
/// cancelar (a loja entrega), tirar pedido, "eu entrego", oferecer mesmo assim, juntar pedido numa
/// rota, reentregar o que voltou e pausar as ofertas. Tudo por RPC (entrega_oferta_*), só equipe da loja.
class EntregaOfertaRotasScreen extends StatefulWidget {
  const EntregaOfertaRotasScreen({super.key});

  @override
  State<EntregaOfertaRotasScreen> createState() => _EntregaOfertaRotasScreenState();
}

class _PedidoRota {
  final String id;
  final String numero;
  final String cliente;
  final String bairro;
  final String status;
  final String? foto;
  final bool contestado;
  final bool devolucaoConfirmada;
  _PedidoRota(this.id, this.numero, this.cliente, this.bairro, this.status,
      {this.foto, this.contestado = false, this.devolucaoConfirmada = false});

  /// [p] = pedido; [rp] = linha de rota_pedidos (prova, reclamação, devolução), quando houver
  factory _PedidoRota.de(Map<String, dynamic> p, [Map<String, dynamic>? rp]) {
    final c = p['cliente'] as Map<String, dynamic>?;
    return _PedidoRota(
      p['id'] as String,
      '${p['numero_sequencial'] ?? '?'}',
      ((c?['nome'] as String?) ?? 'Cliente').split(' ').first,
      (c?['bairro'] as String?) ?? '',
      p['status'] as String? ?? '',
      foto: rp?['foto_path'] as String?,
      contestado: rp?['contestado_em'] != null && rp?['contestacao_resolvida_em'] == null,
      devolucaoConfirmada: rp?['devolucao_confirmada_em'] != null,
    );
  }
}

class _Rota {
  final String id;
  final String status;
  final String? motoboy;
  final double? valor;
  final double bonus;
  final DateTime? prazoSaida;
  final bool chegou;
  final double? km;
  final List<_PedidoRota> pedidos;
  final bool calculando;
  final String? erroRota;
  /// GPS do motoboy durante a rota (Kitsune manda a cada 30 s com o app aberto)
  final double? posLat;
  final double? posLon;
  final DateTime? posEm;
  /// Kitsune avisou que o GPS falhou (negado/bloqueado/desligado/semSinal)
  final String? gpsFalha;
  _Rota(this.id, this.status, this.motoboy, this.valor, this.bonus, this.prazoSaida, this.chegou, this.km, this.pedidos,
      {this.calculando = false, this.erroRota, this.posLat, this.posLon, this.posEm, this.gpsFalha});
}

class _EntregaOfertaRotasScreenState extends State<EntregaOfertaRotasScreen> {
  final _db = Supabase.instance.client;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  List<_Rota> _rotas = [];
  List<(_PedidoRota, String)> _fora = []; // pedido + motivo
  List<_PedidoRota> _naoEntregues = [];
  List<_PedidoRota> _reclamacoes = [];
  bool _ligado = false;
  DateTime? _pausadoAte;
  bool _carregando = true;
  String? _ocupado;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _carregar();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _carregar());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final cfg = await _db.from('entrega_oferta_config').select('ativo, pausado_ate').maybeSingle();
      final rotas = await _db
          .from('rotas_entrega')
          .select('id, status, valor_entregador, bonus, prazo_saida, chegou_loja_em, km_ida, google_ok, google_erro, ofertada_em, '
              'pos_lat, pos_lon, pos_em, gps_falha, '
              'entregador:entregadores(nome), rota_pedidos(ordem, foto_path, contestado_em, contestacao_resolvida_em, devolucao_confirmada_em, '
              'pedido:pedidos(id, numero_sequencial, status, cliente:clientes(nome, bairro)))')
          .eq('origem', 'oferta')
          .inFilter('status', ['ofertada', 'aceita', 'em_andamento', 'sem_entregador'])
          .order('created_at');
      final desde = DateTime.now().subtract(const Duration(hours: 12)).toUtc().toIso8601String();
      final fora = await _db
          .from('entrega_oferta_pedidos_fora')
          .select('motivo, pedido:pedidos!inner(id, numero_sequencial, status, cliente:clientes(nome, bairro))')
          .gte('created_at', desde)
          .inFilter('pedido.status', ['pendente', 'preparando', 'pronto']);
      // voltaram (não entregues) e reclamações do cliente das rotas de oferta
      final voltou = await _db
          .from('rota_pedidos')
          .select('foto_path, contestado_em, contestacao_resolvida_em, devolucao_confirmada_em, '
              'pedido:pedidos!inner(id, numero_sequencial, status, updated_at, cliente:clientes(nome, bairro))')
          .eq('pedido.status', 'nao_entregue')
          .gte('pedido.updated_at', DateTime.now().subtract(const Duration(days: 3)).toUtc().toIso8601String());
      final reclamou = await _db
          .from('rota_pedidos')
          .select('foto_path, contestado_em, contestacao_resolvida_em, devolucao_confirmada_em, '
              'pedido:pedidos(id, numero_sequencial, status, cliente:clientes(nome, bairro))')
          .not('contestado_em', 'is', null)
          .isFilter('contestacao_resolvida_em', null);
      if (!mounted) return;
      setState(() {
        _ligado = cfg?['ativo'] as bool? ?? false;
        _pausadoAte = cfg?['pausado_ate'] == null ? null : DateTime.tryParse(cfg!['pausado_ate'] as String)?.toLocal();
        _rotas = [
          for (final r in rotas as List)
            _Rota(
              r['id'] as String,
              r['status'] as String,
              ((r['entregador'] as Map?)?['nome'] as String?)?.split(' ').first,
              (r['valor_entregador'] as num?)?.toDouble(),
              (r['bonus'] as num?)?.toDouble() ?? 0,
              r['prazo_saida'] == null ? null : DateTime.tryParse(r['prazo_saida'] as String)?.toLocal(),
              r['chegou_loja_em'] != null,
              (r['km_ida'] as num?)?.toDouble(),
              ([...(r['rota_pedidos'] as List)]..sort((a, b) => ((a['ordem'] as num?) ?? 0).compareTo((b['ordem'] as num?) ?? 0)))
                  .map((rp) => _PedidoRota.de(rp['pedido'] as Map<String, dynamic>, rp as Map<String, dynamic>))
                  .toList(),
              calculando: r['status'] == 'ofertada' && r['google_ok'] != true && r['ofertada_em'] == null && r['google_erro'] == null,
              erroRota: r['google_erro'] as String?,
              posLat: (r['pos_lat'] as num?)?.toDouble(),
              posLon: (r['pos_lon'] as num?)?.toDouble(),
              posEm: r['pos_em'] == null ? null : DateTime.tryParse(r['pos_em'] as String)?.toLocal(),
              gpsFalha: r['gps_falha'] as String?,
            ),
        ];
        _fora = [
          for (final f in fora as List) (_PedidoRota.de(f['pedido'] as Map<String, dynamic>), f['motivo'] as String? ?? ''),
        ];
        _naoEntregues = [
          for (final rp in voltou as List) _PedidoRota.de(rp['pedido'] as Map<String, dynamic>, rp as Map<String, dynamic>),
        ];
        _reclamacoes = [
          for (final rp in reclamou as List) _PedidoRota.de(rp['pedido'] as Map<String, dynamic>, rp as Map<String, dynamic>),
        ];
        _carregando = false;
      });
    } catch (e) {
      debugPrint('Erro ao carregar rotas: $e');
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _rpc(String chave, String fn, Map<String, dynamic> params, {String? ok}) async {
    final mensageiro = ScaffoldMessenger.of(context);
    setState(() => _ocupado = chave);
    try {
      final r = await _db.rpc(fn, params: params);
      final m = r is Map ? r : const {};
      mensageiro.showSnackBar(SnackBar(
          content: Text(m['ok'] == false ? (m['mensagem']?.toString() ?? 'Não deu.') : (ok ?? 'Feito.'))));
    } catch (e) {
      mensageiro.showSnackBar(SnackBar(content: Text('Não deu: $e')));
    }
    if (mounted) setState(() => _ocupado = null);
    await _carregar();
    unawaited(RotasOfertaFila.instancia.atualizar());
  }

  /// Foto de prova (bucket privado: link assinado de 5 min)
  Future<void> _verFoto(String path, String titulo) async {
    try {
      final url = await _db.storage.from('entregas-provas').createSignedUrl(path, 300);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(title: Text(titulo), trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx))),
              Flexible(child: InteractiveViewer(child: Image.network(url, fit: BoxFit.contain))),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não deu pra abrir a foto: $e')));
    }
  }

  Future<bool> _confirmar(String titulo, String texto, String botao) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(titulo),
          content: Text(texto),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(botao)),
          ],
        ),
      ) ==
      true;

  String _haQuanto(DateTime t) {
    final m = DateTime.now().difference(t).inMinutes;
    if (m < 1) return 'agora';
    if (m < 60) return 'há $m min';
    return 'às ${DateFormat('HH:mm').format(t)}';
  }

  String _rotuloStatus(_Rota r) => switch (r.status) {
        'ofertada' when r.erroRota != null => 'Não consegui calcular a rota: confira o endereço',
        'ofertada' when r.calculando => 'Calculando a rota exata…',
        'ofertada' => 'Esperando um motoboy aceitar',
        'aceita' => '${r.motoboy ?? 'Motoboy'} ${r.chegou ? 'chegou na loja' : 'está vindo'}',
        'em_andamento' => '${r.motoboy ?? 'Motoboy'} em rota',
        'sem_entregador' => 'Ninguém aceitou: a loja entrega',
        _ => r.status,
      };

  Color _corStatus(_Rota r) => switch (r.status) {
        'ofertada' => Colors.blueGrey,
        'aceita' => r.chegou ? Colors.green.shade700 : Colors.orange.shade800,
        'em_andamento' => Colors.blue.shade700,
        'sem_entregador' => Colors.red.shade700,
        _ => Colors.grey,
      };

  String _motivoFora(String m) => switch (m) {
        'nao_paga_entrega' => 'Não paga a entrega com motoboy',
        'loja_entrega' => 'A loja vai entregar',
        'loja_tirou' => 'Tirado da rota pela loja',
        _ => 'Fora das ofertas',
      };

  Future<void> _escolherBonus(_Rota r) async {
    final valor = await showModalBottomSheet<double>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Aumentar o valor da rota', style: TextStyle(fontWeight: FontWeight.w700))),
            for (final v in [2.0, 4.0, 6.0])
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: Text('+ ${_moeda.format(v)}'),
                subtitle: r.valor == null ? null : Text('Fica ${_moeda.format(r.valor! + v)}'),
                onTap: () => Navigator.pop(ctx, v),
              ),
          ],
        ),
      ),
    );
    if (valor == null) return;
    await _rpc('bonus${r.id}', 'entrega_oferta_bonus', {'p_rota_id': r.id, 'p_valor': valor},
        ok: r.status == 'aceita' ? 'Valor aumentado. O motoboy foi avisado.' : 'Valor aumentado e rota oferecida de novo.');
  }

  Future<void> _juntar(_PedidoRota p) async {
    final abertas = _rotas.where((r) => r.status == 'ofertada' || r.status == 'aceita').toList();
    if (abertas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhuma rota aberta pra juntar.')));
      return;
    }
    final rota = await showModalBottomSheet<_Rota>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(title: Text('Juntar o pedido #${p.numero} em qual rota?', style: const TextStyle(fontWeight: FontWeight.w700))),
            for (final r in abertas)
              ListTile(
                leading: const Icon(Icons.two_wheeler),
                title: Text(_rotuloStatus(r)),
                subtitle: Text(r.pedidos.map((x) => '#${x.numero} ${x.bairro}').join(' · ')),
                onTap: () => Navigator.pop(ctx, r),
              ),
          ],
        ),
      ),
    );
    if (rota == null) return;
    await _rpc('juntar${p.id}', 'entrega_oferta_juntar', {'p_pedido_id': p.id, 'p_rota_id': rota.id},
        ok: 'Pedido #${p.numero} entrou na rota.');
  }

  Widget _cartaoRota(_Rota r) {
    final cor = _corStatus(r);
    final hora = r.prazoSaida == null ? null : DateFormat('HH:mm').format(r.prazoSaida!);
    final antesDeSair = r.status == 'ofertada' || r.status == 'aceita';
    final entregues = r.pedidos.where((p) => p.status == 'entregue' || p.status == 'concluido').length;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: cor.withValues(alpha: 0.5))),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.two_wheeler, color: cor),
                const SizedBox(width: 8),
                Expanded(child: Text(_rotuloStatus(r), style: TextStyle(fontWeight: FontWeight.w700, color: cor))),
                if (r.valor != null)
                  Text(_moeda.format(r.valor), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                '${r.pedidos.length} entrega${r.pedidos.length == 1 ? '' : 's'}',
                if (r.km != null) '${r.km!.toStringAsFixed(1).replaceAll('.', ',')} km',
                if (hora != null && antesDeSair) 'sair até $hora',
                if (r.status == 'em_andamento') '$entregues de ${r.pedidos.length} entregues',
                if (r.bonus > 0) 'bônus ${_moeda.format(r.bonus)}',
              ].join(' · '),
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            if ((r.status == 'aceita' || r.status == 'em_andamento') && r.gpsFalha != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.location_disabled, size: 18, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    switch (r.gpsFalha) {
                      'negado' || 'bloqueado' => 'GPS do motoboy bloqueado no celular dele (o Kitsune mostra como liberar)',
                      'desligado' => 'Localização do celular do motoboy está desligada',
                      _ => 'GPS do motoboy sem sinal agora',
                    },
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ]),
            ],
            if ((r.status == 'aceita' || r.status == 'em_andamento') && r.posLat != null) ...[
              const SizedBox(height: 8),
              Row(children: [
                Icon(Icons.my_location, size: 18,
                    color: DateTime.now().difference(r.posEm!).inMinutes < 3 ? Colors.green.shade700 : Colors.orange.shade800),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'GPS: visto ${_haQuanto(r.posEm!)}',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => launchUrl(
                      Uri.parse('https://www.google.com/maps/search/?api=1&query=${r.posLat},${r.posLon}'),
                      mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.map_outlined, size: 18),
                  label: const Text('Ver no mapa'),
                ),
              ]),
            ],
            const Divider(height: 20),
            for (final p in r.pedidos)
              Row(
                children: [
                  Expanded(
                    child: Text('#${p.numero} · ${p.cliente}${p.bairro.isEmpty ? '' : ' · ${p.bairro}'}',
                        style: TextStyle(
                            decoration: p.status == 'cancelado' ? TextDecoration.lineThrough : null,
                            color: p.status == 'entregue' ? Colors.green.shade700 : null)),
                  ),
                  if (p.contestado) Icon(Icons.report_problem, size: 18, color: Colors.orange.shade800),
                  if (p.foto != null)
                    IconButton(
                      tooltip: 'Ver foto da entrega',
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.photo_camera_outlined, size: 18),
                      onPressed: () => _verFoto(p.foto!, 'Pedido #${p.numero}'),
                    ),
                  if (p.status == 'entregue') const Icon(Icons.check_circle, size: 18, color: Colors.green),
                  if (p.status == 'nao_entregue') Icon(Icons.undo, size: 18, color: Colors.red.shade700),
                  if (antesDeSair)
                    PopupMenuButton<String>(
                      tooltip: 'Ações do pedido',
                      onSelected: (acao) async {
                        if (acao == 'tirar') {
                          await _rpc('p${p.id}', 'entrega_oferta_tirar_pedido', {'p_pedido_id': p.id},
                              ok: 'Pedido #${p.numero} saiu da rota.');
                        } else {
                          await _rpc('p${p.id}', 'entrega_oferta_eu_entrego', {'p_pedido_id': p.id},
                              ok: 'Pedido #${p.numero}: a loja entrega.');
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'tirar', child: Text('Tirar da rota (volta pra oferta)')),
                        PopupMenuItem(value: 'eu', child: Text('Eu entrego este')),
                      ],
                    ),
                ],
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (r.status == 'aceita')
                  BotaoEntregarMotoboy(
                    info: RotaOfertaInfo(rotaId: r.id, status: r.status, entregador: r.motoboy, n: r.pedidos.length),
                  ),
                if (r.status != 'em_andamento')
                  OutlinedButton.icon(
                    onPressed: _ocupado == null ? () => _escolherBonus(r) : null,
                    icon: const Icon(Icons.trending_up, size: 18),
                    label: Text(r.status == 'aceita' ? 'Aumentar valor' : 'Aumentar valor e oferecer'),
                  ),
                if (r.status == 'aceita')
                  OutlinedButton.icon(
                    onPressed: _ocupado == null
                        ? () async {
                            if (await _confirmar('Trocar motoboy',
                                '${r.motoboy ?? 'O motoboy'} sai da rota e ela é oferecida pros outros.', 'Trocar')) {
                              await _rpc('troca${r.id}', 'entrega_oferta_trocar_motoboy', {'p_rota_id': r.id},
                                  ok: 'Rota oferecida pros outros motoboys.');
                            }
                          }
                        : null,
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: const Text('Trocar motoboy'),
                  ),
                if (r.status != 'em_andamento')
                  TextButton.icon(
                    onPressed: _ocupado == null
                        ? () async {
                            if (await _confirmar('Cancelar a rota',
                                'A loja entrega estes pedidos. ${r.status == 'aceita' ? 'O motoboy é avisado.' : ''}', 'Cancelar rota')) {
                              await _rpc('canc${r.id}', 'entrega_oferta_cancelar_rota', {'p_rota_id': r.id},
                                  ok: 'Rota cancelada: a loja entrega.');
                            }
                          }
                        : null,
                    icon: Icon(Icons.close, size: 18, color: Colors.red.shade700),
                    label: Text('Cancelar (eu entrego)', style: TextStyle(color: Colors.red.shade700)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pausar() async {
    if (_pausadoAte != null && _pausadoAte!.isAfter(DateTime.now())) {
      await _rpc('pausa', 'entrega_oferta_pausar', {'p_ate': null}, ok: 'Ofertas retomadas.');
      return;
    }
    final ate = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (ctx) {
        final agora = DateTime.now();
        final amanha = DateTime(agora.year, agora.month, agora.day + 1, 6);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('Pausar ofertas novas', style: TextStyle(fontWeight: FontWeight.w700))),
              ListTile(title: const Text('Por 30 minutos'), onTap: () => Navigator.pop(ctx, agora.add(const Duration(minutes: 30)))),
              ListTile(title: const Text('Por 1 hora'), onTap: () => Navigator.pop(ctx, agora.add(const Duration(hours: 1)))),
              ListTile(title: const Text('Por 2 horas'), onTap: () => Navigator.pop(ctx, agora.add(const Duration(hours: 2)))),
              ListTile(title: const Text('Até amanhã'), onTap: () => Navigator.pop(ctx, amanha)),
            ],
          ),
        );
      },
    );
    if (ate == null) return;
    await _rpc('pausa', 'entrega_oferta_pausar', {'p_ate': ate.toUtc().toIso8601String()},
        ok: 'Ofertas pausadas até ${DateFormat('dd/MM HH:mm').format(ate)}. As rotas abertas continuam.');
  }

  @override
  Widget build(BuildContext context) {
    final pausado = _pausadoAte != null && _pausadoAte!.isAfter(DateTime.now());
    final cores = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rotas de motoboy'),
        actions: [
          IconButton(
            tooltip: 'Resumo',
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EntregaOfertaResumoScreen())),
          ),
          IconButton(
            tooltip: 'Acerto com motoboys',
            icon: const Icon(Icons.payments_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EntregaOfertaAcertoScreen())),
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    color: !_ligado
                        ? cores.surfaceContainerHighest
                        : pausado
                            ? Colors.orange.shade50
                            : Colors.green.shade50,
                    child: ListTile(
                      leading: Icon(!_ligado ? Icons.power_settings_new : (pausado ? Icons.pause_circle : Icons.play_circle),
                          color: !_ligado ? null : (pausado ? Colors.orange.shade800 : Colors.green.shade700)),
                      title: Text(!_ligado
                          ? 'Ofertas desligadas'
                          : pausado
                              ? 'Ofertas pausadas até ${DateFormat('dd/MM HH:mm').format(_pausadoAte!)}'
                              : 'Ofertas ligadas'),
                      subtitle: Text(!_ligado ? 'Ligue em Opções de Entrega › Entregador por oferta' : 'Pedido novo vira oferta pros motoboys'),
                      trailing: !_ligado
                          ? null
                          : TextButton(onPressed: _ocupado == null ? _pausar : null, child: Text(pausado ? 'Retomar' : 'Pausar')),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_rotas.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('Nenhuma rota aberta agora.')),
                    ),
                  for (final r in _rotas) _cartaoRota(r),
                  if (_reclamacoes.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Cliente reclamou da entrega', style: Theme.of(context).textTheme.titleMedium),
                    for (final p in _reclamacoes)
                      Card(
                        child: ListTile(
                          leading: Icon(Icons.report_problem, color: Colors.orange.shade800),
                          title: Text('#${p.numero} · ${p.cliente}'),
                          subtitle: const Text('Respondeu "Tive um problema". O acerto dessa rota espera você resolver.'),
                          trailing: Wrap(spacing: 4, children: [
                            if (p.foto != null)
                              IconButton(
                                  icon: const Icon(Icons.photo_camera_outlined),
                                  onPressed: () => _verFoto(p.foto!, 'Entrega · pedido #${p.numero}')),
                            TextButton(
                              onPressed: _ocupado == null
                                  ? () => _rpc('rec${p.id}', 'entrega_oferta_resolver_reclamacao', {'p_pedido_id': p.id},
                                      ok: 'Reclamação marcada como resolvida.')
                                  : null,
                              child: const Text('Resolvido'),
                            ),
                          ]),
                        ),
                      ),
                  ],
                  if (_naoEntregues.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Voltaram (não entregues)', style: Theme.of(context).textTheme.titleMedium),
                    for (final p in _naoEntregues)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Icon(Icons.undo, color: Colors.red.shade700),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Text('#${p.numero} · ${p.cliente}${p.bairro.isEmpty ? '' : ' · ${p.bairro}'}',
                                        style: const TextStyle(fontWeight: FontWeight.w600))),
                              ]),
                              Text(
                                p.devolucaoConfirmada
                                    ? 'Pedido de volta na loja. Reentregue ou, se o cliente desistiu, cancele no detalhe do pedido.'
                                    : 'Confirme quando o motoboy trouxer o pedido de volta (o acerto dele espera isso).',
                                style: TextStyle(color: cores.onSurfaceVariant),
                              ),
                              Wrap(spacing: 4, children: [
                                if (p.foto != null)
                                  TextButton.icon(
                                    onPressed: () => _verFoto(p.foto!, 'Fachada · pedido #${p.numero}'),
                                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                                    label: const Text('Ver foto'),
                                  ),
                                if (!p.devolucaoConfirmada)
                                  FilledButton.tonal(
                                    onPressed: _ocupado == null
                                        ? () => _rpc('dev${p.id}', 'entrega_oferta_confirmar_devolucao', {'p_pedido_id': p.id},
                                            ok: 'Devolução do pedido #${p.numero} confirmada.')
                                        : null,
                                    child: const Text('Recebi de volta'),
                                  ),
                                TextButton(
                                  onPressed: _ocupado == null
                                      ? () => _rpc('re${p.id}', 'entrega_oferta_reentregar', {'p_pedido_id': p.id},
                                          ok: 'Pedido #${p.numero} voltou pra fila e pra oferta.')
                                      : null,
                                  child: const Text('Reentregar'),
                                ),
                              ]),
                            ],
                          ),
                        ),
                      ),
                  ],
                  if (_fora.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text('Fora das ofertas', style: Theme.of(context).textTheme.titleMedium),
                    for (final (p, motivo) in _fora)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('#${p.numero} · ${p.cliente}${p.bairro.isEmpty ? '' : ' · ${p.bairro}'}',
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text(_motivoFora(motivo), style: TextStyle(color: cores.onSurfaceVariant)),
                              Wrap(
                                spacing: 4,
                                children: [
                                  TextButton(
                                    onPressed: _ocupado == null
                                        ? () => _rpc('f${p.id}', 'entrega_oferta_forcar', {'p_pedido_id': p.id},
                                            ok: 'Pedido #${p.numero} vai pra oferta.')
                                        : null,
                                    child: const Text('Oferecer mesmo assim'),
                                  ),
                                  TextButton(
                                    onPressed: _ocupado == null ? () => _juntar(p) : null,
                                    child: const Text('Juntar numa rota'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
    );
  }
}
