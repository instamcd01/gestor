import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/supabase_config.dart';
import 'web/distancia_maps_stub.dart' if (dart.library.html) 'web/distancia_maps_web.dart' as maps_web;

class RotaCalculada {
  final double distanciaKm;
  final int duracaoMin;

  RotaCalculada({required this.distanciaKm, required this.duracaoMin});
}

class EnderecoEncontrado {
  final String? rua;
  final String? numero;
  final String? bairro;
  final String? cidade;
  final String? estado;
  final String? cep;

  EnderecoEncontrado({
    this.rua,
    this.numero,
    this.bairro,
    this.cidade,
    this.estado,
    this.cep,
  });
}

/// Calcula distância e tempo de entrega reais (rota de carro, não linha
/// reta) via Google Distance Matrix API. Chave dedicada pra isso — a
/// "Distance Matrix API" (e "Geocoding API", usada pra preencher endereço)
/// precisam estar habilitadas pra essa chave no Google Cloud Console.
class DistanciaService {
  DistanciaService._();

  static const _apiKey = 'AIzaSyDKmbywF7XdgUI3LWJ0-c83-tSaEl5EqPU';

  /// Busca o endereço cadastrado da empresa (Dados da Loja) já formatado
  /// pra usar como origem da rota. Retorna null se a empresa não tiver
  /// endereço suficiente cadastrado.
  static Future<String?> buscarEnderecoEmpresa(String empresaId) async {
    try {
      final data = await supabase
          .from('empresas')
          .select('endereco, cidade, estado, cep')
          .eq('id', empresaId)
          .single();

      return _montarEndereco(
        endereco: data['endereco']?.toString() ?? '',
        cidade: data['cidade']?.toString() ?? '',
        estado: data['estado']?.toString() ?? '',
        cep: data['cep']?.toString() ?? '',
      );
    } catch (e) {
      debugPrint('Erro ao buscar endereço da empresa: $e');
      return null;
    }
  }

  static String? _montarEndereco({
    required String endereco,
    String numero = '',
    String bairro = '',
    required String cidade,
    required String estado,
    required String cep,
  }) {
    final partes = <String>[];
    if (endereco.isNotEmpty) {
      partes.add(numero.isNotEmpty ? '$endereco, $numero' : endereco);
    }
    if (bairro.isNotEmpty) partes.add(bairro);
    if (cidade.isNotEmpty) partes.add(estado.isNotEmpty ? '$cidade - $estado' : cidade);
    if (cep.isNotEmpty) partes.add(cep);

    return partes.isEmpty ? null : partes.join(', ');
  }

  /// Monta o endereço de um cliente a partir dos campos estruturados.
  static String? montarEnderecoCliente({
    required String endereco,
    required String numero,
    required String bairro,
    required String cidade,
    required String estado,
    required String cep,
  }) {
    return _montarEndereco(
      endereco: endereco,
      numero: numero,
      bairro: bairro,
      cidade: cidade,
      estado: estado,
      cep: cep,
    );
  }

  /// Calcula a rota real (de carro) entre dois endereços via Google
  /// Distance Matrix API. Retorna null se algum endereço não puder ser
  /// localizado ou a API falhar — nunca lança exceção, quem chama decide
  /// o que fazer na ausência do resultado (ex: deixar o campo em branco).
  static Future<RotaCalculada?> calcularRota({
    required String origem,
    required String destino,
  }) async {
    if (origem.trim().isEmpty || destino.trim().isEmpty) return null;

    // No navegador, a API REST (chamada abaixo via http.get) não manda
    // cabeçalho CORS — o navegador bloqueia a resposta antes do Dart
    // conseguir lê-la. A biblioteca Google Maps JavaScript (carregada em
    // web/index.html) não tem essa restrição, então usa ela via interop.
    if (kIsWeb) {
      return maps_web.calcularRotaViaJs(origem: origem, destino: destino);
    }

    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/distancematrix/json', {
        'origins': origem,
        'destinations': destino,
        'mode': 'driving',
        'units': 'metric',
        'key': _apiKey,
      });

      final resposta = await http.get(uri).timeout(const Duration(seconds: 10));
      final json = jsonDecode(resposta.body) as Map<String, dynamic>;

      if (json['status'] != 'OK') {
        debugPrint('Distance Matrix API status: ${json['status']}');
        return null;
      }

      final elemento = json['rows'][0]['elements'][0] as Map<String, dynamic>;
      if (elemento['status'] != 'OK') {
        debugPrint('Distance Matrix API elemento status: ${elemento['status']}');
        return null;
      }

      final distanciaMetros = (elemento['distance']['value'] as num).toDouble();
      final duracaoSegundos = (elemento['duration']['value'] as num).toDouble();

      return RotaCalculada(
        distanciaKm: distanciaMetros / 1000,
        duracaoMin: (duracaoSegundos / 60).round(),
      );
    } catch (e) {
      debugPrint('Erro ao calcular rota: $e');
      return null;
    }
  }

  /// Preenche bairro/cidade/estado/CEP automaticamente a partir da
  /// rua + número, via Google Geocoding API — usado nos formulários de
  /// cliente pra poupar o usuário de digitar o endereço inteiro. Retorna
  /// null se não achar nada (endereço ambíguo, rua não localizada, etc.);
  /// quem chama só preenche os campos que ainda estiverem vazios.
  static Future<EnderecoEncontrado?> buscarEnderecoPorRuaNumero({
    required String rua,
    required String numero,
    String? cidadeReferencia,
    String? estadoReferencia,
  }) async {
    if (rua.trim().isEmpty) return null;

    final partes = [
      numero.trim().isNotEmpty ? '${rua.trim()}, ${numero.trim()}' : rua.trim(),
      if ((cidadeReferencia ?? '').isNotEmpty) cidadeReferencia!.trim(),
      if ((estadoReferencia ?? '').isNotEmpty) estadoReferencia!.trim(),
      'Brasil',
    ];
    final enderecoCompleto = partes.join(', ');

    if (kIsWeb) {
      return maps_web.buscarEnderecoPorEnderecoViaJs(enderecoCompleto, region: 'br');
    }

    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'address': enderecoCompleto,
        'region': 'br',
        'key': _apiKey,
      });

      final resposta = await http.get(uri).timeout(const Duration(seconds: 10));
      final json = jsonDecode(resposta.body) as Map<String, dynamic>;

      if (json['status'] != 'OK') {
        debugPrint('Geocoding API status: ${json['status']}');
        return null;
      }

      final resultados = json['results'] as List;
      if (resultados.isEmpty) return null;

      return _parseComponentes(resultados.first['address_components'] as List);
    } catch (e) {
      debugPrint('Erro ao buscar endereço por rua/número: $e');
      return null;
    }
  }

  /// Descobre o endereço a partir de coordenadas (geocodificação reversa)
  /// — usado depois que o usuário escolhe um ponto no mapa manualmente,
  /// pra desambiguar ruas com nome repetido/numérico.
  static Future<EnderecoEncontrado?> buscarEnderecoPorCoordenadas({
    required double latitude,
    required double longitude,
  }) async {
    if (kIsWeb) {
      return maps_web.buscarEnderecoPorCoordenadasViaJs(latitude, longitude);
    }

    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/geocode/json', {
        'latlng': '$latitude,$longitude',
        'key': _apiKey,
      });

      final resposta = await http.get(uri).timeout(const Duration(seconds: 10));
      final json = jsonDecode(resposta.body) as Map<String, dynamic>;

      if (json['status'] != 'OK') {
        debugPrint('Geocoding API (reversa) status: ${json['status']}');
        return null;
      }

      final resultados = json['results'] as List;
      if (resultados.isEmpty) return null;

      return _parseComponentes(resultados.first['address_components'] as List);
    } catch (e) {
      debugPrint('Erro ao buscar endereço por coordenadas: $e');
      return null;
    }
  }

  static EnderecoEncontrado _parseComponentes(List componentes) {
    String? extrairComponente(List<String> tiposPrioridade, {bool sigla = false}) {
      for (final tipoAlvo in tiposPrioridade) {
        for (final componente in componentes) {
          final tipos = List<String>.from(componente['types'] as List);
          if (tipos.contains(tipoAlvo)) {
            return (sigla ? componente['short_name'] : componente['long_name']) as String?;
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
}
