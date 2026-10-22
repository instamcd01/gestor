import 'dart:convert';

/// Uma linha do extrato OFX já normalizada pro formato de
/// `movimentacoes_financeiras` (valor sempre positivo, direção em [entrada]).
class LancamentoOfx {
  final String idExterno;
  final DateTime data;
  final bool entrada;
  final double valor;
  final String descricao;
  final String? tipoOfx;

  const LancamentoOfx({
    required this.idExterno,
    required this.data,
    required this.entrada,
    required this.valor,
    required this.descricao,
    this.tipoOfx,
  });
}

class ExtratoOfx {
  final List<LancamentoOfx> lancamentos;
  final DateTime? inicio;
  final DateTime? fim;
  final double? saldoFinal;
  final DateTime? saldoEm;

  const ExtratoOfx({required this.lancamentos, this.inicio, this.fim, this.saldoFinal, this.saldoEm});
}

/// Lê OFX 1.x (SGML, tags sem fechamento — o que quase todo banco
/// brasileiro exporta) e 2.x (XML). Não usa parser XML de propósito: o SGML
/// não fecha `<TRNAMT>`, e um leitor por tag aceita os dois formatos.
///
/// Sem FITID (alguns bancos mandam vazio ou repetido), o id vira
/// data+valor+descrição+ordem da linha no dia — estável entre reimportações
/// do mesmo período, que é o que importa pra não duplicar.
class OfxParser {
  static ExtratoOfx parse(List<int> bytes) => parseTexto(_decodificar(bytes));

  static ExtratoOfx parseTexto(String texto) {
    final blocos = RegExp(r'<STMTTRN>(.*?)(?:</STMTTRN>|(?=<STMTTRN>)|(?=</BANKTRANLIST>))', dotAll: true, caseSensitive: false)
        .allMatches(texto)
        .map((m) => m.group(1)!)
        .toList();

    final lancamentos = <LancamentoOfx>[];
    final fitidsVistos = <String>{};
    final ordemNoDia = <String, int>{};

    for (final bloco in blocos) {
      final valorTexto = _tag(bloco, 'TRNAMT');
      final data = _data(_tag(bloco, 'DTPOSTED'));
      if (valorTexto == null || data == null) continue;
      final valor = double.tryParse(valorTexto.replaceAll(',', '.'));
      if (valor == null || valor == 0) continue;

      final memo = _tag(bloco, 'MEMO');
      final nome = _tag(bloco, 'NAME');
      final descricao = [nome, memo].whereType<String>().where((s) => s.isNotEmpty).toSet().join(' - ');

      var fitid = _tag(bloco, 'FITID');
      if (fitid == null || fitid.isEmpty || fitidsVistos.contains(fitid)) {
        final dia = '${data.year}${_dois(data.month)}${_dois(data.day)}';
        final chave = '$dia|${valor.toStringAsFixed(2)}|$descricao';
        final ordem = (ordemNoDia[chave] ?? 0) + 1;
        ordemNoDia[chave] = ordem;
        fitid = 'h:$chave|$ordem';
      }
      fitidsVistos.add(fitid);

      lancamentos.add(LancamentoOfx(
        idExterno: fitid,
        data: data,
        entrada: valor > 0,
        valor: double.parse(valor.abs().toStringAsFixed(2)),
        descricao: descricao,
        tipoOfx: _tag(bloco, 'TRNTYPE'),
      ));
    }

    final saldoBloco = RegExp(r'<LEDGERBAL>(.*?)(?:</LEDGERBAL>|(?=<AVAILBAL>)|(?=</STMTRS>))', dotAll: true, caseSensitive: false)
        .firstMatch(texto)
        ?.group(1);
    final saldoTexto = saldoBloco == null ? null : _tag(saldoBloco, 'BALAMT');

    return ExtratoOfx(
      lancamentos: lancamentos,
      inicio: _data(_tag(texto, 'DTSTART')),
      fim: _data(_tag(texto, 'DTEND')),
      saldoFinal: saldoTexto == null ? null : double.tryParse(saldoTexto.replaceAll(',', '.')),
      saldoEm: saldoBloco == null ? null : _data(_tag(saldoBloco, 'DTASOF')),
    );
  }

  /// Valor da tag até o próximo `<` (SGML) ou o fechamento (XML).
  static String? _tag(String texto, String nome) {
    final m = RegExp('<$nome>([^<\\r\\n]*)', caseSensitive: false).firstMatch(texto);
    final valor = m?.group(1)?.trim();
    return (valor == null || valor.isEmpty) ? null : _desescapar(valor);
  }

  /// `20261021120000[-3:BRT]` → só a data (o extrato é por dia; fuso do
  /// banco muda de um pra outro e não interessa aqui).
  static DateTime? _data(String? valor) {
    if (valor == null || valor.length < 8) return null;
    final ano = int.tryParse(valor.substring(0, 4));
    final mes = int.tryParse(valor.substring(4, 6));
    final dia = int.tryParse(valor.substring(6, 8));
    if (ano == null || mes == null || dia == null) return null;
    return DateTime(ano, mes, dia);
  }

  static String _desescapar(String s) =>
      s.replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>').replaceAll('&quot;', '"');

  static String _dois(int n) => n.toString().padLeft(2, '0');

  /// Banco brasileiro costuma exportar em Windows-1252 (`CHARSET:1252`);
  /// UTF-8 inválido cai pro latin1, que cobre os acentos do português.
  static String _decodificar(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } on FormatException {
      return latin1.decode(bytes);
    }
  }
}
