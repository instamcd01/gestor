import 'dart:js_interop';

import 'package:google_maps/google_maps_core.dart';
import 'package:google_maps/google_maps_geocoding.dart';
import 'package:google_maps/google_maps_routes.dart';

import '../distancia_service.dart' show EnderecoEncontrado, RotaCalculada, RotaOtimizadaCalculada;

/// Implementação real, usada só quando compilando pra web — chama a Google
/// Maps JavaScript API (já carregada em web/index.html) via interop, em vez
/// do endpoint REST usado por http.get() no resto do DistanciaService. O
/// endpoint REST não manda cabeçalho CORS, então o navegador bloqueia a
/// resposta; a biblioteca JS roda dentro da própria origem do Google e não
/// tem essa restrição.
Future<RotaCalculada?> calcularRotaViaJs({
  required String origem,
  required String destino,
}) async {
  try {
    final response = await DistanceMatrixService().getDistanceMatrix(
      DistanceMatrixRequest(
        origins: <JSAny>[origem.toJS].toJS,
        destinations: <JSAny>[destino.toJS].toJS,
        travelMode: TravelMode.DRIVING,
        unitSystem: UnitSystem.METRIC,
      ),
    );
    if (response.rows.isEmpty) return null;
    final elementos = response.rows.first.elements;
    if (elementos.isEmpty) return null;

    final elemento = elementos.first;
    if (elemento.status != DistanceMatrixElementStatus.OK) return null;

    return RotaCalculada(
      distanciaKm: elemento.distance.value / 1000,
      duracaoMin: (elemento.duration.value / 60).round(),
    );
  } catch (_) {
    return null;
  }
}

/// Ordem de visita já decidida (busca automática por distância feita em
/// Dart puro, ver DistanciaService._melhorOrdemPorDistancia) — só busca o
/// trajeto real (legs/polyline) pra essa ordem fixa, sem optimizeWaypoints
/// (esse otimiza por TEMPO, não por distância, então nunca serve aqui).
Future<RotaOtimizadaCalculada?> calcularRotaOrdemFixaViaJs({
  required String origem,
  required List<String> destinosNaOrdem,
}) async {
  try {
    final response = await DirectionsService().route(
      DirectionsRequest(
        origin: origem.toJS,
        destination: origem.toJS,
        travelMode: TravelMode.DRIVING,
        waypoints: destinosNaOrdem
            .map((d) => DirectionsWaypoint(location: d.toJS, stopover: true))
            .toList()
            .toJS,
      ),
    );
    if (response.routes.isEmpty) return null;
    final rota = response.routes.first;
    final legs = rota.legs;
    if (legs.isEmpty) return null;

    var distanciaCobravelM = 0.0;
    var duracaoTotalS = 0;
    for (var i = 0; i < legs.length - 1; i++) {
      distanciaCobravelM += legs[i].distance?.value.toDouble() ?? 0;
      duracaoTotalS += legs[i].duration?.value.toInt() ?? 0;
    }
    final ultimaLeg = legs.last;
    final distanciaVoltaM = ultimaLeg.distance?.value.toDouble() ?? 0;
    duracaoTotalS += ultimaLeg.duration?.value.toInt() ?? 0;

    return RotaOtimizadaCalculada(
      distanciaCobravelKm: distanciaCobravelM / 1000,
      distanciaVoltaKm: distanciaVoltaM / 1000,
      duracaoTotalMin: (duracaoTotalS / 60).round(),
      polylineCodificada: rota.overviewPolyline,
    );
  } catch (_) {
    return null;
  }
}

/// Matriz NxN de distância real (km) entre todos os `pontos` — usa a mesma
/// DistanceMatrixService de calcularRotaViaJs, só que com todos os pontos
/// como origins E destinations de uma vez.
Future<List<List<double>>?> buscarMatrizDistanciasViaJs(List<String> pontos) async {
  try {
    final pontosJs = pontos.map((p) => p.toJS as JSAny).toList().toJS;
    final response = await DistanceMatrixService().getDistanceMatrix(
      DistanceMatrixRequest(
        origins: pontosJs,
        destinations: pontosJs,
        travelMode: TravelMode.DRIVING,
        unitSystem: UnitSystem.METRIC,
      ),
    );
    if (response.rows.length != pontos.length) return null;

    final matriz = <List<double>>[];
    for (final row in response.rows) {
      if (row.elements.length != pontos.length) return null;
      final linha = <double>[];
      for (final el in row.elements) {
        if (el.status != DistanceMatrixElementStatus.OK) return null;
        linha.add(el.distance.value / 1000);
      }
      matriz.add(linha);
    }
    return matriz;
  } catch (_) {
    return null;
  }
}

Future<({double lat, double lng})?> geocodificarParaCoordenadasViaJs(String endereco) async {
  try {
    final response = await Geocoder().geocode(GeocoderRequest(address: endereco, region: 'br'));
    if (response.results.isEmpty) return null;
    final localizacao = response.results.first.geometry.location;
    return (lat: localizacao.lat.toDouble(), lng: localizacao.lng.toDouble());
  } catch (_) {
    return null;
  }
}

Future<EnderecoEncontrado?> buscarEnderecoPorEnderecoViaJs(
  String endereco, {
  String region = 'br',
}) async {
  try {
    final response = await Geocoder().geocode(
      GeocoderRequest(address: endereco, region: region),
    );
    if (response.results.isEmpty) return null;
    return _parseComponentes(response.results.first.addressComponents);
  } catch (_) {
    return null;
  }
}

Future<EnderecoEncontrado?> buscarEnderecoPorCoordenadasViaJs(
  double latitude,
  double longitude,
) async {
  try {
    final response = await Geocoder().geocode(
      GeocoderRequest(location: LatLngLiteral(lat: latitude, lng: longitude)),
    );
    if (response.results.isEmpty) return null;
    return _parseComponentes(response.results.first.addressComponents);
  } catch (_) {
    return null;
  }
}

EnderecoEncontrado _parseComponentes(List<GeocoderAddressComponent> componentes) {
  String? extrairComponente(List<String> tiposPrioridade, {bool sigla = false}) {
    for (final tipoAlvo in tiposPrioridade) {
      for (final componente in componentes) {
        if (componente.types.contains(tipoAlvo)) {
          return sigla ? componente.shortName : componente.longName;
        }
      }
    }
    return null;
  }

  return EnderecoEncontrado(
    rua: extrairComponente(['route']),
    numero: extrairComponente(['street_number']),
    bairro: extrairComponente(['sublocality_level_1', 'sublocality', 'neighborhood']),
    cidade: extrairComponente(['locality', 'administrative_area_level_2']),
    estado: extrairComponente(['administrative_area_level_1'], sigla: true),
    cep: extrairComponente(['postal_code']),
  );
}
