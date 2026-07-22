import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

/// Tela pra escolher a localização exata de um cliente no mapa — usada
/// quando o endereço por texto é ambíguo (ruas com nome repetido/numérico,
/// tipo "Rua 7", que existem em vários bairros da mesma cidade). O usuário
/// arrasta o pino ou busca um endereço, e a tela devolve as coordenadas
/// exatas escolhidas.
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
  LatLng _posicaoSelecionada = _posicaoPadrao;
  bool _carregandoBusca = false;
  bool _localizando = true;

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
        _mapController?.moveCamera(CameraUpdate.newLatLng(encontrado));
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

    setState(() => _posicaoSelecionada = encontrado);
    _mapController?.animateCamera(CameraUpdate.newLatLngZoom(encontrado, 17));
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Selecionar Localização'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _posicaoSelecionada),
            child: const Text('Confirmar'),
          ),
        ],
      ),
      body: _localizando
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(target: _posicaoSelecionada, zoom: 16),
                  onMapCreated: (controller) => _mapController = controller,
                  onTap: (posicao) => setState(() => _posicaoSelecionada = posicao),
                  markers: {
                    Marker(
                      markerId: const MarkerId('local-selecionado'),
                      position: _posicaoSelecionada,
                      draggable: true,
                      onDragEnd: (posicao) => setState(() => _posicaoSelecionada = posicao),
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
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, size: 18, color: Colors.grey),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Toque no mapa ou arraste o pino até o ponto certo.',
                              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
