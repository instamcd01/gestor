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

/// Resultado de uma rota com múltiplas paradas — usado pela Fase 2 do
/// custo real por venda quando o entregador leva vários pedidos de uma vez
/// (ver rotas_entrega_screen.dart).
class RotaOtimizadaCalculada {
  /// Índices dos destinos originais, na ordem de visita (ex: [2, 0, 1] =
  /// visitar o 3º endereço da lista original primeiro). Só preenchido pela
  /// busca automática (calcularRotaOtimizada) — depois de um reordenamento
  /// manual, quem chama calcularRotaOrdemFixa já sabe a ordem, não precisa
  /// dela de volta.
  final List<int>? ordemOtimizada;
  /// Distância "cobrável": loja → parada 1 → ... → última parada, SEM a
  /// perna de volta pra loja — é o que entra na conta de custo por km
  /// (empresa cobra a entrega, não o trajeto de volta do entregador).
  final double distanciaCobravelKm;
  /// Só a perna final (última parada → loja) — separada pra quem quiser
  /// ver o total rodado de verdade (cobrável + volta), sem misturar isso
  /// na cobrança.
  final double distanciaVoltaKm;
  final int duracaoTotalMin;
  /// Polyline codificada (formato padrão do Google) do trajeto real,
  /// pronta pra desenhar no mapa — ver rota_mapa_screen.dart.
  final String? polylineCodificada;

  RotaOtimizadaCalculada({
    this.ordemOtimizada,
    required this.distanciaCobravelKm,
    required this.distanciaVoltaKm,
    required this.duracaoTotalMin,
    this.polylineCodificada,
  });

  double get distanciaTotalComVoltaKm => distanciaCobravelKm + distanciaVoltaKm;
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

  /// Acha a ordem de visita que minimiza a distância TOTAL de ida-e-volta
  /// (sai da loja, visita cada destino, volta pra loja) — usa a Distance
  /// Matrix API pra montar a matriz de distância real entre todos os
  /// pontos, e busca exaustiva sobre as permutações dos destinos (até 8
  /// pontos — o suficiente pra qualquer rota real de entrega; instantâneo
  /// mesmo no pior caso, 8! = 40320 combinações). **Importante**: isso é
  /// diferente de pedir `optimize:true` na Directions API — aquele
  /// endpoint otimiza por TEMPO de viagem, não por distância (confirmado
  /// na documentação oficial do Google), o que não bate com uma cobrança
  /// baseada em km rodado. Retorna null com menos de 2 destinos (nada a
  /// otimizar), mais de 8 (foge do escopo de busca exaustiva — quem chama
  /// cai pro fluxo manual) ou se a API falhar.
  static Future<RotaOtimizadaCalculada?> calcularRotaOtimizada({
    required String origem,
    required List<String> destinos,
  }) async {
    if (origem.trim().isEmpty || destinos.length < 2 || destinos.length > 8) return null;

    final matriz = await _buscarMatrizDistancias([origem, ...destinos]);
    if (matriz == null) return null;

    final ordem = _melhorOrdemPorDistancia(matriz, destinos.length);
    if (ordem == null) return null;

    final destinosNaOrdem = ordem.map((i) => destinos[i]).toList();
    final rotaFixa = await calcularRotaOrdemFixa(origem: origem, destinosNaOrdem: destinosNaOrdem);
    if (rotaFixa == null) return null;

    return RotaOtimizadaCalculada(
      ordemOtimizada: ordem,
      distanciaCobravelKm: rotaFixa.distanciaCobravelKm,
      distanciaVoltaKm: rotaFixa.distanciaVoltaKm,
      duracaoTotalMin: rotaFixa.duracaoTotalMin,
      polylineCodificada: rotaFixa.polylineCodificada,
    );
  }

  /// Calcula distância/duração/trajeto real pra uma ordem de visita JÁ
  /// DECIDIDA (seja pelo cálculo automático acima, seja por reordenamento
  /// manual do usuário na tela) — via Directions API, sem `optimize:true`
  /// (a ordem já vem pronta, não pede pro Google escolher). Também traz a
  /// polyline do trajeto real, pra desenhar no mapa.
  static Future<RotaOtimizadaCalculada?> calcularRotaOrdemFixa({
    required String origem,
    required List<String> destinosNaOrdem,
  }) async {
    if (origem.trim().isEmpty || destinosNaOrdem.isEmpty) return null;

    if (kIsWeb) {
      return maps_web.calcularRotaOrdemFixaViaJs(origem: origem, destinosNaOrdem: destinosNaOrdem);
    }

    try {
      final uri = Uri.https('maps.googleapis.com', '/maps/api/directions/json', {
        'origin': origem,
        'destination': origem,
        if (destinosNaOrdem.length > 1) 'waypoints': destinosNaOrdem.join('|'),
        'mode': 'driving',
        'units': 'metric',
        'key': _apiKey,
      });

      final resposta = await http.get(uri).timeout(const Duration(seconds: 15));
      final json = jsonDecode(resposta.body) as Map<String, dynamic>;

      if (json['status'] != 'OK') {
        debugPrint('Directions API status: ${json['status']}');
        return null;
      }

      final rotas = json['routes'] as List;
      if (rotas.isEmpty) return null;
      final rota = rotas.first as Map<String, dynamic>;

      final legs = rota['legs'] as List;
      if (legs.isEmpty) return null;

      var duracaoTotalS = 0;
      var distanciaCobravelM = 0.0;
      for (var i = 0; i < legs.length - 1; i++) {
        final leg = legs[i] as Map<String, dynamic>;
        distanciaCobravelM += (leg['distance']['value'] as num).toDouble();
        duracaoTotalS += (leg['duration']['value'] as num).toInt();
      }
      final ultimaLeg = legs.last as Map<String, dynamic>;
      final distanciaVoltaM = (ultimaLeg['distance']['value'] as num).toDouble();
      duracaoTotalS += (ultimaLeg['duration']['value'] as num).toInt();

      final polyline = (rota['overview_polyline'] as Map<String, dynamic>?)?['points'] as String?;

      return RotaOtimizadaCalculada(
        distanciaCobravelKm: distanciaCobravelM / 1000,
        distanciaVoltaKm: distanciaVoltaM / 1000,
        duracaoTotalMin: (duracaoTotalS / 60).round(),
        polylineCodificada: polyline,
      );
    } catch (e) {
      debugPrint('Erro ao calcular rota de ordem fixa: $e');
      return null;
    }
  }

  /// Matriz NxN de distância real (km) entre todos os pontos, via Distance
  /// Matrix API — 1 chamada só, `pontos` usado como origins E destinations.
  /// `matriz[i][j]` = distância de pontos[i] pra pontos[j].
  static Future<List<List<double>>?> _buscarMatrizDistancias(List<String> pontos) async {
    if (kIsWeb) {
      return maps_web.buscarMatrizDistanciasViaJs(pontos);
    }

    try {
      final pontosStr = pontos.join('|');
      final uri = Uri.https('maps.googleapis.com', '/maps/api/distancematrix/json', {
        'origins': pontosStr,
        'destinations': pontosStr,
        'mode': 'driving',
        'units': 'metric',
        'key': _apiKey,
      });

      final resposta = await http.get(uri).timeout(const Duration(seconds: 15));
      final json = jsonDecode(resposta.body) as Map<String, dynamic>;

      if (json['status'] != 'OK') {
        debugPrint('Distance Matrix API status: ${json['status']}');
        return null;
      }

      final linhas = json['rows'] as List;
      final matriz = <List<double>>[];
      for (final linhaRaw in linhas) {
        final elementos = (linhaRaw as Map<String, dynamic>)['elements'] as List;
        final linha = <double>[];
        for (final elRaw in elementos) {
          final el = elRaw as Map<String, dynamic>;
          if (el['status'] != 'OK') return null;
          linha.add((el['distance']['value'] as num).toDouble() / 1000);
        }
        matriz.add(linha);
      }
      return matriz;
    } catch (e) {
      debugPrint('Erro ao buscar matriz de distâncias: $e');
      return null;
    }
  }

  /// Busca exaustiva: testa todas as permutações dos `n` destinos (índices
  /// 0..n-1) e devolve a que minimiza a distância total de ida-e-volta
  /// (matriz[0] = origem, matriz[1..n] = destinos, nessa ordem). `n` até 8
  /// já é garantido pelo chamador (calcularRotaOtimizada).
  static List<int>? _melhorOrdemPorDistancia(List<List<double>> matriz, int n) {
    List<int>? melhorOrdem;
    var melhorDistancia = double.infinity;

    void tentar(List<int> ordem) {
      var distancia = matriz[0][ordem.first + 1];
      for (var i = 0; i < ordem.length - 1; i++) {
        distancia += matriz[ordem[i] + 1][ordem[i + 1] + 1];
      }
      distancia += matriz[ordem.last + 1][0];
      if (distancia < melhorDistancia) {
        melhorDistancia = distancia;
        melhorOrdem = List.of(ordem);
      }
    }

    void permutar(List<int> restantes, List<int> atual) {
      if (restantes.isEmpty) {
        tentar(atual);
        return;
      }
      for (var i = 0; i < restantes.length; i++) {
        final proximo = restantes[i];
        final novoRestante = [...restantes.sublist(0, i), ...restantes.sublist(i + 1)];
        permutar(novoRestante, [...atual, proximo]);
      }
    }

    permutar(List.generate(n, (i) => i), []);
    return melhorOrdem;
  }

  /// Geocodifica um endereço em texto pra coordenadas — usado pra colocar
  /// o marcador da loja no mapa da rota (ver rota_mapa_screen.dart), já
  /// que `empresas.latitude/longitude` nem sempre está preenchido.
  static Future<({double lat, double lng})?> geocodificarParaCoordenadas(String endereco) async {
    if (endereco.trim().isEmpty) return null;

    if (kIsWeb) {
      return maps_web.geocodificarParaCoordenadasViaJs(endereco);
    }

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

      final localizacao = (resultados.first
          as Map<String, dynamic>)['geometry']['location'] as Map<String, dynamic>;
      return (lat: (localizacao['lat'] as num).toDouble(), lng: (localizacao['lng'] as num).toDouble());
    } catch (e) {
      debugPrint('Erro ao geocodificar endereço: $e');
      return null;
    }
  }

  /// Decodifica uma polyline no formato padrão do Google (algoritmo
  /// público, ver developers.google.com/maps/documentation/utilities/polylinealgorithm)
  /// pra uma lista de pontos lat/lng — sem depender de pacote externo só
  /// pra isso.
  static List<({double lat, double lng})> decodificarPolyline(String codificada) {
    final pontos = <({double lat, double lng})>[];
    var index = 0;
    var lat = 0;
    var lng = 0;

    while (index < codificada.length) {
      int b;
      var shift = 0, result = 0;
      do {
        b = codificada.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = codificada.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      pontos.add((lat: lat / 1e5, lng: lng / 1e5));
    }
    return pontos;
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
