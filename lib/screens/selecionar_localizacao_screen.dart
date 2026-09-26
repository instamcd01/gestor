import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as osm;
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' as ll;

/// Tela pra escolher a localização exata de um cliente no mapa — usada
/// quando o endereço por texto é ambíguo (ruas com nome repetido/numérico,
/// tipo "Rua 7", que existem em vários bairros da mesma cidade). O usuário
/// arrasta o pino ou busca um endereço, e a tela devolve as coordenadas
/// exatas escolhidas.
///
/// No desktop (Windows/macOS/Linux) usa flutter_map + OpenStreetMap:
/// google_maps_flutter só tem implementação pra Android/iOS/web e a tela
/// não abria no app Windows (achado real 26/09). Mesmo mapa do site.
class SelecionarLocalizacaoScreen extends StatefulWidget {
  final LatLng? posicaoInicial;
  final String? enderecoInicial;

  const SelecionarLocalizacaoScreen({super.key, this.posicaoInicial, this.enderecoInicial});

  @override
  State<SelecionarLocalizacaoScreen> createState() => _SelecionarLocalizacaoScreenState();
}

class _SelecionarLocalizacaoScreenState extends State<SelecionarLocalizacaoScreen> {
  static const _apiKey = 'AIzaSyDKmbywF7XdgUI3LWJ0-c83-tSaEl5EqPU';
  static const _posicaoPadrao = LatLng(-23.5505, -46.6333); // São Paulo, só de ponto de partida

  final _buscaController = TextEditingController();
  GoogleMapController? _mapController;
  final _osmController = osm.MapController();
  static final bool _usarMapaOsm = !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
  LatLng _posicaoSelecionada = _posicaoPadrao;
  bool _carregandoBusca = false;
  bool _localizando = true;
  // Mexeu no pino e ainda não confirmou — voltar sem confirmar descarta.
  bool _alterado = false;

  @override
  void initState() {
    super.initState();
    _posicaoSelecionada = widget.posicaoInicial ?? _posicaoPadrao;
    _inicializarPosicao();
  }

  Future<void> _inicializarPosicao() async {
    if (widget.posicaoInicial != null) {
      setState(() => _localizando = false);
      return;
    }
    if ((widget.enderecoInicial ?? '').isNotEmpty) {
      final encontrado = await _geocodificarEndereco(widget.enderecoInicial!);
      if (encontrado != null && mounted) {
        setState(() => _posicaoSelecionada = encontrado);
        _moverCamera(encontrado);
      }
    }
    if (mounted) setState(() => _localizando = false);
  }

  Future<LatLng?> _geocodificarEndereco(String endereco) async {
    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'address': endereco,
        'region': 'br',
        'key': _apiKey,
      });
      final resposta = await http.get(uri).timeout(const Duration(seconds: 10));
      final json = jsonDecode(resposta.body) as Map<String, dynamic>;
      if (json['status'] != 'OK') return null;

      final resultados = json['results'] as List;
      if (resultados.isEmpty) return null;

      final location = resultados.first['geometry']['location'];
      return LatLng((location['lat'] as num).toDouble(), (location['lng'] as num).toDouble());
    } catch (e) {
      debugPrint('Erro ao geocodificar endereço: $e');
      return null;
    }
  }

  Future<void> _buscarEIrParaEndereco() async {
    final texto = _buscaController.text.trim();
    if (texto.isEmpty) return;

    setState(() => _carregandoBusca = true);
    final encontrado = await _geocodificarEndereco(texto);
    if (!mounted) return;
    setState(() => _carregandoBusca = false);

    if (encontrado == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Endereço não encontrado')),
      );
      return;
    }

    setState(() {
      _posicaoSelecionada = encontrado;
      _alterado = true;
    });
    _moverCamera(encontrado, zoom: 17);
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  void _moverCamera(LatLng posicao, {double? zoom}) {
    if (_usarMapaOsm) {
      // Antes do primeiro frame do mapa o controller ainda não existe —
      // nesse caso o initialCenter (vindo de _posicaoSelecionada) já cobre.
      try {
        _osmController.move(ll.LatLng(posicao.latitude, posicao.longitude), zoom ?? _osmController.camera.zoom);
      } catch (_) {}
      return;
    }
    _mapController?.animateCamera(
      zoom != null ? CameraUpdate.newLatLngZoom(posicao, zoom) : CameraUpdate.newLatLng(posicao),
    );
  }

  void _marcar(LatLng posicao) => setState(() {
        _posicaoSelecionada = posicao;
        _alterado = true;
      });

  Widget _buildMapaOsm() {
    final ponto = ll.LatLng(_posicaoSelecionada.latitude, _posicaoSelecionada.longitude);
    return osm.FlutterMap(
      mapController: _osmController,
      options: osm.MapOptions(
        initialCenter: ponto,
        initialZoom: 16,
        onTap: (_, p) => _marcar(LatLng(p.latitude, p.longitude)),
      ),
      children: [
        osm.TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.gestor',
        ),
        osm.MarkerLayer(
          markers: [
            osm.Marker(
              point: ponto,
              width: 40,
              height: 40,
              alignment: Alignment.topCenter,
              child: Icon(Icons.location_on, size: 40, color: Theme.of(context).colorScheme.primary),
            ),
          ],
        ),
        const osm.SimpleAttributionWidget(source: Text('OpenStreetMap')),
      ],
    );
  }

  void _confirmar() => Navigator.pop(context, _posicaoSelecionada);

  /// Voltar depois de mexer no pino, sem confirmar, perdia a escolha em
  /// silêncio — e o "Confirmar" antigo (TextButton na AppBar) ficava
  /// invisível, cor da marca sobre a AppBar da mesma cor (achado real
  /// 26/09: "escolhi no mapa e não salvou").
  Future<void> _aoTentarVoltar() async {
    final acao = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Usar essa localização?'),
        content: const Text('Você mudou o ponto no mapa e ainda não confirmou.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'descartar'), child: const Text('Descartar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'confirmar'), child: const Text('Usar localização')),
        ],
      ),
    );
    if (!mounted) return;
    if (acao == 'confirmar') _confirmar();
    if (acao == 'descartar') Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_alterado,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _aoTentarVoltar();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Selecionar Localização'),
          actions: [
            IconButton(
              tooltip: 'Confirmar localização',
              onPressed: _confirmar,
              icon: const Icon(Icons.check),
            ),
          ],
        ),
        body: _localizando
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  if (_usarMapaOsm)
                    _buildMapaOsm()
                  else
                    GoogleMap(
                      initialCameraPosition: CameraPosition(target: _posicaoSelecionada, zoom: 16),
                      onMapCreated: (controller) => _mapController = controller,
                      onTap: _marcar,
                      markers: {
                        Marker(
                          markerId: const MarkerId('local-selecionado'),
                          position: _posicaoSelecionada,
                          draggable: true,
                          onDragEnd: _marcar,
                        ),
                      },
                    ),
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: Material(
                      elevation: 3,
                      borderRadius: BorderRadius.circular(8),
                      child: TextField(
                        controller: _buscaController,
                        decoration: InputDecoration(
                          hintText: 'Buscar endereço no mapa',
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _carregandoBusca
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : IconButton(
                                  icon: const Icon(Icons.arrow_forward),
                                  onPressed: _buscarEIrParaEndereco,
                                ),
                        ),
                        onSubmitted: (_) => _buscarEIrParaEndereco(),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: SafeArea(
                      top: false,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.info_outline, size: 18, color: Colors.grey),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _usarMapaOsm
                                          ? 'Clique no mapa no ponto certo (roda do mouse dá zoom).'
                                          : 'Toque no mapa ou arraste o pino até o ponto certo.',
                                      style: TextStyle(
                                          fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              FilledButton.icon(
                                onPressed: _confirmar,
                                icon: const Icon(Icons.check),
                                label: const Text('Confirmar localização'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
