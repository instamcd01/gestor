import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class EnderecoPorCep {
  final String rua;
  final String bairro;
  final String cidade;
  final String estado;

  EnderecoPorCep({
    required this.rua,
    required this.bairro,
    required this.cidade,
    required this.estado,
  });
}

/// Busca endereço a partir do CEP via ViaCEP — gratuito, sem chave, e o
/// jeito mais confiável de preencher endereço no Brasil, porque o CEP é
/// único mesmo quando o nome da rua se repete entre bairros/cidades (ex:
/// "Rua 7", muito comum em loteamentos e bairros planejados).
class CepService {
  CepService._();

  static Future<EnderecoPorCep?> buscarPorCep(String cep) async {
    final digitos = cep.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitos.length != 8) return null;

    try {
      final uri = Uri.parse('https://viacep.com.br/ws/$digitos/json/');
      final resposta = await http.get(uri).timeout(const Duration(seconds: 8));
      final json = jsonDecode(resposta.body) as Map<String, dynamic>;

      if (json['erro'] == true) return null;

      return EnderecoPorCep(
        rua: json['logradouro']?.toString() ?? '',
        bairro: json['bairro']?.toString() ?? '',
        cidade: json['localidade']?.toString() ?? '',
        estado: json['uf']?.toString() ?? '',
      );
    } catch (e) {
      debugPrint('Erro ao buscar CEP: $e');
      return null;
    }
  }
}
