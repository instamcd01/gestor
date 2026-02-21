import 'dart:convert';
import 'package:http/http.dart' as http;

/// Busca imagem de produto usando OpenFoodFacts pelo código de barras
Future<String?> buscarImagemProdutoPetPorCodigoBarras(String codigoBarras) async {
  try {
    final url = Uri.parse('https://world.openfoodfacts.org/api/v0/product/$codigoBarras.json');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['status'] == 1) {
        final product = data['product'];
        // Tenta pegar imagem do produto
        final imageUrl = product['image_front_small_url'] ?? product['image_front_url'];
        if (imageUrl != null && imageUrl.isNotEmpty) {
          return imageUrl;
        }
      }
    }
    return null;
  } catch (e) {
    print("Erro ao buscar imagem do produto pelo código de barras: $e");
    return null;
  }
}
