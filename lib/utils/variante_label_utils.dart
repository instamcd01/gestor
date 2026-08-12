import '../models/produto.dart';

/// Rótulo padrão de uma variante quando o produto ainda não tem
/// `variante_label` definido — tenta um valor razoável a partir do campo
/// estruturado correspondente ao eixo detectado (peso/dose/sabor...).
/// Usado tanto no diálogo de revisão individual quanto na aprovação em
/// massa (sugestões estruturadas), pra manter o mesmo critério nos dois
/// fluxos.
String labelPadraoVariante(Produto produto, String tipoVariacao) {
  if (produto.varianteLabel != null && produto.varianteLabel!.isNotEmpty) {
    return produto.varianteLabel!;
  }
  switch (tipoVariacao) {
    case 'peso':
      return produto.peso != null ? '${produto.peso}kg' : '';
    case 'volume':
      return produto.volume != null ? '${produto.volume}ml' : '';
    case 'dose':
      return produto.dose ?? '';
    case 'sabor':
      return produto.sabor ?? '';
    case 'apresentacao':
      return produto.apresentacao ?? '';
    default:
      return '';
  }
}
