import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as osm;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/rota_oferta_fila.dart';
import 'entrega_oferta_acerto_screen.dart';
import 'entrega_oferta_config_screen.dart';
import 'entrega_oferta_resumo_screen.dart';
import 'rotas_entrega_screen.dart';
import 'trajeto_rota_screen.dart';

/// Painel de Entregas (26/11, desenho aprovado https://claude.ai/artifact/WTXKPmYdWim27QCo4zpbeb):
/// junta as antigas "Rotas de Entrega" e "Rotas de motoboy". Cabeçalho (ofertas, chuva, rota da loja),
/// faixa da chuva, resumo do dia, mapa (loja, motoboys pelo GPS, paradas), "Precisa de você",
/// rotas (abertas / concluídas, com a lista de entregas), "Juntando pedidos" e o acerto do dia.
///
/// Ações por RPC (entrega_oferta_*), só equipe da loja. [demo] = dados de exemplo da bancada
/// (test_manual/main_painel_entregas.dart): mesmo formato das linhas do banco, sem rede.
class PainelEntregasScreen extends StatefulWidget {
  final Map<String, dynamic>? demo;
  const PainelEntregasScreen({super.key, this.demo});

  @override
  State<PainelEntregasScreen> createState() => _PainelEntregasScreenState();
}

// ── Cores fixas de situação (iguais em qualquer loja; a marca vem do tema) ─────────────────────────
class _Tom {
  final Color texto;
  final Color fundo;
  const _Tom(this.texto, this.fundo);
}

const _tomEmRota = _Tom(Color(0xFF1E3A8A), Color(0xFFDBEAFE));
const _tomLoja = _Tom(Color(0xFF166534), Color(0xFFDCFCE7));
const _tomEspera = _Tom(Color(0xFF92400E), Color(0xFFFEF3C7));
const _tomProblema = _Tom(Color(0xFF991B1B), Color(0xFFFEE2E2));
const _tomNeutro = _Tom(Color(0xFF3F3F46), Color(0xFFE4E4E7));

class _PedidoRota {
  final String id;
  final String numero;
  final String cliente;
  final String bairro;
  final String status;
  final String? foto;
  final bool contestado;
  final bool devolucaoConfirmada;
  final double? lat;
  final double? lon;
  /// fim da janela prometida ao cliente (pedido ou iFood)
  final DateTime? prometidoAte;
  /// motoboy pediu pra devolver (não entregou) e espera a loja autorizar
  final bool devolucaoPedida;
  final String? motivoDevolucao;
  _PedidoRota(this.id, this.numero, this.cliente, this.bairro, this.status,
      {this.foto, this.contestado = false, this.devolucaoConfirmada = false, this.lat, this.lon, this.prometidoAte, this.devolucaoPedida = false, this.motivoDevolucao});

  bool get entregue => status == 'entregue' || status == 'concluido';
  bool get resolvido => entregue || status == 'cancelado' || status == 'nao_entregue';

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
      lat: (c?['latitude'] as num?)?.toDouble(),
      lon: (c?['longitude'] as num?)?.toDouble(),
      devolucaoPedida: rp?['devolucao_pedida_em'] != null && p['status'] != 'nao_entregue',
      motivoDevolucao: rp?['devolucao_motivo'] as String?,
      prometidoAte: _Rota._dt(p['previsao_entrega_fim']) ??
          _Rota._dt(((p['mp'] is List && (p['mp'] as List).isNotEmpty) ? (p['mp'] as List).first : p['mp'] as Map?)?['entrega_prevista_fim']),
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
  final double? posLat;
  final double? posLon;
  final DateTime? posEm;
  final String? gpsFalha;
  final bool ofertaSaiu;
  final DateTime? ofertadaEm;
  final DateTime? saiuEm;
  final DateTime? finalizadaEm;
  final double troco;
  final String? telefoneMotoboy;
  /// rota montada à mão (a loja entrega), não é do entregador por oferta
  final bool daLoja;
  _Rota(this.id, this.status, this.motoboy, this.valor, this.bonus, this.prazoSaida, this.chegou, this.km, this.pedidos,
      {this.calculando = false,
      this.erroRota,
      this.posLat,
      this.posLon,
      this.posEm,
      this.gpsFalha,
      this.ofertaSaiu = true,
      this.ofertadaEm,
      this.saiuEm,
      this.finalizadaEm,
      this.troco = 0,
      this.telefoneMotoboy,
      this.daLoja = false});

  String get bairros {
    final bs = <String>[];
    for (final p in pedidos) {
      if (p.bairro.isNotEmpty && !bs.contains(p.bairro)) bs.add(p.bairro);
    }
    return bs.isEmpty ? 'região da loja' : bs.join(', ');
  }

  int get entregues => pedidos.where((p) => p.entregue).length;

  static DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v as String)?.toLocal();

  factory _Rota.de(Map<String, dynamic> r) => _Rota(
        r['id'] as String,
        r['status'] as String,
        ((r['entregador'] as Map?)?['nome'] as String?)?.split(' ').first,
        (r['valor_entregador'] as num?)?.toDouble(),
        (r['bonus'] as num?)?.toDouble() ?? 0,
        _dt(r['prazo_saida']),
        r['chegou_loja_em'] != null,
        (r['km_ida'] as num?)?.toDouble(),
        ([...(r['rota_pedidos'] as List? ?? const [])]
              ..sort((a, b) => ((a['ordem'] as num?) ?? 0).compareTo((b['ordem'] as num?) ?? 0)))
            .map((rp) => _PedidoRota.de(rp['pedido'] as Map<String, dynamic>, rp as Map<String, dynamic>))
            .toList(),
        calculando: r['status'] == 'ofertada' && r['google_ok'] != true && r['ofertada_em'] == null && r['google_erro'] == null,
        erroRota: r['google_erro'] as String?,
        posLat: (r['pos_lat'] as num?)?.toDouble(),
        posLon: (r['pos_lon'] as num?)?.toDouble(),
        posEm: _dt(r['pos_em']),
        gpsFalha: (r['gps_falha'] as String?)?.split(':').first, // "estado:código:mensagem" → estado
        ofertaSaiu: r['ofertada_em'] != null,
        ofertadaEm: _dt(r['ofertada_em']),
        saiuEm: _dt(r['saiu_em']),
        finalizadaEm: _dt(r['finalizada_em']),
        troco: (r['troco'] as num?)?.toDouble() ?? 0,
        telefoneMotoboy: (r['entregador'] as Map?)?['telefone'] as String?,
        daLoja: r['origem'] == 'manual',
      );
}

/// Rota montada à mão (a loja entrega) — aparece no painel e no mapa, gestão na tela "Rota da loja".
class _RotaLoja {
  final String id;
  final String status;
  final String? entregador;
  final List<({bool entregue, double? lat, double? lon})> paradas;
  _RotaLoja(this.id, this.status, this.entregador, this.paradas);
  factory _RotaLoja.de(Map<String, dynamic> r) => _RotaLoja(
        r['id'] as String,
        r['status'] as String? ?? '',
        ((r['entregador'] as Map?)?['nome'] as String?)?.split(' ').first,
        [
          for (final rp in (r['rota_pedidos'] as List? ?? const []))
            (
              entregue: ['entregue', 'concluido'].contains((rp['pedido'] as Map?)?['status']),
              lat: (((rp['pedido'] as Map?)?['cliente'] as Map?)?['latitude'] as num?)?.toDouble(),
              lon: (((rp['pedido'] as Map?)?['cliente'] as Map?)?['longitude'] as num?)?.toDouble(),
            ),
        ],
      );
}

class _Acerto {
  final String nome;
  int rotas = 0;
  int entregas = 0;
  double ganhou = 0;
  double dinheiro = 0;
  _Acerto(this.nome);
  double get saldo => ganhou - dinheiro; // >0 a loja paga; <0 ele devolve
}

class _PainelEntregasScreenState extends State<PainelEntregasScreen> {
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
  List<_Rota> _rotas = [];
  List<_Rota> _concluidas = [];
  List<(_PedidoRota, String)> _fora = []; // pedido + motivo
  List<_PedidoRota> _naoEntregues = [];
  List<_PedidoRota> _reclamacoes = [];
  List<_Acerto> _acertos = [];
  List<_RotaLoja> _rotasLoja = [];
  List<({String id, String nome, bool disponivel, double? lat, double? lon, DateTime? em})> _motoboys = [];
  bool _ligado = false;
  DateTime? _pausadoAte;
  double _chuvaValor = 0;
  DateTime? _chuvaAte;
  Map<String, dynamic>? _resumo;
  ll.LatLng? _loja;
  bool _carregando = true;
  bool _verConcluidas = false;
  String? _ocupado;
  Timer? _timer;

  bool get _demo => widget.demo != null;
  SupabaseClient get _db => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    if (_demo) {
      _aplicar(widget.demo!);
      return;
    }
    _carregar();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _carregar());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ── Dados ────────────────────────────────────────────────────────────────────────────────────────
  static const _selRota = 'id, status, valor_entregador, bonus, prazo_saida, chegou_loja_em, km_ida, google_ok, google_erro, '
      'ofertada_em, saiu_em, finalizada_em, pos_lat, pos_lon, pos_em, gps_falha, origem, '
      'entregador:entregadores(nome, telefone), rota_pedidos(ordem, foto_path, contestado_em, contestacao_resolvida_em, devolucao_confirmada_em, devolucao_pedida_em, devolucao_motivo, '
      'pedido:pedidos(id, numero_sequencial, status, previsao_entrega_fim, mp:marketplace_pedidos(entrega_prevista_fim), '
      'cliente:clientes(nome, bairro, latitude, longitude)))';

  Future<void> _carregar() async {
    if (_demo) return;
    try {
      final cfg = await _db.from('entrega_oferta_config').select('ativo, pausado_ate, chuva_valor, chuva_ate, empresa_id').maybeSingle();
      Map<String, dynamic>? loja;
      if (_loja == null && cfg?['empresa_id'] != null) {
        loja = await _db.from('empresas').select('latitude, longitude').eq('id', cfg!['empresa_id'] as String).maybeSingle();
      }
      final hoje = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final desde12h = DateTime.now().subtract(const Duration(hours: 12)).toUtc().toIso8601String();
      final res = await Future.wait<dynamic>([
        _db.rpc('entrega_oferta_resumo', params: {'p_dias': 1}),
        _db
            .from('rotas_entrega')
            .select(_selRota)
            .eq('origem', 'oferta')
            .inFilter('status', ['ofertada', 'aceita', 'em_andamento', 'sem_entregador'])
            .order('created_at'),
        _db.from('rotas_entrega').select(_selRota).eq('origem', 'oferta').eq('status', 'concluida').eq('data_rota', hoje).order('finalizada_em'),
        _db
            .from('entrega_oferta_pedidos_fora')
            .select('motivo, lucro_estimado, custo_estimado, pedido:pedidos!inner(id, numero_sequencial, status, cliente:clientes(nome, bairro))')
            .gte('created_at', desde12h)
            .inFilter('pedido.status', ['pendente', 'preparando', 'pronto']),
        _db
            .from('rota_pedidos')
            .select('foto_path, contestado_em, contestacao_resolvida_em, devolucao_confirmada_em, '
                'pedido:pedidos!inner(id, numero_sequencial, status, updated_at, cliente:clientes(nome, bairro))')
            .eq('pedido.status', 'nao_entregue')
            .gte('pedido.updated_at', DateTime.now().subtract(const Duration(days: 3)).toUtc().toIso8601String()),
        _db
            .from('rota_pedidos')
            .select('foto_path, contestado_em, contestacao_resolvida_em, devolucao_confirmada_em, '
                'pedido:pedidos(id, numero_sequencial, status, cliente:clientes(nome, bairro))')
            .not('contestado_em', 'is', null)
            .isFilter('contestacao_resolvida_em', null),
        _db
            .from('rotas_entrega')
            .select('id, status, entregador:entregadores(nome), rota_pedidos(pedido:pedidos(status, cliente:clientes(latitude, longitude)))')
            .eq('origem', 'manual')
            .eq('data_rota', hoje)
            .neq('status', 'concluida'),
        _db.from('entregadores').select('id, nome, disponivel, pos_lat, pos_lon, pos_em').eq('freelancer_oferta', true).eq('ativo', true).isFilter('deleted_at', null).order('nome'),
        _db
            .from('rotas_entrega')
            .select('n_pedidos, valor_entregador, dinheiro_recebido, entregador:entregadores(nome)')
            .eq('origem', 'oferta')
            .eq('status', 'concluida')
            .isFilter('acertado_em', null)
            .not('entregador_id', 'is', null),
      ]);
      if (!mounted) return;
      _aplicar({
        'cfg': cfg,
        'loja': loja,
        'resumo': res[0],
        'rotas': res[1],
        'concluidas': res[2],
        'fora': res[3],
        'voltou': res[4],
        'reclamou': res[5],
        'rotas_loja': res[6],
        'motoboys': res[7],
        'acerto': res[8],
      });
    } catch (e) {
      debugPrint('Erro ao carregar o painel de entregas: $e');
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _aplicar(Map<String, dynamic> d) {
    final cfg = d['cfg'] as Map<String, dynamic>?;
    final loja = d['loja'] as Map<String, dynamic>?;
    final acertos = <String, _Acerto>{};
    for (final a in (d['acerto'] as List? ?? const [])) {
      final nome = ((a['entregador'] as Map?)?['nome'] as String?)?.split(' ').first ?? 'Motoboy';
      final x = acertos.putIfAbsent(nome, () => _Acerto(nome));
      x.rotas++;
      x.entregas += (a['n_pedidos'] as num?)?.toInt() ?? 0;
      x.ganhou += (a['valor_entregador'] as num?)?.toDouble() ?? 0;
      x.dinheiro += (a['dinheiro_recebido'] as num?)?.toDouble() ?? 0;
    }
    setState(() {
      _ligado = cfg?['ativo'] as bool? ?? false;
      _pausadoAte = _Rota._dt(cfg?['pausado_ate']);
      _chuvaValor = (cfg?['chuva_valor'] as num?)?.toDouble() ?? 0;
      _chuvaAte = _Rota._dt(cfg?['chuva_ate']);
      final lat = (loja?['latitude'] as num?)?.toDouble(), lon = (loja?['longitude'] as num?)?.toDouble();
      if (lat != null && lon != null) _loja = ll.LatLng(lat, lon);
      _resumo = d['resumo'] is Map ? Map<String, dynamic>.from(d['resumo'] as Map) : null;
      _rotas = [for (final r in (d['rotas'] as List? ?? const [])) _Rota.de(Map<String, dynamic>.from(r as Map))];
      _concluidas = [for (final r in (d['concluidas'] as List? ?? const [])) _Rota.de(Map<String, dynamic>.from(r as Map))];
      _fora = [
        for (final f in (d['fora'] as List? ?? const []))
          (_PedidoRota.de(f['pedido'] as Map<String, dynamic>), f['motivo'] as String? ?? ''),
      ];
      _naoEntregues = [
        for (final rp in (d['voltou'] as List? ?? const []))
          _PedidoRota.de(rp['pedido'] as Map<String, dynamic>, rp as Map<String, dynamic>),
      ];
      _reclamacoes = [
        for (final rp in (d['reclamou'] as List? ?? const []))
          _PedidoRota.de(rp['pedido'] as Map<String, dynamic>, rp as Map<String, dynamic>),
      ];
      _acertos = acertos.values.toList();
      _rotasLoja = [for (final r in (d['rotas_loja'] as List? ?? const [])) _RotaLoja.de(Map<String, dynamic>.from(r as Map))];
      _motoboys = [
        for (final m in (d['motoboys'] as List? ?? const []))
          (
            id: m['id'] as String,
            nome: (m['nome'] as String? ?? 'Motoboy').split(' ').first,
            disponivel: m['disponivel'] as bool? ?? true,
            lat: (m['pos_lat'] as num?)?.toDouble(),
            lon: (m['pos_lon'] as num?)?.toDouble(),
            em: _Rota._dt(m['pos_em']),
          ),
      ];
      _carregando = false;
    });
  }

  Future<void> _rpc(String chave, String fn, Map<String, dynamic> params, {String? ok}) async {
    final mensageiro = ScaffoldMessenger.of(context);
    if (_demo) {
      mensageiro.showSnackBar(SnackBar(content: Text('(bancada) $fn')));
      return;
    }
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
    if (_demo) return;
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

  String _hora(DateTime t) => DateFormat('HH:mm').format(t);

  String _haQuanto(DateTime t) {
    final s = DateTime.now().difference(t).inSeconds;
    if (s < 60) return 'há $s s';
    final m = s ~/ 60;
    if (m < 60) return 'há $m min';
    return 'às ${_hora(t)}';
  }

  String _km(double? km) => km == null ? '' : '${km.toStringAsFixed(1).replaceAll('.', ',')} km';

  String _motivoFora(String m) => switch (m) {
        'nao_paga_entrega' => 'não paga o motoboy',
        'loja_entrega' => 'a loja vai entregar',
        'loja_tirou' => 'tirado da rota pela loja',
        'sem_localizacao' => 'endereço sem localização',
        _ => 'fora das ofertas',
      };

  // ── Ações ────────────────────────────────────────────────────────────────────────────────────────
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
                title: Text('${r.bairros} · ${r.pedidos.length} entrega${r.pedidos.length == 1 ? '' : 's'}'),
                subtitle: Text(r.pedidos.map((x) => '#${x.numero}').join(' · ')),
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

  Future<void> _cancelarRota(_Rota r) async {
    if (await _confirmar('Eu entrego esta rota',
        'A rota é cancelada e a loja entrega estes pedidos.${r.status == 'aceita' ? ' O motoboy é avisado.' : ''}', 'Eu entrego')) {
      await _rpc('canc${r.id}', 'entrega_oferta_cancelar_rota', {'p_rota_id': r.id}, ok: 'Rota cancelada: a loja entrega.');
    }
  }

  Future<void> _trocarMotoboy(_Rota r) async {
    if (await _confirmar('Trocar motoboy', '${r.motoboy ?? 'O motoboy'} sai da rota e ela é oferecida pros outros.', 'Trocar')) {
      await _rpc('troca${r.id}', 'entrega_oferta_trocar_motoboy', {'p_rota_id': r.id}, ok: 'Rota oferecida pros outros motoboys.');
    }
  }

  Future<void> _pausarOuRetomar() async {
    if (!_ligado) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const EntregaOfertaConfigScreen()));
      await _carregar();
      return;
    }
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
              const ListTile(
                title: Text('Pausar ofertas novas', style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('As rotas que já têm motoboy continuam.'),
              ),
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
        ok: 'Ofertas pausadas até ${DateFormat('dd/MM HH:mm').format(ate)}.');
  }

  bool get _chovendo => _chuvaAte != null && _chuvaAte!.isAfter(DateTime.now()) && _chuvaValor > 0;

  /// Liga (ou muda) o bônus de chuva. [mudar] = já ligado, trocar valor/horário.
  Future<void> _ligarChuva({bool mudar = false}) async {
    var valor = _chuvaValor > 0 ? _chuvaValor : 3.0;
    var horas = 2;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(mudar ? 'Mudar o bônus de chuva' : 'Está chovendo',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Cada rota oferecida ganha um valor a mais. Desliga sozinho na hora escolhida.',
                    style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 16),
                const Text('Valor a mais por rota', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  for (final v in [2.0, 3.0, 5.0])
                    ChoiceChip(label: Text(_moeda.format(v)), selected: valor == v, onSelected: (_) => set(() => valor = v)),
                ]),
                const SizedBox(height: 16),
                const Text('Por quanto tempo', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final h in [1, 2, 3])
                    ChoiceChip(
                        label: Text('$h h · até ${_hora(DateTime.now().add(Duration(hours: h)))}'),
                        selected: horas == h,
                        onSelected: (_) => set(() => horas = h)),
                ]),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(mudar ? 'Salvar' : 'Ligar bônus de chuva')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (ok != true) return;
    final ate = DateTime.now().add(Duration(hours: horas));
    await _rpc('chuva', 'entrega_oferta_chuva', {'p_valor': valor, 'p_ate': ate.toUtc().toIso8601String()},
        ok: 'Chuva ligada: +${_moeda.format(valor)} por rota até ${_hora(ate)}.');
  }

  Future<void> _desligarChuva() =>
      _rpc('chuva', 'entrega_oferta_chuva', {'p_valor': 0, 'p_ate': null}, ok: 'Bônus de chuva desligado.');

  void _ligar(String? tel) {
    final t = (tel ?? '').replaceAll(RegExp(r'\D'), '');
    if (t.isEmpty) return;
    launchUrl(Uri.parse('tel:+${t.startsWith('55') ? t : '55$t'}'));
  }

  bool _ocupadoComRota(String nome) =>
      _rotas.any((r) => (r.status == 'aceita' || r.status == 'em_andamento') && r.motoboy == nome);

  Future<void> _oferecerPara(_Rota r) async {
    if (_motoboys.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Nenhum motoboy cadastrado pra receber ofertas.')));
      return;
    }
    final m = await showModalBottomSheet<({String id, String nome, bool disponivel, double? lat, double? lon, DateTime? em})>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(
            title: Text('Oferecer só para…', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Só ele recebe a oferta. Se não aceitar, a rota volta pra você decidir.'),
          ),
          for (final x in _motoboys)
            ListTile(
              leading: Icon(Icons.two_wheeler, color: x.disponivel ? Colors.green.shade700 : _suave),
              title: Text(x.nome),
              subtitle: Text(_ocupadoComRota(x.nome) ? 'está com uma rota agora' : (x.disponivel ? 'disponível' : 'de folga')),
              enabled: !_ocupadoComRota(x.nome),
              onTap: () => Navigator.pop(ctx, x),
            ),
        ]),
      ),
    );
    if (m == null) return;
    await _rpc('para${r.id}', 'entrega_oferta_oferecer_para', {'p_rota_id': r.id, 'p_entregador_id': m.id},
        ok: 'Rota oferecida só pro ${m.nome}.');
  }

  void _abrirMapaMotoboy(_Rota r) => launchUrl(Uri.parse('https://www.google.com/maps/search/?api=1&query=${r.posLat},${r.posLon}'),
      mode: LaunchMode.externalApplication);

  // ── Peças visuais ────────────────────────────────────────────────────────────────────────────────
  ColorScheme get _cores => Theme.of(context).colorScheme;
  Color get _suave => _cores.onSurfaceVariant;

  Widget _caixa({required Widget child, Color? borda, double larguraBorda = 1, EdgeInsets? padding}) =>
      Container(
        width: double.infinity,
        padding: padding ?? const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _cores.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borda ?? _cores.outlineVariant, width: larguraBorda),
        ),
        child: child,
      );

  Widget _selo(String t, _Tom tom) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: tom.fundo, borderRadius: BorderRadius.circular(999)),
        child: Text(t.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: tom.texto, letterSpacing: 0.3)),
      );

  Widget _botao(String t, VoidCallback? onTap, {bool principal = false, IconData? icone}) {
    final ativo = _ocupado == null ? onTap : null;
    final estilo = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
      padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14)),
      shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
      textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
    );
    if (principal) {
      return icone == null
          ? FilledButton(onPressed: ativo, style: estilo, child: Text(t))
          : FilledButton.icon(onPressed: ativo, style: estilo, icon: Icon(icone, size: 18), label: Text(t));
    }
    final contorno = estilo.copyWith(
      foregroundColor: WidgetStatePropertyAll(_cores.onSurface),
      side: WidgetStatePropertyAll(BorderSide(color: _cores.outlineVariant)),
    );
    return icone == null
        ? OutlinedButton(onPressed: ativo, style: contorno, child: Text(t))
        : OutlinedButton.icon(onPressed: ativo, style: contorno, icon: Icon(icone, size: 18), label: Text(t));
  }

  Widget _tituloSecao(String t, {Color? cor, Widget? direita, String? sub}) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 6,
          children: [
            Text(t, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: cor)),
            if (sub != null) Text(sub, style: TextStyle(fontSize: 12, color: _suave)),
            if (direita != null) direita,
          ],
        ),
      );

  // ── Cabeçalho, chuva e resumo ────────────────────────────────────────────────────────────────────
  Widget _cabecalho() {
    final pausado = _pausadoAte != null && _pausadoAte!.isAfter(DateTime.now());
    // sem DateFormat('EEEE', 'pt_BR'): o app não carrega os dados de idioma do intl
    const dias = ['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'];
    final agora = DateTime.now();
    final data = '${dias[agora.weekday - 1]}, ${DateFormat('dd/MM').format(agora)}';
    final corChave = !_ligado ? _cores.outline : (pausado ? Colors.orange.shade700 : Colors.green.shade700);
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 16,
      runSpacing: 12,
      children: [
        Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text('${data[0].toUpperCase()}${data.substring(1)}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
          Text('Motoboys por oferta e rotas da loja', style: TextStyle(fontSize: 13, color: _suave)),
        ]),
        Wrap(spacing: 10, runSpacing: 10, children: [
          OutlinedButton(
            onPressed: _ocupado == null ? _pausarOuRetomar : null,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 44),
              foregroundColor: _cores.onSurface,
              side: BorderSide(color: _cores.outlineVariant),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 36,
                height: 20,
                padding: const EdgeInsets.all(2),
                alignment: _ligado && !pausado ? Alignment.centerRight : Alignment.centerLeft,
                decoration: BoxDecoration(color: corChave, borderRadius: BorderRadius.circular(999)),
                child: Container(width: 16, height: 16, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
              ),
              const SizedBox(width: 10),
              Text(
                  !_ligado
                      ? 'Ofertas desligadas'
                      : pausado
                          ? 'Pausadas até ${_hora(_pausadoAte!)}'
                          : 'Ofertas ligadas',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
          OutlinedButton.icon(
            onPressed: _ocupado == null ? (_chovendo ? _desligarChuva : _ligarChuva) : null,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 44),
              backgroundColor: _chovendo ? _tomEmRota.fundo : null,
              foregroundColor: _chovendo ? _tomEmRota.texto : _cores.onSurface,
              side: BorderSide(color: _chovendo ? const Color(0xFF1D4ED8) : _cores.outlineVariant),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            icon: const Icon(Icons.umbrella, size: 18),
            label: Text(_chovendo ? 'Chovendo · ligado' : 'Está chovendo?'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RotasEntregaScreen())),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(fontWeight: FontWeight.w700),
            ),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Rota da loja'),
          ),
        ]),
      ],
    );
  }

  Widget _faixaChuva() {
    if (!_chovendo) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: _tomEmRota.fundo, borderRadius: BorderRadius.circular(14)),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        runSpacing: 8,
        children: [
          Text.rich(
            TextSpan(style: TextStyle(color: _tomEmRota.texto, fontSize: 14), children: [
              const TextSpan(text: 'Bônus de chuva ligado: ', style: TextStyle(fontWeight: FontWeight.w800)),
              TextSpan(text: '+${_moeda.format(_chuvaValor)} em cada rota oferecida · desliga sozinho às ${_hora(_chuvaAte!)}'),
            ]),
          ),
          Wrap(spacing: 8, children: [
            OutlinedButton(
              onPressed: _ocupado == null ? () => _ligarChuva(mudar: true) : null,
              style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: _tomEmRota.texto,
                  side: const BorderSide(color: Color(0xFF93C5FD)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('Mudar valor / horário'),
            ),
            FilledButton(
              onPressed: _ocupado == null ? _desligarChuva : null,
              style: FilledButton.styleFrom(
                  backgroundColor: _tomEmRota.texto, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
              child: const Text('Desligar agora'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _resumoDoDia(bool largo) {
    final r = _resumo ?? const {};
    int i(String k) => (r[k] as num?)?.toInt() ?? 0;
    double d(String k) => (r[k] as num?)?.toDouble() ?? 0;
    final emRota = _rotas.where((x) => x.status == 'em_andamento').length;
    final indo = _rotas.where((x) => x.status == 'aceita').length;
    final esperando = _rotas.where((x) => x.status == 'ofertada').length;
    final sobra = d('frete_cobrado') - d('pago_motoboys');
    final naoEntregues = _naoEntregues.length;
    Widget kpi(String rotulo, Widget valor, String sub, {Color? corSub}) => _caixa(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rotulo, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _suave)),
            const SizedBox(height: 4),
            valor,
            const SizedBox(height: 2),
            Text(sub, style: TextStyle(fontSize: 13, color: corSub ?? _suave, fontWeight: corSub == null ? null : FontWeight.w600)),
          ]),
        );
    Widget numero(String a, [String? b]) => Text.rich(TextSpan(children: [
          TextSpan(text: a, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
          if (b != null) TextSpan(text: ' $b', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _suave)),
        ]));
    final cards = [
      kpi('Rotas hoje', numero('${_rotas.length + _concluidas.length}'), '$emRota em rota · $indo indo/na loja · $esperando esperando'),
      kpi('Entregas', numero('${i('entregas')}'), naoEntregues == 0 ? 'nenhuma voltou' : '$naoEntregues não entregue${naoEntregues == 1 ? '' : 's'}'),
      kpi('Ofertas aceitas', numero('${i('aceitas')}', 'de ${i('ofertadas')}'),
          r['min_ate_aceite'] == null ? 'sem tempo de aceite ainda' : 'tempo até aceitar: ~${(r['min_ate_aceite'] as num).round()} min'),
      kpi('Pago a motoboys', numero(_moeda.format(d('pago_motoboys'))),
          'frete cobrado ${_moeda.format(d('frete_cobrado'))} · ${sobra >= 0 ? 'sobra ${_moeda.format(sobra)}' : 'faltam ${_moeda.format(-sobra)}'}',
          corSub: sobra >= 0 ? Colors.green.shade800 : Colors.red.shade800),
    ];
    final colunas = largo ? 4 : 2;
    return LayoutBuilder(builder: (context, c) {
      const gap = 12.0;
      final w = (c.maxWidth - gap * (colunas - 1)) / colunas;
      return Wrap(spacing: gap, runSpacing: gap, children: [for (final k in cards) SizedBox(width: w, child: k)]);
    });
  }

  Widget _linhaMotoboys() {
    final livres = _motoboys.where((m) => m.disponivel && !_ocupadoComRota(m.nome)).length;
    final disp = livres;
    return Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Text('Motoboys livres agora: $livres de ${_motoboys.length}',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: disp == 0 ? _tomProblema.texto : _cores.onSurface)),
      for (final m in _motoboys)
        _selo('${m.nome} · ${_ocupadoComRota(m.nome) ? 'em rota' : (m.disponivel ? 'disponível' : 'de folga')}',
            _ocupadoComRota(m.nome) ? _tomEmRota : (m.disponivel ? _tomLoja : _tomNeutro)),
    ]);
  }

  // ── Mapa ─────────────────────────────────────────────────────────────────────────────────────────
  Color _corLinha(_Rota r) => switch (r.status) {
        'em_andamento' => const Color(0xFF1D4ED8),
        'aceita' => const Color(0xFF15803D),
        'sem_entregador' => const Color(0xFFB91C1C),
        _ => const Color(0xFFB45309),
      };

  Widget _mapa(double altura) {
    final loja = _loja;
    final pontos = <ll.LatLng>[];
    final linhas = <osm.Polyline>[];
    final marcas = <osm.Marker>[];
    final semGps = <_Rota>[];
    if (loja != null) {
      pontos.add(loja);
      for (final r in _rotas) {
        final cor = _corLinha(r);
        final trecho = <ll.LatLng>[loja];
        var n = 0;
        for (final p in r.pedidos) {
          n++;
          if (p.lat == null || p.lon == null) continue;
          final pt = ll.LatLng(p.lat!, p.lon!);
          trecho.add(pt);
          pontos.add(pt);
          marcas.add(osm.Marker(
            point: pt,
            width: 26,
            height: 26,
            child: Tooltip(
              message: '#${p.numero} ${p.cliente}${p.bairro.isEmpty ? '' : ' · ${p.bairro}'}',
              child: Container(
                decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: cor, width: 3)),
                alignment: Alignment.center,
                child: p.entregue
                    ? Icon(Icons.check, size: 14, color: cor)
                    : Text('$n', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: cor)),
              ),
            ),
          ));
        }
        if (trecho.length > 1) {
          linhas.add(osm.Polyline(
            points: trecho,
            color: cor.withValues(alpha: 0.85),
            strokeWidth: 4,
            pattern: r.status == 'ofertada' || r.status == 'sem_entregador'
                ? osm.StrokePattern.dashed(segments: const [10, 8])
                : const osm.StrokePattern.solid(),
          ));
        }
        final ativo = r.status == 'aceita' || r.status == 'em_andamento';
        if (ativo && r.posLat != null && r.posLon != null) {
          final pt = ll.LatLng(r.posLat!, r.posLon!);
          pontos.add(pt);
          final recente = r.posEm != null && DateTime.now().difference(r.posEm!).inMinutes < 3;
          marcas.add(osm.Marker(
            point: pt,
            width: 160,
            height: 62,
            alignment: Alignment.topCenter,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)]),
                child: Text('${r.motoboy ?? 'Motoboy'} · ${r.posEm == null ? '' : _haQuanto(r.posEm!)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF1E1E24))),
              ),
              const SizedBox(height: 3),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: recente ? _cores.primary : Colors.grey.shade600,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [BoxShadow(color: (recente ? _cores.primary : Colors.grey).withValues(alpha: 0.3), blurRadius: 0, spreadRadius: 5)],
                ),
                alignment: Alignment.center,
                child: Text((r.motoboy ?? 'M').substring(0, 1).toUpperCase(),
                    style: TextStyle(color: _cores.onPrimary, fontWeight: FontWeight.w800)),
              ),
            ]),
          ));
        } else if (ativo) {
          semGps.add(r);
        }
      }
      // motoboys disponíveis (Kitsune aberto, posição de até 10 min) — termo v3
      for (final m in _motoboys) {
        if (!m.disponivel || _ocupadoComRota(m.nome) || m.lat == null || m.lon == null || m.em == null) continue;
        if (DateTime.now().difference(m.em!).inMinutes > 10) continue;
        final pt = ll.LatLng(m.lat!, m.lon!);
        pontos.add(pt);
        marcas.add(osm.Marker(
          point: pt,
          width: 150,
          height: 56,
          alignment: Alignment.topCenter,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(8), boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 3)]),
              child: Text('${m.nome} · livre · ${_haQuanto(m.em!)}',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF166534))),
            ),
            const SizedBox(height: 3),
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                  color: const Color(0xFF15803D), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
              alignment: Alignment.center,
              child: Text(m.nome.substring(0, 1).toUpperCase(),
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
            ),
          ]),
        ));
      }
      for (final r in _rotasLoja) {
        final trecho = <ll.LatLng>[loja];
        for (final p in r.paradas) {
          if (p.lat == null || p.lon == null) continue;
          final pt = ll.LatLng(p.lat!, p.lon!);
          trecho.add(pt);
          pontos.add(pt);
          marcas.add(osm.Marker(
            point: pt,
            width: 22,
            height: 22,
            child: Container(
              decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: const Color(0xFF52525B), width: 3)),
              child: p.entregue ? const Icon(Icons.check, size: 12, color: Color(0xFF52525B)) : null,
            ),
          ));
        }
        if (trecho.length > 1) linhas.add(osm.Polyline(points: trecho, color: const Color(0xFF52525B), strokeWidth: 3));
      }
      marcas.insert(
          0,
          osm.Marker(
            point: loja,
            width: 44,
            height: 28,
            child: Container(
              decoration: BoxDecoration(color: const Color(0xFF1E1E24), borderRadius: BorderRadius.circular(7)),
              alignment: Alignment.center,
              child: const Text('LOJA', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
            ),
          ));
    }
    Widget legenda(Color cor, String t, {bool ponto = false}) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: ponto ? 12 : 16,
              height: ponto ? 12 : 4,
              decoration: BoxDecoration(color: cor, borderRadius: BorderRadius.circular(ponto ? 6 : 2))),
          const SizedBox(width: 6),
          Text(t, style: TextStyle(fontSize: 12, color: _suave)),
        ]);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
          color: _cores.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: _cores.outlineVariant)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: [
              const Text('Mapa agora', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              Wrap(spacing: 14, runSpacing: 4, children: [
                legenda(const Color(0xFF1E1E24), 'Loja', ponto: true),
                legenda(_cores.primary, 'Motoboy em rota', ponto: true),
                legenda(const Color(0xFF15803D), 'Motoboy livre', ponto: true),
                legenda(const Color(0xFF1D4ED8), 'em rota'),
                legenda(const Color(0xFF15803D), 'indo/na loja'),
                legenda(const Color(0xFFB45309), 'esperando aceite'),
                if (_rotasLoja.isNotEmpty) legenda(const Color(0xFF52525B), 'rota da loja'),
              ]),
            ],
          ),
        ),
        Divider(height: 1, color: _cores.outlineVariant),
        SizedBox(
          height: altura,
          child: loja == null
              ? Center(child: Text('Cadastre a localização da loja pra ver o mapa.', style: TextStyle(color: _suave)))
              : osm.FlutterMap(
                  key: ValueKey('mapa${_rotas.length}${_rotas.map((r) => r.pedidos.length).join()}'),
                  options: osm.MapOptions(
                    initialCenter: loja,
                    initialZoom: 13,
                    initialCameraFit: pontos.length > 1
                        ? osm.CameraFit.bounds(bounds: osm.LatLngBounds.fromPoints(pontos), padding: const EdgeInsets.all(56), maxZoom: 15)
                        : null,
                  ),
                  children: [
                    osm.TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.gestor'),
                    osm.PolylineLayer(polylines: linhas),
                    osm.MarkerLayer(markers: marcas),
                    const osm.SimpleAttributionWidget(source: Text('OpenStreetMap')),
                  ],
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: Text(
            semGps.isEmpty
                ? 'Linha cheia = rota com motoboy · tracejada = esperando aceite. O motoboy aparece quando está com o Kitsune aberto.'
                : 'Sem GPS agora: ${semGps.map((r) => r.motoboy ?? 'motoboy').join(', ')}'
                    '${semGps.any((r) => r.gpsFalha != null) ? ' (localização desligada ou bloqueada no celular)' : ' (Kitsune fechado ou sem sinal)'}.',
            style: TextStyle(fontSize: 12, color: semGps.isEmpty ? _suave : _tomProblema.texto),
          ),
        ),
      ]),
    );
  }

  // ── Precisa de você ──────────────────────────────────────────────────────────────────────────────
  Widget _item(String titulo, String sub, List<Widget> botoes, {bool ultimo = false}) => Container(
        width: double.infinity,
        padding: EdgeInsets.only(bottom: ultimo ? 0 : 12),
        margin: EdgeInsets.only(bottom: ultimo ? 0 : 12),
        decoration: BoxDecoration(border: ultimo ? null : Border(bottom: BorderSide(color: _cores.outlineVariant.withValues(alpha: 0.6)))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(fontSize: 13, color: _suave)),
          if (botoes.isNotEmpty) ...[const SizedBox(height: 8), Wrap(spacing: 8, runSpacing: 8, children: botoes)],
        ]),
      );

  Widget? _precisaDeVoce() {
    final itens = <Widget Function(bool)>[];
    final agora = DateTime.now();
    for (final r in _rotas.where((r) => r.status == 'aceita' || r.status == 'em_andamento')) {
      for (final p in r.pedidos.where((p) => !p.resolvido && p.prometidoAte != null && p.prometidoAte!.isBefore(agora))) {
        itens.add((u) => _item(
              'Entrega atrasada: #${p.numero} ${p.cliente}${p.bairro.isEmpty ? '' : ' · ${p.bairro}'}',
              'prometido até ${_hora(p.prometidoAte!)} (${agora.difference(p.prometidoAte!).inMinutes} min atrás) · ${r.motoboy ?? 'motoboy'}'
                  '${r.posEm == null ? '' : ' · GPS ${_haQuanto(r.posEm!)}'}',
              [
                if (r.telefoneMotoboy != null) _botao('Ligar pro ${r.motoboy ?? 'motoboy'}', () => _ligar(r.telefoneMotoboy), principal: true, icone: Icons.call),
                if (r.posLat != null) _botao('Ver no mapa', () => _abrirMapaMotoboy(r), icone: Icons.map_outlined),
              ],
              ultimo: u,
            ));
      }
      if (r.status == 'em_andamento' && r.posEm != null && agora.difference(r.posEm!).inMinutes >= 5 && r.gpsFalha == null) {
        itens.add((u) => _item(
              'GPS do ${r.motoboy ?? 'motoboy'} parado há ${agora.difference(r.posEm!).inMinutes} min',
              'Pode ser o Kitsune fechado, a tela apagada ou ele parado. Última posição ${_haQuanto(r.posEm!)}.',
              [
                if (r.telefoneMotoboy != null) _botao('Ligar pro ${r.motoboy ?? 'motoboy'}', () => _ligar(r.telefoneMotoboy), icone: Icons.call),
                _botao('Ver no mapa', () => _abrirMapaMotoboy(r), icone: Icons.map_outlined),
              ],
              ultimo: u,
            ));
      }
    }
    for (final r in _rotas.where((r) => r.status == 'em_andamento')) {
      for (final p in r.pedidos.where((p) => p.devolucaoPedida)) {
        itens.add((u) => _item(
              '${r.motoboy ?? 'Motoboy'} pede pra devolver #${p.numero} · ${p.cliente}',
              '${p.motivoDevolucao ?? 'não conseguiu entregar'} · chegou, ligou, esperou e tirou foto. Só traz de volta se você autorizar.',
              [
                _botao('Autorizar devolução', () => _rpc('aut${p.id}', 'entrega_oferta_autorizar_devolucao', {'p_pedido_id': p.id},
                    ok: 'Devolução do #${p.numero} autorizada. O motoboy foi avisado.'), principal: true),
                _botao('Pedir pra tentar de novo', () => _rpc('ten${p.id}', 'entrega_oferta_tentar_de_novo', {'p_pedido_id': p.id},
                    ok: 'Pedimos pro motoboy tentar o #${p.numero} de novo.')),
                if (p.foto != null) _botao('Ver foto', () => _verFoto(p.foto!, 'Fachada · pedido #${p.numero}')),
                if (r.telefoneMotoboy != null) _botao('Ligar pro ${r.motoboy ?? 'motoboy'}', () => _ligar(r.telefoneMotoboy), icone: Icons.call),
              ],
              ultimo: u,
            ));
      }
    }
    for (final r in _rotas.where((r) => r.status == 'sem_entregador')) {
      itens.add((u) => _item(
            'Ninguém aceitou: ${r.bairros} · ${r.pedidos.length} entrega${r.pedidos.length == 1 ? '' : 's'}',
            [
              if (r.ofertadaEm != null) 'oferecida às ${_hora(r.ofertadaEm!)}',
              if (r.prazoSaida != null) 'era pra sair às ${_hora(r.prazoSaida!)}',
              if (r.valor != null) _moeda.format(r.valor),
            ].join(' · '),
            [
              _botao('Oferecer de novo +R\$ 2', () => _rpc('bonus${r.id}', 'entrega_oferta_bonus', {'p_rota_id': r.id, 'p_valor': 2},
                  ok: 'Rota oferecida de novo com +R\$ 2.'), principal: true),
              _botao('Oferecer só para…', () => _oferecerPara(r)),
              _botao('Eu entrego', () => _cancelarRota(r)),
            ],
            ultimo: u,
          ));
    }
    for (final r in _rotas.where((r) => r.status == 'ofertada' && r.erroRota != null)) {
      itens.add((u) => _item('Não consegui calcular a rota: ${r.bairros}', 'Confira o endereço do cliente (${r.erroRota}).',
          [_botao('Eu entrego', () => _cancelarRota(r))], ultimo: u));
    }
    for (final r in _rotas.where((r) => (r.status == 'aceita' || r.status == 'em_andamento') && r.gpsFalha != null)) {
      itens.add((u) => _item(
          'GPS do ${r.motoboy ?? 'motoboy'} não está chegando',
          switch (r.gpsFalha) {
            'semSinal' => 'Sem sinal de GPS agora. Na rua costuma voltar sozinho.',
            'semRede' => 'O celular dele está sem internet.',
            _ => 'A localização está desligada ou bloqueada no celular dele. O Kitsune mostra pra ele como ligar.',
          },
          const [],
          ultimo: u));
    }
    for (final p in _reclamacoes) {
      itens.add((u) => _item('#${p.numero} · cliente reclamou da entrega', 'Respondeu "Tive um problema". O acerto dessa rota espera você resolver.', [
            if (p.foto != null) _botao('Ver foto', () => _verFoto(p.foto!, 'Entrega · pedido #${p.numero}')),
            _botao('Resolvido', () => _rpc('rec${p.id}', 'entrega_oferta_resolver_reclamacao', {'p_pedido_id': p.id}, ok: 'Reclamação resolvida.')),
          ], ultimo: u));
    }
    for (final p in _naoEntregues) {
      itens.add((u) => _item(
            '#${p.numero} não entregue · ${p.cliente}${p.bairro.isEmpty ? '' : ' · ${p.bairro}'}',
            p.devolucaoConfirmada ? 'Pedido de volta na loja. Reentregue ou cancele no detalhe do pedido.' : 'O motoboy está trazendo de volta. Confirme quando chegar (o acerto dele espera isso).',
            [
              if (p.foto != null) _botao('Ver foto', () => _verFoto(p.foto!, 'Fachada · pedido #${p.numero}')),
              if (!p.devolucaoConfirmada)
                _botao('Recebi de volta', () => _rpc('dev${p.id}', 'entrega_oferta_confirmar_devolucao', {'p_pedido_id': p.id},
                    ok: 'Devolução do pedido #${p.numero} confirmada.')),
              _botao('Reentregar', () => _rpc('re${p.id}', 'entrega_oferta_reentregar', {'p_pedido_id': p.id},
                  ok: 'Pedido #${p.numero} voltou pra oferta.')),
            ],
            ultimo: u,
          ));
    }
    for (final (p, motivo) in _fora) {
      itens.add((u) => _item('#${p.numero} ${_motivoFora(motivo)}', '${p.cliente}${p.bairro.isEmpty ? '' : ' · ${p.bairro}'}', [
            _botao('Mandar mesmo assim', () => _rpc('f${p.id}', 'entrega_oferta_forcar', {'p_pedido_id': p.id}, ok: 'Pedido #${p.numero} vai pra oferta.')),
            _botao('Juntar numa rota', () => _juntar(p)),
          ], ultimo: u));
    }
    if (itens.isEmpty) return null;
    return _caixa(
      borda: const Color(0xFFFCA5A5),
      larguraBorda: 2,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Precisa de você · ${itens.length}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _tomProblema.texto)),
        const SizedBox(height: 12),
        for (var i = 0; i < itens.length; i++) itens[i](i == itens.length - 1),
      ]),
    );
  }

  // ── Rotas ────────────────────────────────────────────────────────────────────────────────────────
  (String, _Tom) _status(_Rota r) {
    if (r.status == 'concluida') return ('concluída${r.finalizadaEm == null ? '' : ' ${_hora(r.finalizadaEm!)}'}', _tomNeutro);
    if (r.status == 'em_andamento') return ('em rota · ${r.entregues} de ${r.pedidos.length} entregues', _tomEmRota);
    if (r.status == 'aceita') return (r.chegou ? 'chegou na loja' : 'vindo pra loja', _tomLoja);
    if (r.status == 'sem_entregador') return ('sem motoboy', _tomProblema);
    if (r.calculando) return ('calculando a rota', _tomNeutro);
    if (!r.ofertaSaiu) return ('juntando pedidos', _tomNeutro);
    final min = r.ofertadaEm == null ? null : DateTime.now().difference(r.ofertadaEm!).inMinutes;
    return ('esperando aceite${min == null ? '' : ' · $min min'}', _tomEspera);
  }

  String _linhaInfo(_Rota r) {
    final partes = <String>[];
    switch (r.status) {
      case 'em_andamento':
        if (r.saiuEm != null) partes.add('saiu ${_hora(r.saiuEm!)}');
        if (r.posEm != null) partes.add('GPS visto ${_haQuanto(r.posEm!)}');
      case 'aceita':
        if (r.prazoSaida != null) partes.add('sair até ${_hora(r.prazoSaida!)}');
        if (r.posEm != null) partes.add('GPS visto ${_haQuanto(r.posEm!)}');
      case 'ofertada':
        if (!r.ofertaSaiu && r.prazoSaida != null) {
          partes.add('oferta sai ~${_hora(r.prazoSaida!.subtract(const Duration(minutes: 30)))}');
        } else if (r.ofertadaEm != null) {
          partes.add('oferecida às ${_hora(r.ofertadaEm!)}');
        }
        if (r.prazoSaida != null) partes.add('sair até ${_hora(r.prazoSaida!)}');
      case 'concluida':
        if (r.saiuEm != null) partes.add('saiu ${_hora(r.saiuEm!)}');
    }
    if (r.bonus > 0) partes.add('inclui +${_moeda.format(r.bonus)} de bônus');
    return partes.join(' · ');
  }

  Widget _parada(_Rota r, int n, _PedidoRota p, bool proxima) {
    final antesDeSair = r.status == 'ofertada' || r.status == 'aceita';
    final (String direita, Color cor) = switch (p.status) {
      'entregue' || 'concluido' => ('entregue', Colors.green.shade800),
      'cancelado' => ('cancelado', _suave),
      'nao_entregue' => ('não entregue', _tomProblema.texto),
      _ when p.devolucaoPedida => ('pede devolução', _tomProblema.texto),
      _ => (proxima ? 'próxima' : '', _tomEmRota.texto),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Expanded(
          child: Text(
            '$n. #${p.numero} ${p.cliente}${p.bairro.isEmpty ? '' : ' · ${p.bairro}'}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: proxima ? FontWeight.w800 : FontWeight.w500,
              decoration: p.status == 'cancelado' ? TextDecoration.lineThrough : null,
            ),
          ),
        ),
        if (p.contestado) Padding(padding: const EdgeInsets.only(left: 6), child: Icon(Icons.report_problem, size: 16, color: Colors.orange.shade800)),
        if (direita.isNotEmpty)
          Padding(padding: const EdgeInsets.only(left: 8), child: Text(direita, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: cor))),
        if (p.foto != null)
          TextButton(
            onPressed: () => _verFoto(p.foto!, 'Pedido #${p.numero}'),
            style: TextButton.styleFrom(minimumSize: const Size(0, 32), padding: const EdgeInsets.symmetric(horizontal: 6)),
            child: const Text('foto', style: TextStyle(fontSize: 13)),
          ),
        if (antesDeSair)
          PopupMenuButton<String>(
            tooltip: 'Ações do pedido #${p.numero}',
            padding: EdgeInsets.zero,
            iconSize: 20,
            style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(36, 28)),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
            icon: Icon(Icons.more_horiz, size: 20, color: _suave),
            onSelected: (acao) async {
              if (acao == 'tirar') {
                await _rpc('p${p.id}', 'entrega_oferta_tirar_pedido', {'p_pedido_id': p.id}, ok: 'Pedido #${p.numero} saiu da rota.');
              } else {
                await _rpc('p${p.id}', 'entrega_oferta_eu_entrego', {'p_pedido_id': p.id}, ok: 'Pedido #${p.numero}: a loja entrega.');
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'tirar', child: Text('Tirar da rota (volta pra oferta)')),
              PopupMenuItem(value: 'eu', child: Text('Eu entrego este')),
            ],
          ),
      ]),
    );
  }

  Widget _cartaoRota(_Rota r) {
    final (rotulo, tom) = _status(r);
    final info = _linhaInfo(r);
    final proxima = r.status == 'em_andamento' ? r.pedidos.indexWhere((p) => !p.resolvido && !p.devolucaoPedida) : -1;
    final esperando = r.status == 'ofertada';
    final botoes = <Widget>[
      if (r.status == 'aceita')
        BotaoEntregarMotoboy(info: RotaOfertaInfo(rotaId: r.id, status: r.status, entregador: r.motoboy, n: r.pedidos.length)),
      if ((r.status == 'aceita' || r.status == 'em_andamento') && r.posLat != null) _botao('Ver no mapa', () => _abrirMapaMotoboy(r), icone: Icons.map_outlined),
      if (r.status == 'em_andamento' || r.status == 'concluida')
        _botao('Ver trajeto', () {
          if (_demo) return;
          Navigator.push(context, MaterialPageRoute(builder: (_) => TrajetoRotaScreen(rotaId: r.id, titulo: 'Rota · ${r.bairros}')));
        }, icone: Icons.route),
      if (esperando && r.ofertaSaiu) _botao('Aumentar valor', () => _escolherBonus(r), icone: Icons.trending_up),
      if (esperando) _botao('Oferecer só para…', () => _oferecerPara(r), icone: Icons.person_outline),
      if (esperando && !r.ofertaSaiu)
        _botao('Oferecer agora', () => _rpc('agora${r.id}', 'entrega_oferta_oferecer_agora', {'p_rota_id': r.id}, ok: 'Rota oferecida agora.'),
            icone: Icons.send),
      if (r.status == 'aceita') _botao('Aumentar valor', () => _escolherBonus(r), icone: Icons.trending_up),
      if (r.status == 'aceita') _botao('Trocar motoboy', () => _trocarMotoboy(r), icone: Icons.swap_horiz),
      if (esperando || r.status == 'aceita') _botao('Eu entrego', () => _cancelarRota(r)),
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cores.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: esperando && r.ofertaSaiu ? const Color(0xFFD97706) : _cores.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Align(alignment: Alignment.centerLeft, child: _selo(rotulo, tom))),
          const SizedBox(width: 12),
          if (r.valor != null) Text(_moeda.format(r.valor), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 10),
        Text(
          [
            if (r.motoboy != null) r.motoboy!,
            r.bairros,
            '${r.pedidos.length} entrega${r.pedidos.length == 1 ? '' : 's'}',
            if (r.km != null) _km(r.km),
          ].join(' · '),
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
        if (info.isNotEmpty) ...[const SizedBox(height: 2), Text(info, style: TextStyle(fontSize: 13, color: _suave))],
        if ((r.status == 'aceita' || r.status == 'em_andamento') && r.gpsFalha != null && r.posLat == null) ...[
          const SizedBox(height: 4),
          Text('GPS desligado ou bloqueado no celular dele', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _tomProblema.texto)),
        ],
        const SizedBox(height: 8),
        for (var i = 0; i < r.pedidos.length; i++) _parada(r, i + 1, r.pedidos[i], i == proxima),
        if (botoes.isNotEmpty) ...[const SizedBox(height: 10), Wrap(spacing: 8, runSpacing: 8, children: botoes)],
      ]),
    );
  }

  Widget _secaoRotas() {
    final abertas = _rotas.where((r) => r.status == 'aceita' || r.status == 'em_andamento' || (r.status == 'ofertada' && r.ofertaSaiu)).toList();
    final nAbertas = abertas.length + _rotasLoja.length;
    final lista = _verConcluidas ? _concluidas.reversed.toList() : abertas;
    Widget filtro(String t, bool sel, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(left: 6),
          child: ChoiceChip(label: Text(t), selected: sel, onSelected: (_) => onTap(), showCheckmark: false),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _tituloSecao(
        'Rotas de hoje',
        direita: Row(mainAxisSize: MainAxisSize.min, children: [
          filtro('Abertas · $nAbertas', !_verConcluidas, () => setState(() => _verConcluidas = false)),
          filtro('Concluídas · ${_concluidas.length}', _verConcluidas, () => setState(() => _verConcluidas = true)),
        ]),
      ),
      if (lista.isEmpty)
        _caixa(
          child: Text(_verConcluidas ? 'Nenhuma rota concluída hoje.' : 'Nenhuma rota com motoboy agora. Pedido novo vira oferta sozinho.',
              style: TextStyle(color: _suave)),
        ),
      for (final r in lista) _cartaoRota(r),
      if (!_verConcluidas) for (final r in _rotasLoja) _cartaoRotaLoja(r),
    ]);
  }

  Widget _cartaoRotaLoja(_RotaLoja r) {
    final entregues = r.paradas.where((p) => p.entregue).length;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: _cores.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: _cores.outlineVariant)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _selo('rota da loja · ${r.status == 'em_andamento' ? '$entregues de ${r.paradas.length} entregues' : 'planejada'}', _tomNeutro),
        const SizedBox(height: 10),
        Text('${r.entregador ?? 'Entregador da loja'} · ${r.paradas.length} entrega${r.paradas.length == 1 ? '' : 's'}',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        _botao('Abrir rota da loja', () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RotasEntregaScreen())).then((_) => _carregar()),
            icone: Icons.open_in_new),
      ]),
    );
  }

  Widget? _juntando() {
    final js = _rotas.where((r) => r.status == 'ofertada' && !r.ofertaSaiu && r.erroRota == null).toList();
    if (js.isEmpty) return null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _tituloSecao('Juntando pedidos', sub: 'a rota espera até ~30 min antes de sair pra pegar mais pedidos no caminho'),
      for (final r in js) _cartaoRota(r),
    ]);
  }

  // ── Acerto ───────────────────────────────────────────────────────────────────────────────────────
  Widget _acerto() {
    Widget cel(String t, {bool bold = false, Color? cor, TextAlign? align}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Text(t, textAlign: align, style: TextStyle(fontSize: 14, fontWeight: bold ? FontWeight.w800 : FontWeight.w500, color: cor)),
        );
    Widget cab(String t) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Text(t.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: _suave, letterSpacing: 0.4)),
        );
    void abrir() => Navigator.push(context, MaterialPageRoute(builder: (_) => const EntregaOfertaAcertoScreen())).then((_) => _carregar());
    return _caixa(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _tituloSecao('Acerto com motoboys', direita: TextButton(onPressed: abrir, child: const Text('Abrir acerto e histórico'))),
        if (_acertos.isEmpty)
          Text('Nada pra acertar agora.', style: TextStyle(color: _suave))
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 720),
              child: Table(
                defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                columnWidths: const {0: FlexColumnWidth(1.2), 6: IntrinsicColumnWidth()},
                children: [
                  TableRow(children: [cab('Motoboy'), cab('Rotas'), cab('Entregas'), cab('Ganhou'), cab('Recebeu em dinheiro'), cab('Acerto'), const SizedBox()]),
                  for (final a in _acertos)
                    TableRow(
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: _cores.outlineVariant.withValues(alpha: 0.6)))),
                      children: [
                        cel(a.nome, bold: true),
                        cel('${a.rotas}'),
                        cel('${a.entregas}'),
                        cel(_moeda.format(a.ganhou)),
                        cel(_moeda.format(a.dinheiro)),
                        cel(a.saldo >= 0 ? 'loja paga ${_moeda.format(a.saldo)}' : '${a.nome} devolve ${_moeda.format(-a.saldo)}',
                            bold: true, cor: a.saldo >= 0 ? null : _tomEspera.texto),
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: _botao(a.saldo >= 0 ? 'Pagar' : 'Recebi', abrir, principal: a.saldo >= 0),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Entregas'),
        actions: [
          IconButton(
            tooltip: 'Resumo da semana',
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const EntregaOfertaResumoScreen())),
          ),
          IconButton(
            tooltip: 'Configurar entregador por oferta',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.push(context, MaterialPageRoute(builder: (_) => const EntregaOfertaConfigScreen()));
              await _carregar();
            },
          ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: LayoutBuilder(builder: (context, c) {
                final largo = c.maxWidth >= 1000;
                final precisa = _precisaDeVoce();
                final juntando = _juntando();
                final topo = <Widget>[
                  _cabecalho(),
                  _faixaChuva(),
                  const SizedBox(height: 16),
                  _resumoDoDia(largo),
                  const SizedBox(height: 12),
                  _linhaMotoboys(),
                  const SizedBox(height: 20),
                ];
                if (!largo) {
                  return ListView(padding: const EdgeInsets.all(16), children: [
                    ...topo,
                    if (precisa != null) ...[precisa, const SizedBox(height: 16)],
                    _mapa(280),
                    const SizedBox(height: 20),
                    _secaoRotas(),
                    if (juntando != null) ...[const SizedBox(height: 8), juntando],
                    const SizedBox(height: 8),
                    _acerto(),
                  ]);
                }
                return ListView(padding: const EdgeInsets.fromLTRB(32, 24, 32, 48), children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1440),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        ...topo,
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(
                            flex: 11,
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              _mapa(440),
                              const SizedBox(height: 20),
                              if (juntando != null) juntando,
                            ]),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            flex: 9,
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              if (precisa != null) ...[precisa, const SizedBox(height: 20)],
                              _secaoRotas(),
                            ]),
                          ),
                        ]),
                        const SizedBox(height: 20),
                        _acerto(),
                      ]),
                    ),
                  ),
                ]);
              }),
            ),
    );
  }
}
