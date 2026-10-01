import 'dart:typed_data';

import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Um item lido de um PDF de cotação/pedido do fornecedor. O casamento com
/// o catálogo é sempre por um identificador exato — nunca por nome — mas o
/// identificador disponível varia por formato de PDF: alguns trazem EAN
/// ([codigoBarras], casa direto com `produtos.codigo_barras`), outros só
/// trazem o código interno do PRÓPRIO fornecedor ([codigoFornecedor], casa
/// com `produto_fornecedores.codigo_produto_fornecedor` — por isso esse
/// casamento só funciona depois que o código já foi vinculado uma vez, ver
/// `ConferenciaEspelhoScreen._vincularExistente`). Um item sempre tem pelo
/// menos um dos dois preenchido.
class ItemCotacaoExtraido {
  final String? codigoBarras;
  final String? codigoFornecedor;
  final String nome;
  final int quantidade;
  final double custoUnitario;

  ItemCotacaoExtraido({
    this.codigoBarras,
    this.codigoFornecedor,
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
/// (preço unitário SEM imposto) / Vl ST / Vl IPI / **Vl Líq + Imp** (preço
/// unitário COM imposto — usado aqui como custo, é o valor real que sai do
/// bolso por unidade) / Vl Liq Tot s/Imp / Vl Líq Tot. Casamento é só por
/// código de barras — nunca por nome (mesmo princípio de toda
/// reconciliação por EAN já usada no projeto, ver iFood/Kyte) — produto
/// com nome diferente do cadastro mas EAN igual ainda casa certo; EAN sem
/// produto correspondente no catálogo fica de fora, quem chama decide o
/// que fazer.
///
/// Nunca lança exceção — PDF em formato diferente simplesmente devolve
/// lista vazia, e quem chama trata isso como "não deu pra ler
/// automaticamente, siga com a conferência manual" (comportamento de
/// antes desta função existir).
List<ItemCotacaoExtraido> parseCotacaoTargetSistemas(String texto) {
  final itens = <ItemCotacaoExtraido>[];
  // Grupo 1/2: nome do item + marca, do cabeçalho "(código) NOME\nMARCA"
  // que abre cada bloco. Grupo 5: "Vl Líq + Imp" (com "+ Imp" literal),
  // não confundir com o "Vl Líq" bare (sem imposto) que aparece antes no
  // mesmo bloco — o `[\s\S]*?` não-guloso pula o "Vl Líq" solto porque ali
  // não vem seguido de "+ Imp".
  final regexItem = RegExp(
    r'\(\d+\)\s*([^\n]+)\n([^\n]+)\n[\s\S]*?C[oó]d\.\s*Barras\s*\n(\d{8,14})[\s\S]*?Qtde\s*\n(\d+)[\s\S]*?Vl\s*L[ií]q\s*\+\s*Imp\s*\n([\d.,]+)\s*\n',
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

/// Reconhece o formato de cotação/pedido em TABELA do "Target Sistemas"
/// (mesmo rodapé "Target Sistemas", ERP usado pela Alfa Vet — formato
/// diferente do bloco rotulado de [parseCotacaoTargetSistemas], mesmo ERP
/// gerando 2 layouts de relatório distintos). A tabela visualmente tem 1
/// linha por item, mas o texto extraído (`PdfTextExtractor.extractText`)
/// sai com **1 CAMPO por linha**, não 1 item por linha — cada célula da
/// tabela é um "text run" próprio no PDF. Conferido com a extração real
/// (22/09, não só a renderização visual do PDF): a sequência por item é
/// sempre `Cód. / Descrição / "UN" / Emb / Qtde / Qtde Bonif / Validade /
/// Vl Unit / Vl Total`, 9 linhas seguidas, sem exceção (mesmo quando a
/// descrição "visualmente" quebra em 2 linhas na página, ela sai inteira
/// numa linha só de texto, ex: "KIT PROMOCIONAL FEMEA LABELLE(ROSA)"). Por
/// isso o parser ancora no literal "UN" (sempre sozinho numa linha, sempre
/// logo após a descrição) e lê os 2 campos antes e os 6 depois — com
/// validação de formato em cada um (código só dígitos, quantidades só
/// dígitos, validade no formato dd/mm/aa) pra não confundir com o
/// cabeçalho da tabela, que também tem uma linha "UN" solta.
///
/// Achado real (22/09): esse formato NÃO traz EAN nenhum — só o código
/// interno do PRÓPRIO fornecedor (coluna "Cód.") — por isso o item aqui
/// preenche [ItemCotacaoExtraido.codigoFornecedor], nunca
/// [ItemCotacaoExtraido.codigoBarras]. Esse código só casa com um produto
/// depois de vinculado (ver `produto_fornecedores.codigo_produto_fornecedor`
/// e `ConferenciaEspelhoScreen._vincularExistente`) — antes disso, mesmo
/// lendo o PDF certinho, o item cai em "sem cadastro" até o usuário vincular
/// uma vez.
List<ItemCotacaoExtraido> parseCotacaoTargetSistemasTabela(String texto) {
  final linhas = texto.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
  final regexCodigo = RegExp(r'^\d{1,6}$');
  final regexNumero = RegExp(r'^[\d.,]+$');
  final regexData = RegExp(r'^\d{1,2}/\d{1,2}/\d{1,2}$');
  final itens = <ItemCotacaoExtraido>[];

  for (var j = 0; j < linhas.length; j++) {
    if (linhas[j] != 'UN') continue;
    if (j < 2 || j + 6 >= linhas.length) continue;

    final codigo = linhas[j - 2];
    final nome = linhas[j - 1];
    final emb = linhas[j + 1];
    final qtdeStr = linhas[j + 2];
    final bonif = linhas[j + 3];
    final validade = linhas[j + 4];
    final vlUnitStr = linhas[j + 5];
    final vlTotalStr = linhas[j + 6];

    if (!regexCodigo.hasMatch(codigo)) continue;
    if (nome.isEmpty || nome == 'UN') continue;
    if (!regexNumero.hasMatch(emb) || !regexNumero.hasMatch(qtdeStr) || !regexNumero.hasMatch(bonif)) continue;
    if (!regexData.hasMatch(validade)) continue;
    if (!regexNumero.hasMatch(vlUnitStr) || !regexNumero.hasMatch(vlTotalStr)) continue;

    final quantidade = int.tryParse(qtdeStr);
    final custo = double.tryParse(vlUnitStr.replaceAll('.', '').replaceAll(',', '.'));
    if (quantidade == null || custo == null) continue;

    itens.add(ItemCotacaoExtraido(codigoFornecedor: codigo, nome: nome, quantidade: quantidade, custoUnitario: custo));
  }
  return itens;
}

/// Reconhece o formato de pedido/cotação do "ION Sistemas" (rodapé
/// "Processado por ION Sistemas" no PDF — ERP usado pela Mouragro). Único
/// dos 3 formatos que traz EAN de verdade (coluna "COD. BARRAS") — mas é
/// o mais fragmentado dos três: cada célula da tabela sai como um "text
/// run" próprio, e o "Preço Un." em particular sai partido em 4 linhas —
/// "$", parte inteira, ".", parte decimal — sempre nessa ordem, conferido
/// com a extração real (22/09). Já o "Preço" total (não o unitário) sai
/// inteiro numa linha só, ex: "$23.92". A sequência completa por item é:
/// `[# da linha] [código interno] [descrição, 1+ linhas] [unidade] [qtde]
/// $ [inteiro] . [decimal] [EAN] [preço total]`.
///
/// Estratégia: ancorar no bloco "$ / inteiro / . / decimal / EAN / preço
/// total" (o mais específico e menos ambíguo da sequência — dificilmente
/// aparece por acaso), e derivar tudo mais por POSIÇÃO relativa a essa
/// âncora, nunca por conteúdo. Isso evita o problema de números soltos da
/// descrição (ex: "500" de "500 GRS") serem confundidos com o código
/// interno do produto — em vez de tentar reconhecer onde a descrição
/// começa por regex, o início de cada item é sempre "logo depois do fim do
/// item anterior" (ou, pro primeiro item, logo depois do fim do cabeçalho
/// da tabela, que sempre termina no rótulo de coluna "IMAGEM" nesse
/// layout) — daí as 2 primeiras linhas desse trecho são sempre [#] e
/// [código interno] (nenhum dos dois é usado aqui), e o resto até a
/// unidade é a descrição.
List<ItemCotacaoExtraido> parseCotacaoIonSistemas(String texto) {
  final linhas = texto.replaceAll('\r', '').split('\n');
  final regexEan = RegExp(r'^\d{8,14}$');

  final inicioDados = linhas.indexWhere((l) => l.trim() == 'IMAGEM');
  if (inicioDados == -1) return [];

  final ancoras = <int>[];
  for (var i = 0; i + 5 < linhas.length; i++) {
    if (linhas[i].trim() != r'$') continue;
    if (linhas[i + 2].trim() != '.') continue;
    if (!regexEan.hasMatch(linhas[i + 4].trim())) continue;
    if (!linhas[i + 5].trim().startsWith(r'$')) continue;
    ancoras.add(i);
  }

  final itens = <ItemCotacaoExtraido>[];
  var inicioItem = inicioDados + 1;
  for (final k in ancoras) {
    final fimDescricao = k - 2; // k-2 é a unidade, k-1 é a quantidade
    if (fimDescricao - inicioItem < 3) {
      inicioItem = k + 6;
      continue;
    }
    final nome = linhas.sublist(inicioItem + 2, fimDescricao).join().trim();
    final quantidade = int.tryParse(linhas[k - 1].trim());
    final custo = double.tryParse('${linhas[k + 1].trim()}.${linhas[k + 3].trim()}');
    final ean = linhas[k + 4].trim();

    if (nome.isNotEmpty && quantidade != null && custo != null) {
      itens.add(ItemCotacaoExtraido(codigoBarras: ean, nome: nome, quantidade: quantidade, custoUnitario: custo));
    }
    inicioItem = k + 6; // logo depois do preço total começa o próximo item
  }
  return itens;
}

/// Ponto de entrada único pra ler um PDF de cotação/pedido — tenta cada
/// formato conhecido (ver funções acima) e usa o primeiro que reconhecer
/// algum item. Formato novo, não reconhecido por nenhum, devolve lista
/// vazia (mesmo contrato de sempre: quem chama trata como "leitura manual").
List<ItemCotacaoExtraido> parseCotacaoPdf(String texto) {
  final porBloco = parseCotacaoTargetSistemas(texto);
  if (porBloco.isNotEmpty) return porBloco;
  final porTabela = parseCotacaoTargetSistemasTabela(texto);
  if (porTabela.isNotEmpty) return porTabela;
  return parseCotacaoIonSistemas(texto);
}
