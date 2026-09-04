import '../distancia_service.dart' show EnderecoEncontrado, RotaCalculada, RotaOtimizadaCalculada;

/// Stub pra plataformas nativas (Android/iOS) — nunca chamado de verdade,
/// já que o DistanciaService só invoca essas funções quando kIsWeb é true.
/// Existe só pra satisfazer o import condicional: a implementação real
/// (distancia_maps_web.dart) usa dart:js_interop, que não compila fora do
/// alvo web.
Future<RotaCalculada?> calcularRotaViaJs({
  required String origem,
  required String destino,
}) async =>
    null;

Future<RotaOtimizadaCalculada?> calcularRotaOrdemFixaViaJs({
  required String origem,
  required List<String> destinosNaOrdem,
}) async =>
    null;

Future<List<List<double>>?> buscarMatrizDistanciasViaJs(List<String> pontos) async => null;

Future<({double lat, double lng})?> geocodificarParaCoordenadasViaJs(String endereco) async => null;

Future<EnderecoEncontrado?> buscarEnderecoPorEnderecoViaJs(
  String endereco, {
  String region = 'br',
}) async =>
    null;

Future<EnderecoEncontrado?> buscarEnderecoPorCoordenadasViaJs(
  double latitude,
  double longitude,
) async =>
    null;
