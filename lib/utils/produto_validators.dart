/// Regras de validação e parsing dos campos de produto, compartilhadas
/// entre cadastro e edição pra não haver divergência entre as duas telas
/// (foi exatamente essa divergência que causou preços não sendo salvos).
class ProdutoValidators {
  ProdutoValidators._();

  /// Converte texto pra número aceitando vírgula ou ponto como separador
  /// decimal. Use isso em vez de `double.tryParse` direto em qualquer
  /// campo de preço/quantidade — texto com vírgula falha silenciosamente
  /// no `double.tryParse` puro.
  static double? parseNumero(String? texto) {
    if (texto == null) return null;
    final limpo = texto.trim();
    if (limpo.isEmpty) return null;
    return double.tryParse(limpo.replaceAll(',', '.'));
  }

  /// Formata um valor pra exibição nos campos com [MoedaInputFormatter]
  /// (sempre vírgula, 2 casas) — usado ao pré-popular um campo existente,
  /// já que o formatter só atua na digitação do usuário.
  static String formatarMoeda(double? valor) {
    if (valor == null) return '';
    return valor.toStringAsFixed(2).replaceAll('.', ',');
  }

  /// Calcula o % de desconto de um preço promocional sobre o preço normal,
  /// pra exibição (catálogo, carrinho). Retorna null quando não há uma
  /// promoção válida (promocional ausente, zerado ou não menor que o preço).
  static double? calcularDescontoPercentual(double preco, double? precoPromocional) {
    if (precoPromocional == null || precoPromocional <= 0) return null;
    if (preco <= 0 || precoPromocional >= preco) return null;
    return (1 - precoPromocional / preco) * 100;
  }

  static String? nome(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Por favor, insira o nome do produto';
    }
    return null;
  }

  static String? descricao(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Por favor, insira a descrição';
    }
    return null;
  }

  static String? categoria(String? value) {
    if (value == null || value.isEmpty) {
      return 'Por favor, selecione uma categoria';
    }
    return null;
  }

  /// Preço de venda (site/app): obrigatório e maior que zero.
  static String? precoVenda(String? value) {
    final numero = parseNumero(value);
    if (numero == null) return 'Por favor, insira o preço de venda';
    if (numero <= 0) return 'O preço de venda deve ser maior que zero';
    return null;
  }

  /// Custo: obrigatório, não pode ser negativo (zero é aceitável).
  static String? custo(String? value) {
    final numero = parseNumero(value);
    if (numero == null) return 'Por favor, insira o custo do produto';
    if (numero < 0) return 'O custo não pode ser negativo';
    return null;
  }

  /// Campo de preço opcional (iFood, concorrência): se preenchido, tem
  /// que ser um número válido maior que zero.
  static String? precoOpcional(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final numero = parseNumero(value);
    if (numero == null) return 'Número inválido';
    if (numero <= 0) return 'Deve ser maior que zero';
    return null;
  }

  /// Preço promocional: opcional, mas se preenchido tem que ser positivo
  /// e menor que o preço de venda (senão não é uma promoção).
  static String? precoPromocional(String? value, String? precoVendaTexto) {
    if (value == null || value.trim().isEmpty) return null;
    final numero = parseNumero(value);
    if (numero == null) return 'Número inválido';
    if (numero <= 0) return 'Deve ser maior que zero';

    final precoVenda = parseNumero(precoVendaTexto);
    if (precoVenda != null && numero >= precoVenda) {
      return 'O preço promocional deve ser menor que o preço de venda';
    }
    return null;
  }

  /// Quantidades de estoque: obrigatórias, inteiras, não-negativas.
  static String? estoqueInteiro(String? value, {required String campo}) {
    if (value == null || value.trim().isEmpty) {
      return 'Por favor, insira $campo';
    }
    final numero = int.tryParse(value.trim());
    if (numero == null) return 'Por favor, insira um número inteiro válido';
    if (numero < 0) return 'Não pode ser negativo';
    return null;
  }

  /// Peso/volume: opcionais, mas se preenchidos não podem ser negativos.
  static String? numeroOpcionalNaoNegativo(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final numero = parseNumero(value);
    if (numero == null) return 'Número inválido';
    if (numero < 0) return 'Não pode ser negativo';
    return null;
  }

  /// Markup (%) sobre o preço de venda no site/app — não é usado nos
  /// marketplaces, que têm preço próprio em "Disponibilidade em Marketplaces".
  /// Matematicamente precisa ser < 100 (é a mesma fórmula que o banco usa
  /// pra calcular `margem`: (preco - custo) / preco * 100).
  static String? markup(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final numero = parseNumero(value);
    if (numero == null) return 'Número inválido';
    if (numero >= 100) return 'Markup deve ser menor que 100%';
    return null;
  }

  /// Lucro (R$) sobre o preço de venda no site/app.
  static String? lucro(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    if (parseNumero(value) == null) return 'Número inválido';
    return null;
  }

  /// Desconto (%) do preço promocional sobre o preço de venda: opcional,
  /// mas se preenchido tem que ser um desconto real (entre 0 e 100,
  /// exclusive — 0% não é promoção e 100% seria dar de graça).
  static String? descontoPercentual(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final numero = parseNumero(value);
    if (numero == null) return 'Número inválido';
    if (numero <= 0 || numero >= 100) return 'Deve ser entre 0 e 100%';
    return null;
  }

  /// Código de barras: opcional, mas se preenchido só dígitos e no
  /// tamanho de um EAN-8/UPC-A/EAN-13/ITF-14 real (8 a 14 dígitos).
  static String? codigoBarras(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final limpo = value.trim();
    if (!RegExp(r'^\d+$').hasMatch(limpo)) {
      return 'Código de barras deve conter só números';
    }
    if (limpo.length < 8 || limpo.length > 14) {
      return 'Código de barras deve ter entre 8 e 14 dígitos';
    }
    return null;
  }

  /// Validade: opcional, mas se preenchida tem que ser uma data real no
  /// formato DD/MM/AAAA (o banco guarda como texto, então sem essa
  /// checagem qualquer coisa passaria).
  static String? validade(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(value.trim());
    if (match == null) return 'Use o formato DD/MM/AAAA';

    final dia = int.parse(match.group(1)!);
    final mes = int.parse(match.group(2)!);
    final ano = int.parse(match.group(3)!);
    final data = DateTime(ano, mes, dia);
    if (data.day != dia || data.month != mes || data.year != ano) {
      return 'Data inválida';
    }
    return null;
  }

  /// Formata a validade pra exibição — o campo é texto livre no banco e
  /// planilhas importadas gravam datas em formatos variados (ex: ISO
  /// "2026-04-30T00:00:00.000Z", já visto em produtos reais), bem diferente
  /// do DD/MM/AAAA que o cadastro manual sempre usa. Reconhece os dois; se
  /// não reconhecer nenhum, mostra o texto como está em vez de escondê-lo.
  static String formatarValidade(String? valor) {
    if (valor == null || valor.trim().isEmpty) return '';
    final texto = valor.trim();

    if (RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(texto)) return texto;

    final data = DateTime.tryParse(texto);
    if (data != null) {
      final dia = data.day.toString().padLeft(2, '0');
      final mes = data.month.toString().padLeft(2, '0');
      return '$dia/$mes/${data.year}';
    }

    return texto;
  }
}
