import 'package:url_launcher/url_launcher.dart';

/// Busca de um produto nos marketplaces já ordenada pelo menor preço — o preço
/// e o frete grátis mudam o tempo todo, então o link salvo do anúncio não
/// basta pra saber onde está mais barato hoje (pedido do Lucas, 20/11/2026).
class BuscaMarketplace {
  /// Termo de busca a partir do nome do produto: tira o que atrapalha a busca
  /// (parênteses, "un", códigos) e limita o tamanho.
  static String termo(String nomeProduto) {
    var t = nomeProduto
        .replaceAll(RegExp(r'\(.*?\)'), ' ')
        .replaceAll(RegExp(r'[^\p{L}\p{N}\s,.-]', unicode: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final palavras = t.split(' ');
    if (palavras.length > 8) t = palavras.take(8).join(' ');
    return t;
  }

  /// Shopee: menor preço primeiro.
  static Uri shopee(String nomeProduto) => Uri.parse(
      'https://shopee.com.br/search?keyword=${Uri.encodeQueryComponent(termo(nomeProduto))}&order=asc&sortBy=price');

  /// Mercado Livre: menor preço primeiro, só com frete grátis.
  static Uri mercadoLivre(String nomeProduto) {
    final slug = termo(nomeProduto).toLowerCase().replaceAll(RegExp(r'[\s,.]+'), '-');
    return Uri.parse('https://lista.mercadolivre.com.br/${Uri.encodeComponent(slug)}_CustoFrete_Gratis_OrderId_PRICE_NoIndex_True');
  }

  static Future<bool> abrir(Uri uri) => launchUrl(uri, mode: LaunchMode.externalApplication);
}
