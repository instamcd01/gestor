/// Regras de validação e parsing dos campos de cliente/pet — mesmo
/// espírito de `produto_validators.dart`: formata e valida no próprio
/// campo em vez de só reclamar depois de salvar.
class ClienteValidators {
  ClienteValidators._();

  static double? parseNumero(String? texto) {
    if (texto == null) return null;
    final limpo = texto.trim();
    if (limpo.isEmpty) return null;
    return double.tryParse(limpo.replaceAll(',', '.'));
  }

  static String formatarMoeda(double? valor) {
    if (valor == null) return '';
    return valor.toStringAsFixed(2).replaceAll('.', ',');
  }

  static String? nome(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Por favor, insira o nome do cliente';
    }
    return null;
  }

  /// Celular: obrigatório, precisa ter DDD + número (10 ou 11 dígitos).
  static String? celular(String? value) {
    final digitos = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (digitos.isEmpty) return 'Por favor, insira o celular';
    if (digitos.length < 10 || digitos.length > 11) {
      return 'Celular inválido — inclua o DDD';
    }
    return null;
  }

  /// E-mail: opcional, mas se preenchido precisa ter um formato válido.
  static String? email(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!regex.hasMatch(value.trim())) return 'E-mail inválido';
    return null;
  }

  /// CPF: opcional, mas se preenchido precisa ter 11 dígitos.
  static String? cpf(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final digitos = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitos.length != 11) return 'CPF deve ter 11 dígitos';
    return null;
  }

  /// CEP: opcional, mas se preenchido precisa ter 8 dígitos.
  static String? cep(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final digitos = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitos.length != 8) return 'CEP deve ter 8 dígitos';
    return null;
  }

  /// UF: opcional, mas se preenchida precisa ser uma sigla de 2 letras.
  static String? estado(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    if (!RegExp(r'^[A-Za-z]{2}$').hasMatch(value.trim())) {
      return 'Use a sigla do estado (ex: SP)';
    }
    return null;
  }

  /// Saldo: opcional, mas se preenchido não pode ser negativo.
  static String? saldo(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final numero = parseNumero(value);
    if (numero == null) return 'Número inválido';
    if (numero < 0) return 'Saldo não pode ser negativo';
    return null;
  }

  /// Peso do pet: se preenchido, precisa ser maior que zero.
  static String? pesoPet(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final numero = parseNumero(value);
    if (numero == null) return 'Número inválido';
    if (numero <= 0) return 'Peso deve ser maior que zero';
    return null;
  }

  /// Converte texto DD/MM/AAAA numa data real — null se o formato ou a
  /// data forem inválidos, ou se a data for no futuro (nascimento não
  /// pode ser depois de hoje).
  static DateTime? parseData(String? value) {
    if (value == null) return null;
    final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(value.trim());
    if (match == null) return null;

    final dia = int.parse(match.group(1)!);
    final mes = int.parse(match.group(2)!);
    final ano = int.parse(match.group(3)!);
    final data = DateTime(ano, mes, dia);
    if (data.day != dia || data.month != mes || data.year != ano) return null;
    if (data.isAfter(DateTime.now())) return null;
    return data;
  }

  static String formatarData(DateTime? data) {
    if (data == null) return '';
    final dia = data.day.toString().padLeft(2, '0');
    final mes = data.month.toString().padLeft(2, '0');
    return '$dia/$mes/${data.year}';
  }

  /// Data digitada (aniversário, nascimento do pet): opcional por padrão,
  /// mas se preenchida precisa ser uma data DD/MM/AAAA real e não-futura.
  static String? data(String? value, {bool obrigatoria = false}) {
    if (value == null || value.trim().isEmpty) {
      return obrigatoria ? 'Por favor, insira a data' : null;
    }
    if (parseData(value) == null) return 'Data inválida — use DD/MM/AAAA';
    return null;
  }
}
