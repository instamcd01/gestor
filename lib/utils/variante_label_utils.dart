import '../models/produto.dart';

/// Peso pra exibição, nunca o `double` cru (`4.0` vira "4.0kg" ao interpolar
/// direto, `0.06` vira "0.06kg" em vez de "60g" — bug real achado revisando
/// sugestões de variante). Mesma convenção usada no catálogo do site
/// (gestor-loja `formatarPeso`): abaixo de 1kg mostra em gramas, senão em
/// kg com vírgula e sem zero decimal à toa (`1kg`, não `1,0kg`).
String formatarPeso(double valor) {
  if (valor < 1) return '${(valor * 1000).round()}g';
  return '${_semZeroDecimal(valor)}kg';
}

String _semZeroDecimal(double valor) =>
    valor % 1 == 0 ? valor.toInt().toString() : valor.toStringAsFixed(1).replaceAll('.', ',');

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
      return produto.peso != null ? formatarPeso(produto.peso!) : '';
    case 'volume':
      return produto.volume != null ? '${_semZeroDecimal(produto.volume!)}ml' : '';
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
