import '../models/margem_alvo_categoria.dart';

/// Resultado do cálculo de preço sugerido: o preço em si e a margem
/// (sobre o preço de venda) que gerou ele — mostrados juntos na tela pra
/// deixar claro de onde veio o número.
class PrecoSugerido {
  final double preco;
  final double margemPercentual;
  const PrecoSugerido({required this.preco, required this.margemPercentual});
}

/// Mesma lógica de `calcular_preco_sugerido()` no banco, em Dart — usada
/// nos formulários de cadastro/edição de produto pra mostrar a sugestão
/// enquanto o usuário ainda está digitando (produto novo nem tem id pra
/// chamar a função do banco ainda). Subcategoria bate primeiro; sem
/// subcategoria bate a linha geral da categoria (`subcategoria == ''`).
PrecoSugerido? calcularPrecoSugerido({
  required List<MargemAlvoCategoria> margens,
  required String categoria,
  String? subcategoria,
  required double custo,
}) {
  if (custo <= 0 || categoria.isEmpty) return null;

  final subcategoriaBusca = subcategoria ?? '';
  double? margem;
  for (final m in margens) {
    if (m.categoria == categoria && m.subcategoria == subcategoriaBusca) {
      margem = m.margemAlvoPercentual;
      break;
    }
  }
  if (margem == null && subcategoriaBusca.isNotEmpty) {
    for (final m in margens) {
      if (m.categoria == categoria && m.subcategoria == '') {
        margem = m.margemAlvoPercentual;
        break;
      }
    }
  }
  if (margem == null) return null;

  final preco = custo / (1 - margem / 100);
  return PrecoSugerido(preco: double.parse(preco.toStringAsFixed(2)), margemPercentual: margem);
}
