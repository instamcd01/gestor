import 'package:flutter_test/flutter_test.dart';
import 'package:gestor/utils/cliente_validators.dart';

void main() {
  group('ClienteValidators.celular', () {
    test('aceita com máscara, só dígitos e com DDI 55', () {
      expect(ClienteValidators.celular('(21) 97446-4293'), isNull);
      expect(ClienteValidators.celular('21974464293'), isNull);
      expect(ClienteValidators.celular('5521974464293'), isNull);
      expect(ClienteValidators.celular('552134567890'), isNull);
    });

    test('aceita placeholder do histórico Kyte', () {
      expect(ClienteValidators.celular('kyte-sem-numero-42'), isNull);
    });

    test('rejeita vazio e tamanho errado', () {
      expect(ClienteValidators.celular(''), isNotNull);
      expect(ClienteValidators.celular('974464293'), isNotNull);
      expect(ClienteValidators.celular('219744642930'), isNotNull);
    });
  });
}
