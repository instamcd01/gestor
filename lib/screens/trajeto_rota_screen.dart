import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as osm;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Trajeto de uma rota do entregador por oferta (26/11): o caminho que o motoboy fez (posições que o
/// Kitsune manda durante a rota), as paradas, os horários e a distância percorrida.
///
/// O Kitsune no navegador só manda posição com o app na frente: quando o motoboy abre o Maps/Waze ou
/// apaga a tela, fica um buraco — a tela liga os pontos em linha reta e avisa os buracos.
/// [demo] = dados de exemplo da bancada (mesmo formato do banco).
class TrajetoRotaScreen extends StatefulWidget {
  final String rotaId;
  final String titulo;
  final Map<String, dynamic>? demo;
  const TrajetoRotaScreen({super.key, required this.rotaId, required this.titulo, this.demo});

  @override
  State<TrajetoRotaScreen> createState() => _TrajetoRotaScreenState();
}

class _Ponto {
  final ll.LatLng p;
  final DateTime em;
  _Ponto(this.p, this.em);
}

class _Parada {
  final int ordem;
  final String numero;
  final String cliente;
  final String status;
  final ll.LatLng? p;
  final DateTime? chegou;
  _Parada(this.ordem, this.numero, this.cliente, this.status, this.p, this.chegou);
}

class _TrajetoRotaScreenState extends State<TrajetoRotaScreen> {
  bool _carregando = true;
  String? _erro;
  List<_Ponto> _pontos = [];
  List<_Parada> _paradas = [];
  ll.LatLng? _loja;
  DateTime? _aceita, _chegouLoja, _saiu, _fim;
  String? _motoboy;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  static DateTime? _dt(dynamic v) => v == null ? null : DateTime.tryParse(v as String)?.toLocal();

  Future<void> _carregar() async {
    try {
      Map<String, dynamic> d;
      if (widget.demo != null) {
        d = widget.demo!;
      } else {
        final db = Supabase.instance.client;
        final r = await db
            .from('rotas_entrega')
            .select('empresa_id, aceita_em, chegou_loja_em, saiu_em, finalizada_em, entregador:entregadores(nome), '
                'rota_pedidos(ordem, chegou_cliente_em, pedido:pedidos(numero_sequencial, status, cliente:clientes(nome, latitude, longitude)))')
            .eq('id', widget.rotaId)
            .single();
        final pos = await db.from('entregador_posicoes').select('lat, lon, em').eq('rota_id', widget.rotaId).order('em').limit(5000);
        final loja = await db.from('empresas').select('latitude, longitude').eq('id', r['empresa_id'] as String).maybeSingle();
        d = {'rota': r, 'posicoes': pos, 'loja': loja};
      }
      final r = Map<String, dynamic>.from(d['rota'] as Map);
      final loja = d['loja'] as Map?;
      setState(() {
        _aceita = _dt(r['aceita_em']);
        _chegouLoja = _dt(r['chegou_loja_em']);
        _saiu = _dt(r['saiu_em']);
        _fim = _dt(r['finalizada_em']);
        _motoboy = ((r['entregador'] as Map?)?['nome'] as String?)?.split(' ').first;
        final lat = (loja?['latitude'] as num?)?.toDouble(), lon = (loja?['longitude'] as num?)?.toDouble();
        _loja = lat == null || lon == null ? null : ll.LatLng(lat, lon);
        _pontos = [
          for (final p in (d['posicoes'] as List? ?? const []))
            if (p['lat'] != null && p['lon'] != null)
              _Ponto(ll.LatLng((p['lat'] as num).toDouble(), (p['lon'] as num).toDouble()), _dt(p['em']) ?? DateTime.now()),
        ];
        final rps = [...(r['rota_pedidos'] as List? ?? const [])]
          ..sort((a, b) => ((a['ordem'] as num?) ?? 0).compareTo((b['ordem'] as num?) ?? 0));
        _paradas = [
          for (final rp in rps)
            () {
              final p = rp['pedido'] as Map? ?? const {};
              final c = p['cliente'] as Map? ?? const {};
              final la = (c['latitude'] as num?)?.toDouble(), lo = (c['longitude'] as num?)?.toDouble();
              return _Parada((rp['ordem'] as num?)?.toInt() ?? 0, '${p['numero_sequencial'] ?? '?'}',
                  ((c['nome'] as String?) ?? 'Cliente').split(' ').first, p['status'] as String? ?? '',
                  la == null || lo == null ? null : ll.LatLng(la, lo), _dt(rp['chegou_cliente_em']));
            }(),
        ];
        _carregando = false;
      });
    } catch (e) {
      setState(() {
        _erro = 'Não deu pra carregar o trajeto: $e';
        _carregando = false;
      });
    }
  }

  double _km(ll.LatLng a, ll.LatLng b) {
    const r = 6371.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180, dLon = (b.longitude - a.longitude) * math.pi / 180;
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(a.latitude * math.pi / 180) * math.cos(b.latitude * math.pi / 180) * math.pow(math.sin(dLon / 2), 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  String _h(DateTime? t) => t == null ? '—' : DateFormat('HH:mm').format(t);

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final suave = cores.onSurfaceVariant;
    if (_carregando) return Scaffold(appBar: AppBar(title: Text(widget.titulo)), body: const Center(child: CircularProgressIndicator()));
    if (_erro != null) return Scaffold(appBar: AppBar(title: Text(widget.titulo)), body: Center(child: Text(_erro!)));

    // indo pra loja (antes de sair) × na rua (depois de sair)
    final antes = _saiu == null ? _pontos : _pontos.where((p) => p.em.isBefore(_saiu!)).toList();
    final depois = _saiu == null ? <_Ponto>[] : _pontos.where((p) => !p.em.isBefore(_saiu!)).toList();
    var kmRua = 0.0;
    for (var i = 1; i < depois.length; i++) {
      kmRua += _km(depois[i - 1].p, depois[i].p);
    }
    final buracos = <(DateTime, DateTime)>[];
    for (var i = 1; i < _pontos.length; i++) {
      if (_pontos[i].em.difference(_pontos[i - 1].em).inMinutes >= 3) buracos.add((_pontos[i - 1].em, _pontos[i].em));
    }
    final todos = [
      if (_loja != null) _loja!,
      ..._pontos.map((p) => p.p),
      ..._paradas.where((p) => p.p != null).map((p) => p.p!),
    ];

    final eventos = <(DateTime?, String)>[
      (_aceita, 'Aceitou a rota'),
      (_chegouLoja, 'Chegou na loja'),
      (_saiu, 'Saiu com os pedidos'),
      for (final p in _paradas) (p.chegou, 'Chegou no cliente #${p.numero} ${p.cliente}'),
      (_fim, 'Rota encerrada'),
    ];

    Widget mapa() => osm.FlutterMap(
          options: osm.MapOptions(
            initialCenter: _loja ?? (todos.isEmpty ? const ll.LatLng(-22.9, -43.5) : todos.first),
            initialZoom: 13,
            initialCameraFit: todos.length > 1
                ? osm.CameraFit.bounds(bounds: osm.LatLngBounds.fromPoints(todos), padding: const EdgeInsets.all(48), maxZoom: 16)
                : null,
          ),
          children: [
            osm.TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.gestor'),
            osm.PolylineLayer(polylines: [
              if (antes.length > 1)
                osm.Polyline(
                    points: antes.map((p) => p.p).toList(),
                    color: Colors.grey.shade600,
                    strokeWidth: 4,
                    pattern: osm.StrokePattern.dashed(segments: const [8, 6])),
              if (depois.length > 1) osm.Polyline(points: depois.map((p) => p.p).toList(), color: const Color(0xFF1D4ED8), strokeWidth: 5),
            ]),
            osm.MarkerLayer(markers: [
              for (final p in _pontos)
                osm.Marker(
                  point: p.p,
                  width: 10,
                  height: 10,
                  child: Tooltip(
                    message: _h(p.em),
                    child: Container(
                        decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: p.em.isBefore(_saiu ?? DateTime(3000)) ? Colors.grey.shade600 : const Color(0xFF1D4ED8), width: 2))),
                  ),
                ),
              for (final p in _paradas.where((p) => p.p != null))
                osm.Marker(
                  point: p.p!,
                  width: 28,
                  height: 28,
                  child: Tooltip(
                    message: '#${p.numero} ${p.cliente} · chegou ${_h(p.chegou)}',
                    child: Container(
                      decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: const Color(0xFF15803D), width: 3)),
                      alignment: Alignment.center,
                      child: Text('${p.ordem}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: Color(0xFF15803D))),
                    ),
                  ),
                ),
              if (_loja != null)
                osm.Marker(
                  point: _loja!,
                  width: 44,
                  height: 28,
                  child: Container(
                    decoration: BoxDecoration(color: const Color(0xFF1E1E24), borderRadius: BorderRadius.circular(7)),
                    alignment: Alignment.center,
                    child: const Text('LOJA', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                ),
            ]),
            const osm.SimpleAttributionWidget(source: Text('OpenStreetMap')),
          ],
        );

    Widget resumo() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_motoboy == null ? 'Trajeto' : 'Trajeto do $_motoboy', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            [
              if (_saiu != null && _fim != null) '${_fim!.difference(_saiu!).inMinutes} min na rua',
              if (depois.length > 1)
                buracos.any((b) => _saiu != null && b.$2.isAfter(_saiu!))
                    ? '~${kmRua.toStringAsFixed(1).replaceAll('.', ',')} km (aproximado: trecho sem GPS em linha reta)'
                    : '~${kmRua.toStringAsFixed(1).replaceAll('.', ',')} km percorridos',
              '${_pontos.length} posições',
            ].join(' · '),
            style: TextStyle(color: suave),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 14, runSpacing: 4, children: [
            _legenda(Colors.grey.shade600, 'indo pra loja'),
            _legenda(const Color(0xFF1D4ED8), 'com os pedidos'),
            _legenda(const Color(0xFF15803D), 'entregas'),
          ]),
          if (_pontos.isEmpty) ...[
            const SizedBox(height: 12),
            Text('O Kitsune não mandou nenhuma posição nesta rota (localização desligada ou app fechado).',
                style: TextStyle(color: cores.error, fontWeight: FontWeight.w600)),
          ],
          if (buracos.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Sem posição ${buracos.map((b) => 'das ${_h(b.$1)} às ${_h(b.$2)}').join(', ')}: o Kitsune estava em segundo plano '
              '(Maps/Waze aberto ou tela apagada). Nesses trechos o mapa liga os pontos em linha reta.',
              style: TextStyle(fontSize: 13, color: Colors.orange.shade900),
            ),
          ],
          const SizedBox(height: 16),
          for (final (t, txt) in eventos)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(width: 52, child: Text(_h(t), style: const TextStyle(fontWeight: FontWeight.w800))),
                Expanded(child: Text(txt, style: TextStyle(color: t == null ? suave : null))),
              ]),
            ),
        ]);

    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      body: LayoutBuilder(builder: (context, c) {
        if (c.maxWidth >= 1000) {
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(flex: 3, child: mapa()),
            SizedBox(width: 380, child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: resumo())),
          ]);
        }
        return ListView(children: [
          SizedBox(height: 380, child: mapa()),
          Padding(padding: const EdgeInsets.all(16), child: resumo()),
        ]);
      }),
    );
  }

  Widget _legenda(Color cor, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 16, height: 4, color: cor),
        const SizedBox(width: 6),
        Text(t, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]);
}
