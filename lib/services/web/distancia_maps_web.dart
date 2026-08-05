import 'dart:js_interop';

import 'package:google_maps/google_maps_core.dart';
import 'package:google_maps/google_maps_geocoding.dart';
import 'package:google_maps/google_maps_routes.dart';

import '../distancia_service.dart' show EnderecoEncontrado, RotaCalculada;

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
