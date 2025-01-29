// import 'dart:convert';
// import 'package:http/http.dart' as http;
//
// class ProdutoService {
//   static const String _apiKey = "SUA_API_KEY"; // Substitua pela sua chave de API
//
//   Future<Map<String, String>> buscarProdutoPorCodigoBarras(String codigoBarras) async {
//     final url = Uri.parse('https://api.upcitemdb.com/prod/trial/lookup?upc=$codigoBarras');
//     try {
//       final response = await http.get(url, headers: {'Authorization': _apiKey});
//       if (response.statusCode == 200) {
//         final dados = jsonDecode(response.body);
//         if (dados['items'] != null && dados['items'].isNotEmpty) {
//           final item = dados['items'][0];
//           return {
//             'imagemUrl': item['images'] != null && item['images'].isNotEmpty
//                 ? item['images'][0]
//                 : '',
//             'descricao': item['title'] ?? '',
//           };
//         }
//       }
//     } catch (e) {
//       print('Erro ao buscar produto: $e');
//     }
//     return {'imagemUrl': '', 'descricao': ''}; // Retorna valores vazios se não encontrar
//   }
// }
