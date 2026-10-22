import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gestor/utils/ofx_parser.dart';

const _sgml = '''OFXHEADER:100
DATA:OFXSGML
VERSION:102
CHARSET:1252

<OFX>
<BANKMSGSRSV1><STMTTRNRS><STMTRS>
<CURDEF>BRL
<BANKTRANLIST>
<DTSTART>20261001000000[-3:BRT]
<DTEND>20261021000000[-3:BRT]
<STMTTRN>
<TRNTYPE>CREDIT
<DTPOSTED>20261020120000[-3:BRT]
<TRNAMT>1234.56
<FITID>abc-1
<MEMO>Pix recebido - Maria Silva
<STMTTRN>
<TRNTYPE>DEBIT
<DTPOSTED>20261021
<TRNAMT>-89,90
<MEMO>Pagamento boleto ENEL
<STMTTRN>
<TRNTYPE>DEBIT
<DTPOSTED>20261021
<TRNAMT>-89,90
<MEMO>Pagamento boleto ENEL
</BANKTRANLIST>
<LEDGERBAL>
<BALAMT>5000.10
<DTASOF>20261021
</LEDGERBAL>
</STMTRS></STMTTRNRS></BANKMSGSRSV1>
</OFX>
''';

const _xml = '''<?xml version="1.0" encoding="UTF-8"?>
<OFX><BANKMSGSRSV1><STMTTRNRS><STMTRS><BANKTRANLIST>
<STMTTRN><TRNTYPE>CREDIT</TRNTYPE><DTPOSTED>20261015</DTPOSTED><TRNAMT>300.00</TRNAMT><FITID>X9</FITID><NAME>IFOOD.COM AGENCIA</NAME><MEMO>Repasse</MEMO></STMTTRN>
</BANKTRANLIST><LEDGERBAL><BALAMT>10.00</BALAMT><DTASOF>20261015</DTASOF></LEDGERBAL></STMTRS></STMTTRNRS></BANKMSGSRSV1></OFX>''';

void main() {
  test('OFX 1.x SGML: valores, direção, período e saldo', () {
    final e = OfxParser.parseTexto(_sgml);
    expect(e.lancamentos, hasLength(3));
    expect(e.lancamentos[0].entrada, isTrue);
    expect(e.lancamentos[0].valor, 1234.56);
    expect(e.lancamentos[0].idExterno, 'abc-1');
    expect(e.lancamentos[0].data, DateTime(2026, 10, 20));
    expect(e.lancamentos[1].entrada, isFalse);
    expect(e.lancamentos[1].valor, 89.90);
    expect(e.inicio, DateTime(2026, 10, 1));
    expect(e.fim, DateTime(2026, 10, 21));
    expect(e.saldoFinal, 5000.10);
  });

  test('sem FITID: duas linhas iguais no mesmo dia viram ids diferentes e estáveis', () {
    final a = OfxParser.parseTexto(_sgml);
    final b = OfxParser.parseTexto(_sgml);
    expect(a.lancamentos[1].idExterno, isNot(a.lancamentos[2].idExterno));
    expect(a.lancamentos[2].idExterno, b.lancamentos[2].idExterno);
  });

  test('OFX 2.x XML: NAME + MEMO na descrição', () {
    final e = OfxParser.parseTexto(_xml);
    expect(e.lancamentos.single.descricao, 'IFOOD.COM AGENCIA - Repasse');
    expect(e.lancamentos.single.valor, 300.0);
    expect(e.saldoFinal, 10.0);
  });

  test('Windows-1252 com acento cai pro latin1', () {
    final bytes = latin1.encode(_sgml.replaceFirst('Maria Silva', 'João Conceição'));
    expect(OfxParser.parse(bytes).lancamentos.first.descricao, contains('João Conceição'));
  });
}
