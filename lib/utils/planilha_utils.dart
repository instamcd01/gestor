import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:excel/excel.dart';

/// Corrige um problema real observado em planilhas exportadas por algumas
/// ferramentas (Excel Online entre elas): `xl/styles.xml` às vezes declara
/// um `<numFmt>` "customizado" com `numFmtId` abaixo de 164 — faixa
/// reservada pra formatos *embutidos* do Excel. O pacote `excel` (v4.0.6)
/// lança exceção nesse caso ("custom numFmtId starts at 164 but found a
/// value of N") em vez de aceitar. A primeira tentativa de corrigir isso
/// (apagar a declaração) quebrou em outro lugar: o pacote não tem uma
/// tabela própria de formatos embutidos, só conhece o que está declarado
/// em `<numFmts>` — apagando a declaração, toda célula com estilo
/// referenciando esse id (`<xf numFmtId="44">`) passa a apontar pro nada
/// ("missing numFmt for 44"). A correção certa é RENUMERAR: mover o id
/// pra faixa válida (+10000) e atualizar todas as referências no mesmo
/// arquivo pro novo número, preservando a definição em vez de apagá-la.
Uint8List corrigirNumFmtsInvalidos(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final stylesFile = archive.findFile('xl/styles.xml');
  if (stylesFile == null) return bytes;

  var conteudo = utf8.decode(stylesFile.content as List<int>);

  final regexNumFmt = RegExp(r'<numFmt\s+numFmtId="(\d+)"');
  final idsInvalidos = <int>{};
  for (final m in regexNumFmt.allMatches(conteudo)) {
    final id = int.tryParse(m.group(1) ?? '');
    if (id != null && id < 164) idsInvalidos.add(id);
  }
  if (idsInvalidos.isEmpty) return bytes;

  for (final idAntigo in idsInvalidos) {
    final idNovo = idAntigo + 10000;
    // Substitui toda ocorrência de numFmtId="N" no arquivo (tanto a
    // declaração em <numFmts> quanto cada referência em <xf>) -- a aspa de
    // fechamento no padrão evita casar "44" dentro de "440" por engano.
    conteudo = conteudo.replaceAll('numFmtId="$idAntigo"', 'numFmtId="$idNovo"');
  }

  final novosBytes = utf8.encode(conteudo);
  archive.addFile(ArchiveFile('xl/styles.xml', novosBytes.length, novosBytes));
  final reempacotado = ZipEncoder().encode(archive);
  return reempacotado != null ? Uint8List.fromList(reempacotado) : bytes;
}

/// Preço/valor vindo de planilha pode vir como "R$   19,90" (com prefixo,
/// espaços variados e separador de milhar) — bem mais solto do que o que
/// os campos de digitação do app aceitam.
double? parseMoedaPlanilha(String? texto) {
  if (texto == null) return null;
  var limpo = texto.replaceAll('R\$', '').trim();
  if (limpo.isEmpty) return null;
  if (limpo.contains(',')) {
    limpo = limpo.replaceAll('.', '').replaceAll(',', '.');
  }
  return double.tryParse(limpo);
}

bool parseBooleanoPlanilha(String? texto, {bool padrao = false}) {
  if (texto == null || texto.isEmpty) return padrao;
  final v = texto.trim().toUpperCase();
  return v == 'S' || v == 'SIM' || v == '1' || v == 'TRUE' || v == 'V' || v == 'VERDADEIRO';
}

/// Reconhece o cabeçalho de uma planilha por *nome* de coluna, não por
/// posição — planilhas reais de lojistas quase nunca têm a mesma ordem de
/// colunas de um modelo genérico. Cada campo (chave do mapa de aliases)
/// aceita uma lista de nomes possíveis de cabeçalho (comparados em
/// minúsculo, sem distinção de maiúsculas).
class MapaColunasPlanilha {
  final Map<String, int> indicePorCampo;
  MapaColunasPlanilha(this.indicePorCampo);

  int? _idx(String campo) => indicePorCampo[campo];

  String? celula(List<Data?> row, String campo) {
    final i = _idx(campo);
    if (i == null || i >= row.length) return null;
    final v = row[i]?.value?.toString().trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  static MapaColunasPlanilha deCabecalho(
    List<Data?> headerRow,
    Map<String, List<String>> aliases,
  ) {
    final porNome = <String, int>{};
    for (var i = 0; i < headerRow.length; i++) {
      final nome = headerRow[i]?.value?.toString().trim().toLowerCase();
      if (nome != null && nome.isNotEmpty) porNome[nome] = i;
    }

    final indicePorCampo = <String, int>{};
    for (final entry in aliases.entries) {
      for (final alias in entry.value) {
        if (porNome.containsKey(alias)) {
          indicePorCampo[entry.key] = porNome[alias]!;
          break;
        }
      }
    }
    return MapaColunasPlanilha(indicePorCampo);
  }
}
