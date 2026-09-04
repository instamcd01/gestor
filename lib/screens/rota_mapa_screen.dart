import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';

import '../models/rota_entrega.dart';
import '../models/venda.dart';
import '../providers/auth_provider.dart';
import '../services/distancia_service.dart';

/// Mostra no mapa a rota calculada (ou reordenada manualmente) — loja
/// marcada + uma parada por pedido, numeradas na ordem de visita, com o
/// trajeto real desenhado (mesma polyline usada pra calcular a distância).
/// Só é possível abrir depois que alguma distância já foi calculada
/// (rota.polylineEstimada != null), ver botão "Ver no mapa" em
/// rotas_entrega_screen.dart.
class RotaMapaScreen extends StatefulWidget {
  final RotaEntrega rota;
  final List<Venda?> vendas;

  const RotaMapaScreen({super.key, required this.rota, required this.vendas});

  @override
  State<RotaMapaScreen> createState() => _RotaMapaScreenState();
}

class _RotaMapaScreenState extends State<RotaMapaScreen> {
  bool _carregando = true;
  String? _erro;
  final _markers = <Marker>{};
  final _polylines = <Polyline>{};
  LatLngBounds? _bounds;
  GoogleMapController? _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _montarMapa());
  }

  Future<void> _montarMapa() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) {
      setState(() {
        _erro = 'Empresa não identificada.';
        _carregando = false;
      });
      return;
    }

    final enderecoLoja = await DistanciaService.buscarEnderecoEmpresa(empresaId);
    final coordenadasLoja =
        enderecoLoja != null ? await DistanciaService.geocodificarParaCoordenadas(enderecoLoja) : null;
    if (coordenadasLoja == null) {
      setState(() {
        _erro = 'Não foi possível localizar o endereço da loja no mapa.';
        _carregando = false;
      });
      return;
    }

    final pontosLat = <double>[];
    final pontosLng = <double>[];

    void registrarPonto(double lat, double lng) {
      pontosLat.add(lat);
      pontosLng.add(lng);
    }

    final loja = LatLng(coordenadasLoja.lat, coordenadasLoja.lng);
    registrarPonto(loja.latitude, loja.longitude);

    _markers.add(
      Marker(
        markerId: const MarkerId('loja'),
        position: loja,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Loja — início e fim da rota'),
      ),
    );

    for (var i = 0; i < widget.vendas.length; i++) {
      final venda = widget.vendas[i];
      final cliente = venda?.cliente;
      if (cliente == null) continue;

      // Mesmo fallback usado pra calcular a rota (ver
      // rotas_entrega_screen.dart, _destinosDosPedidos): cliente sem
      // lat/lng salvo ainda entra no mapa, só que geocodificando o
      // endereço em texto na hora — sem isso, a parada simplesmente
      // sumia do mapa sem nenhum aviso, mesmo tendo entrado no cálculo
      // da rota normalmente.
      LatLng? posicao;
      if (cliente.latitude != null && cliente.longitude != null) {
        posicao = LatLng(cliente.latitude!, cliente.longitude!);
      } else if (cliente.enderecoCompleto.isNotEmpty) {
        final geocodificado = await DistanciaService.geocodificarParaCoordenadas(cliente.enderecoCompleto);
        if (geocodificado != null) posicao = LatLng(geocodificado.lat, geocodificado.lng);
      }
      if (posicao == null) continue;

      registrarPonto(posicao.latitude, posicao.longitude);

      final ultima = i == widget.vendas.length - 1;
      _markers.add(
        Marker(
          markerId: MarkerId('parada_$i'),
          position: posicao,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            ultima ? BitmapDescriptor.hueRed : BitmapDescriptor.hueAzure,
          ),
          infoWindow: InfoWindow(title: '${i + 1}ª parada', snippet: cliente.nome),
        ),
      );
    }

    if (widget.rota.polylineEstimada != null) {
      final pontos = DistanciaService.decodificarPolyline(widget.rota.polylineEstimada!);
      _polylines.add(
        Polyline(
          polylineId: const PolylineId('rota'),
          points: pontos.map((p) => LatLng(p.lat, p.lng)).toList(),
          color: Colors.blue,
          width: 4,
        ),
      );
    }

    if (pontosLat.isNotEmpty) {
      _bounds = LatLngBounds(
        southwest: LatLng(pontosLat.reduce((a, b) => a < b ? a : b), pontosLng.reduce((a, b) => a < b ? a : b)),
        northeast: LatLng(pontosLat.reduce((a, b) => a > b ? a : b), pontosLng.reduce((a, b) => a > b ? a : b)),
      );
    }

    if (mounted) setState(() => _carregando = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Rota — ${widget.rota.entregadorNome}')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_erro!, textAlign: TextAlign.center)))
              : GoogleMap(
                  initialCameraPosition: CameraPosition(target: _markers.first.position, zoom: 13),
                  markers: _markers,
                  polylines: _polylines,
                  onMapCreated: (controller) {
                    _controller = controller;
                    if (_bounds != null) {
                      // Espera um frame — mover a câmera pros bounds calculados
                      // logo no onMapCreated às vezes não tem efeito porque o
                      // mapa ainda não terminou de medir o próprio tamanho.
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _controller?.animateCamera(CameraUpdate.newLatLngBounds(_bounds!, 60));
                      });
                    }
                  },
                ),
    );
  }
}
