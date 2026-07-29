import 'package:xml/xml.dart';

import '../models/entrada.dart';
import '../models/fornecedor.dart';

/// Dados extraídos do XML de uma NF-e — puro parsing, sem tocar em
/// Supabase/produtos cadastrados. O casamento de `ItemEntrada.produtoId`
/// por código de barras acontece depois, em `EntradaRepository`/na tela
/// de importação, contra a lista de produtos já carregada no app.
class NfeImportada {
  final String chaveAcesso;
  final String? numero;
  final String? serie;
  final DateTime? dataEmissao;
  final Fornecedor fornecedorDetectado;
  final double valorTotalProdutos;
  final double valorTotalNota;
  final List<ItemEntrada> itens;
  final List<ParcelaEntrada> parcelas;

  NfeImportada({
    required this.chaveAcesso,
    this.numero,
    this.serie,
    this.dataEmissao,
    required this.fornecedorDetectado,
    required this.valorTotalProdutos,
    required this.valorTotalNota,
    required this.itens,
    required this.parcelas,
  });
}

class NfeXmlParser {
  /// Lança [FormatException] se o XML não tiver a estrutura mínima de uma
  /// NF-e (`infNFe` ausente) — a tela de importação deve capturar isso e
  /// mostrar uma mensagem amigável, não deixar vazar como erro genérico.
  static NfeImportada parse(String conteudoXml) {
    final documento = XmlDocument.parse(conteudoXml);
    final infNFe = _primeiroDescendente(documento.rootElement, 'infNFe');
    if (infNFe == null) {
      throw const FormatException('Arquivo não parece ser um XML de NF-e válido (tag infNFe não encontrada).');
    }

    final chaveAcesso = _extrairChaveAcesso(infNFe);

    final ide = _primeiroFilho(infNFe, 'ide');
    final numero = ide != null ? _texto(ide, 'nNF') : null;
    final serie = ide != null ? _texto(ide, 'serie') : null;
    final dhEmi = ide != null ? _texto(ide, 'dhEmi') : null;

    final emit = _primeiroFilho(infNFe, 'emit');
    final fornecedorDetectado = Fornecedor(
      nome: emit != null ? (_texto(emit, 'xNome') ?? 'Fornecedor sem nome') : 'Fornecedor sem nome',
      cnpjCpf: emit != null ? (_texto(emit, 'CNPJ') ?? _texto(emit, 'CPF') ?? '') : '',
      telefone: emit != null ? (_texto(_primeiroFilho(emit, 'enderEmit'), 'fone') ?? '') : '',
    );

    final itens = infNFe
        .findElements('det')
        .map(_parseItem)
        .toList();

    final total = _primeiroFilho(infNFe, 'total');
    final icmsTot = total != null ? _primeiroFilho(total, 'ICMSTot') : null;
    final valorTotalProdutos = double.tryParse(icmsTot != null ? (_texto(icmsTot, 'vProd') ?? '0') : '0') ?? 0.0;
    final valorTotalNota = double.tryParse(icmsTot != null ? (_texto(icmsTot, 'vNF') ?? '0') : '0') ?? 0.0;

    final cobr = _primeiroFilho(infNFe, 'cobr');
    final parcelas = cobr != null ? _parseParcelas(cobr) : <ParcelaEntrada>[];

    return NfeImportada(
      chaveAcesso: chaveAcesso,
      numero: numero,
      serie: serie,
      dataEmissao: dhEmi != null ? DateTime.tryParse(dhEmi) : null,
      fornecedorDetectado: fornecedorDetectado,
      valorTotalProdutos: valorTotalProdutos,
      valorTotalNota: valorTotalNota,
      itens: itens,
      parcelas: parcelas,
    );
  }

  /// A chave de 44 dígitos vem no atributo `Id` de `infNFe` (formato
  /// `"NFe" + 44 dígitos`) — presente em qualquer NF-e válida, diferente
  /// de `protNFe/infProt/chNFe` que só existe quando o XML inclui o
  /// protocolo de autorização (nem todo XML recebido do fornecedor traz).
  static String _extrairChaveAcesso(XmlElement infNFe) {
    final id = infNFe.getAttribute('Id') ?? '';
    final digitos = id.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitos.length != 44) {
      throw FormatException('Chave de acesso inválida no XML (esperado 44 dígitos, achou ${digitos.length}).');
    }
    return digitos;
  }

  static ItemEntrada _parseItem(XmlElement det) {
    final prod = _primeiroFilho(det, 'prod');
    if (prod == null) {
      return ItemEntrada(eanNfe: '', descricaoNfe: 'Item sem dados de produto', quantidade: 0, custoUnitario: 0, valorTotal: 0);
    }

    // cEAN vem literalmente "SEM GTIN" quando o fornecedor não cadastrou
    // código de barras pro item — não é um EAN de verdade, tratar como
    // ausente e cair pro cEANTrib (código tributável, às vezes preenchido
    // mesmo quando cEAN não é).
    String? ean = _texto(prod, 'cEAN');
    if (ean == null || ean.toUpperCase() == 'SEM GTIN' || ean.isEmpty) {
      ean = _texto(prod, 'cEANTrib');
    }
    if (ean == null || ean.toUpperCase() == 'SEM GTIN') {
      ean = '';
    }

    // <rastro> é opcional e pode se repetir (vários lotes do mesmo item na
    // mesma nota) — só usamos o primeiro pra auto-preencher, caso mais raro
    // de múltiplos lotes num único item fica pra edição manual na prévia.
    final rastro = _primeiroFilho(prod, 'rastro');
    final dFab = rastro != null ? _texto(rastro, 'dFab') : null;
    final dVal = rastro != null ? _texto(rastro, 'dVal') : null;

    return ItemEntrada(
      eanNfe: ean,
      descricaoNfe: _texto(prod, 'xProd') ?? '',
      ncm: _texto(prod, 'NCM'),
      quantidade: double.tryParse(_texto(prod, 'qCom') ?? '0') ?? 0.0,
      custoUnitario: double.tryParse(_texto(prod, 'vUnCom') ?? '0') ?? 0.0,
      valorTotal: double.tryParse(_texto(prod, 'vProd') ?? '0') ?? 0.0,
      numeroLote: rastro != null ? _texto(rastro, 'nLote') : null,
      dataFabricacao: dFab != null ? DateTime.tryParse(dFab) : null,
      dataValidade: dVal != null ? DateTime.tryParse(dVal) : null,
    );
  }

  /// Nem toda NF-e tem duplicatas (ex: pagamento à vista sem boleto) —
  /// lista vazia é um resultado válido, a tela de importação não deve
  /// criar nenhuma despesa nesse caso em vez de inventar um vencimento.
  static List<ParcelaEntrada> _parseParcelas(XmlElement cobr) {
    final parcelas = <ParcelaEntrada>[];
    var indice = 1;
    for (final dup in cobr.findElements('dup')) {
      final vencimentoTexto = _texto(dup, 'dVenc');
      final vencimento = vencimentoTexto != null ? DateTime.tryParse(vencimentoTexto) : null;
      final valor = double.tryParse(_texto(dup, 'vDup') ?? '');
      if (vencimento == null || valor == null) continue;
      parcelas.add(ParcelaEntrada(numero: indice, valor: valor, vencimento: vencimento));
      indice++;
    }
    return parcelas;
  }

  static XmlElement? _primeiroFilho(XmlElement el, String nome) {
    final filhos = el.findElements(nome);
    return filhos.isEmpty ? null : filhos.first;
  }

  static XmlElement? _primeiroDescendente(XmlElement el, String nome) {
    final encontrados = el.findAllElements(nome);
    return encontrados.isEmpty ? null : encontrados.first;
  }

  static String? _texto(XmlElement? el, String nome) {
    if (el == null) return null;
    final filho = _primeiroFilho(el, nome);
    final valor = filho?.innerText.trim();
    return (valor == null || valor.isEmpty) ? null : valor;
  }
}
