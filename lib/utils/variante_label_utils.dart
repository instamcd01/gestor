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

/// Nome amigável do eixo de variação (`tipo_variacao`) — usado nos filtros
/// e telas que listam/editam sugestões e famílias de variante. Fallback
/// (capitaliza o valor cru) cobre eixos novos que o banco venha a detectar
/// sem precisar mexer aqui.
String rotuloTipoVariacao(String tipo) {
  switch (tipo) {
    case 'peso':
      return 'Peso';
    case 'volume':
      return 'Volume';
    case 'dose':
      return 'Dose';
    case 'sabor':
      return 'Sabor';
    case 'apresentacao':
      return 'Apresentação';
    default:
      return tipo.isEmpty ? 'Outro' : tipo[0].toUpperCase() + tipo.substring(1);
  }
}
