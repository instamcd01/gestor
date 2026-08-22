import 'dart:convert';

import 'package:http/http.dart' as http;

/// Gera descrição de produto via IA (workflow n8n "Gestor App - Gerar
/// Descricao Produto"). O resultado só preenche o campo do formulário —
/// quem cadastra ainda revisa e confirma antes de salvar, nunca é
/// aplicado direto no banco por aqui.
class DescricaoProdutoService {
  static const _url = 'https://n8n.lukz.com.br/webhook/gerar-descricao-produto';
  static const _chave = '15a4c4b206cadf1146b1a2f8cbd73127c8bffb286572dce5';

  static Future<String> gerar({
    required String nome,
    String? categoria,
    String? fabricante,
    String? especie,
    String? descricaoAtual,
  }) async {
    final resposta = await http.post(
      Uri.parse(_url),
      headers: {'Content-Type': 'application/json', 'X-Gestor-Key': _chave},
      body: jsonEncode({
        'nome': nome,
        'categoria': categoria,
        'fabricante': fabricante,
        'especie': especie,
        'descricao_atual': descricaoAtual,
      }),
    );

    if (resposta.statusCode != 200) {
      throw Exception('Não foi possível gerar a descrição agora. Tente de novo em instantes.');
    }

    final corpo = jsonDecode(utf8.decode(resposta.bodyBytes)) as Map<String, dynamic>;
    final descricao = corpo['descricao']?.toString();
    if (descricao == null || descricao.isEmpty) {
      throw Exception('A IA não retornou uma descrição.');
    }
    return descricao;
  }
}
