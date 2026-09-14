import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Um item lido de um PDF de cotação/pedido do fornecedor.
class ItemCotacaoExtraido {
  final String codigoBarras;
  final String nome;
  final int quantidade;
  final double custoUnitario;

  ItemCotacaoExtraido({
    required this.codigoBarras,
    required this.nome,
    required this.quantidade,
    required this.custoUnitario,
  });
}

/// Extrai o texto bruto de um PDF (ordem de leitura do próprio arquivo,
/// sem tentar reconstruir layout de tabela) — suficiente pro formato do
/// Target Sistemas (ver [parseCotacaoTargetSistemas]), onde cada campo já
/// vem rotulado e em sequência determinística no fluxo de texto do PDF.
String extrairTextoPdf(Uint8List bytes) {
  final documento = PdfDocument(inputBytes: bytes);
  try {
    return PdfTextExtractor(documento).extractText();
  } finally {
    documento.dispose();
  }
}

/// Reconhece o formato de cotação/pedido do "Target Sistemas" (rodapé
/// "Target Sistemas" no PDF) — ERP usado pela Seropec e possivelmente
/// outros distribuidores. Cada item vem como um bloco de campos rotulados
/// sempre na mesma ordem: Cód. Barras / NCM / Qtde / Emb / Bonif / Vl Líq
/// (preço unitário SEM imposto — mesmo critério de custo já usado no
/// resto do projeto) / Vl ST / Vl IPI / Vl Líq + Imp / Vl Liq Tot s/Imp /
/// Vl Líq Tot. Casamento é só por código de barras — nunca por nome
/// (mesmo princípio de toda reconciliação por EAN já usada no projeto,
/// ver iFood/Kyte) — produto com nome diferente do cadastro mas EAN igual
/// ainda casa certo; EAN sem produto correspondente no catálogo fica de
/// fora, quem chama decide o que fazer.
///
/// Nunca lança exceção — PDF em formato diferente simplesmente devolve
/// lista vazia, e quem chama trata isso como "não deu pra ler
/// automaticamente, siga com a conferência manual" (comportamento de
/// antes desta função existir).
List<ItemCotacaoExtraido> parseCotacaoTargetSistemas(String texto) {
  final itens = <ItemCotacaoExtraido>[];
  // Grupo 1/2: nome do item + marca, do cabeçalho "(código) NOME\nMARCA"
  // que abre cada bloco. Resto igual a antes (EAN/Qtde/preço unitário).
  final regexItem = RegExp(
    r'\(\d+\)\s*([^\n]+)\n([^\n]+)\n[\s\S]*?C[oó]d\.\s*Barras\s*\n(\d{8,14})[\s\S]*?Qtde\s*\n(\d+)[\s\S]*?Vl\s*L[ií]q\s*\n([\d.,]+)\s*\n',
  );
  for (final m in regexItem.allMatches(texto)) {
    final nomeItem = m.group(1)?.trim();
    final marca = m.group(2)?.trim();
    final ean = m.group(3);
    final quantidade = int.tryParse(m.group(4) ?? '');
    final custo = double.tryParse((m.group(5) ?? '').replaceAll('.', '').replaceAll(',', '.'));
    if (nomeItem == null || ean == null || quantidade == null || custo == null) continue;
    final nome = (marca == null || marca.isEmpty) ? nomeItem : '$nomeItem — $marca';
    itens.add(ItemCotacaoExtraido(codigoBarras: ean, nome: nome, quantidade: quantidade, custoUnitario: custo));
  }
  return itens;
}
