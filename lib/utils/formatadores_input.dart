import 'package:flutter/services.dart';

/// Máscara de valor monetário: o usuário só digita números e o campo se
/// formata sozinho como "45,90" (os 2 últimos dígitos viram centavos,
/// como em qualquer caixa de PDV). Elimina de vez a ambiguidade
/// vírgula/ponto que já causou preço não salvo antes.
class MoedaInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digitos = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitos.isEmpty) {
      return const TextEditingValue(text: '');
    }
    // Trava um teto sensato pra evitar número absurdo por colagem de texto.
    if (digitos.length > 10) {
      digitos = digitos.substring(0, 10);
    }

    final valor = int.parse(digitos) / 100;
    final texto = valor.toStringAsFixed(2).replaceAll('.', ',');

    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}

/// Só dígitos inteiros — estoque, quantidades.
class InteiroInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitos = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    return TextEditingValue(
      text: digitos,
      selection: TextSelection.collapsed(offset: digitos.length),
    );
  }
}

/// Só dígitos — código de barras. O tamanho (8-14) fica a cargo do
/// validator, aqui só barra letra/símbolo.
class DigitosInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digitos = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    return TextEditingValue(
      text: digitos,
      selection: TextSelection.collapsed(offset: digitos.length),
    );
  }
}

/// Máscara de data DD/MM/AAAA — insere as barras sozinho.
class DataInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digitos = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitos.length > 8) digitos = digitos.substring(0, 8);

    final buffer = StringBuffer();
    for (var i = 0; i < digitos.length; i++) {
      buffer.write(digitos[i]);
      if ((i == 1 || i == 3) && i != digitos.length - 1) {
        buffer.write('/');
      }
    }

    final texto = buffer.toString();
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}

/// Máscara de telefone BR: adapta pra (XX) XXXX-XXXX (fixo, 10 dígitos)
/// ou (XX) XXXXX-XXXX (celular, 11 dígitos) conforme a quantidade digitada.
class TelefoneInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digitos = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitos.length > 11) digitos = digitos.substring(0, 11);

    String texto;
    if (digitos.isEmpty) {
      texto = '';
    } else if (digitos.length <= 2) {
      texto = '($digitos';
    } else {
      final ddd = digitos.substring(0, 2);
      final resto = digitos.substring(2);
      final tamanhoPrefixo = digitos.length > 10 ? 5 : 4;
      if (resto.length <= tamanhoPrefixo) {
        texto = '($ddd) $resto';
      } else {
        final prefixo = resto.substring(0, tamanhoPrefixo);
        final sufixo = resto.substring(tamanhoPrefixo);
        texto = '($ddd) $prefixo-$sufixo';
      }
    }

    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}

/// Máscara de CPF: 000.000.000-00.
class CpfInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digitos = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitos.length > 11) digitos = digitos.substring(0, 11);

    final buffer = StringBuffer();
    for (var i = 0; i < digitos.length; i++) {
      buffer.write(digitos[i]);
      if ((i == 2 || i == 5) && i != digitos.length - 1) buffer.write('.');
      if (i == 8 && i != digitos.length - 1) buffer.write('-');
    }

    final texto = buffer.toString();
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}

/// Máscara de CEP: 00000-000.
class CepInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var digitos = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitos.length > 8) digitos = digitos.substring(0, 8);

    final buffer = StringBuffer();
    for (var i = 0; i < digitos.length; i++) {
      buffer.write(digitos[i]);
      if (i == 4 && i != digitos.length - 1) buffer.write('-');
    }

    final texto = buffer.toString();
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}

/// Filtro leve pra número decimal com sinal opcional (peso, volume,
/// markup, lucro) — só bloqueia letra/símbolo, sem forçar uma máscara de
/// centavos (que não faz sentido pra kg/m³/percentual).
class DecimalInputFormatter extends TextInputFormatter {
  final bool permiteSinal;

  DecimalInputFormatter({this.permiteSinal = false});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final permitido = permiteSinal ? RegExp(r'[0-9,\-]') : RegExp(r'[0-9,]');
    final texto = newValue.text
        .split('')
        .where((c) => permitido.hasMatch(c))
        .join();

    if (texto == newValue.text) return newValue;
    return TextEditingValue(
      text: texto,
      selection: TextSelection.collapsed(offset: texto.length),
    );
  }
}
