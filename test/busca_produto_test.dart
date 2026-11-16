import 'package:flutter_test/flutter_test.dart';
import 'package:gestor/utils/busca_utils.dart';

void main() {
  const golden = 'Ração Golden Fórmula Para Cães Adultos 15kg – PremieRpet';
  const premier = 'Biscoito Premier Cookie Frutas Vermelhas 250g – PremieRpet';
  const vitta = 'Ração Vitta Natural Para Cães Adultos 15kg – PremieRpet';
  const nutrisco = 'Snack Cremoso Nutrisco Sabor Atum 56g – Nutrisco';

  bool busca(String nome, String termo, {String? marca, String? fab = 'PremieRpet'}) =>
      produtoBateBusca(nome, termo, marca: marca, fabricante: fab);

  test('"premier" não traz Golden nem Vitta, traz Premier', () {
    expect(busca(golden, 'premier', marca: 'Golden'), isFalse);
    expect(busca(vitta, 'premier', marca: 'Vitta Natural'), isFalse);
    expect(busca(premier, 'premier', marca: 'Premier'), isTrue);
  });

  test('"premierpet" traz o fabricante inteiro', () {
    expect(busca(golden, 'premierpet', marca: 'Golden'), isTrue);
    expect(busca(vitta, 'PremieRpet', marca: 'Vitta Natural'), isTrue);
    expect(busca(golden, 'premierpet golden', marca: 'Golden'), isTrue);
  });

  test('"golden premier" (fabricante como complemento) traz Golden', () {
    expect(busca(golden, 'golden premier', marca: 'Golden'), isTrue);
    expect(busca(golden, 'racao golden da premier', marca: 'Golden'), isFalse); // "da" não está em lugar nenhum
    expect(busca(premier, 'golden premier', marca: 'Premier'), isFalse);
  });

  test('busca pela marca e por palavras do nome continua', () {
    expect(busca('Ração X Para Cães 10kg – PremieRpet', 'golden', marca: 'Golden'), isTrue);
    expect(busca(golden, 'racao golden 15kg', marca: 'Golden'), isTrue);
    expect(busca(golden, 'caes adultos'), isTrue);
  });

  test('sufixo que não é o fabricante (marca) continua pesquisável', () {
    expect(busca(nutrisco, 'nutrisco', fab: 'Bem-me-Pet'), isTrue);
  });

  test('sem fabricante cadastrado o nome inteiro vale', () {
    expect(busca('Ração Golden Mini Bits 15KG', 'golden', fab: null), isTrue);
  });
}
