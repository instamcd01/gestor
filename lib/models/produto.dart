class Produto {
  final String id;
  String nome;
  double preco;
  double? precoPromocional;
  String descricao;
  String categoria;
  int estoqueAtual;
  int estoqueMinimo;
  String imagemUrl;
  String? imagemAutomaticaUrl;
  String codigoBarras;
  double custo;
  bool destacar;
  bool exibirNoCatalogo;
  double? precoIfood;
  String? validade;
  String? markup;
  String? lucro;
  String? empresa;
  double? precoConcorrencia;

  Produto({
    required this.id,
    required this.nome,
    required this.preco,
    this.precoPromocional,
    required this.descricao,
    required this.categoria,
    required this.estoqueAtual,
    required this.estoqueMinimo,
    required this.imagemUrl,
    this.imagemAutomaticaUrl,
    required this.codigoBarras,
    required this.custo,
    this.destacar = false,
    this.exibirNoCatalogo = true,
    this.precoIfood,
    this.validade,
    this.markup,
    this.lucro,
    this.empresa,
    this.precoConcorrencia, Object? idDaPlanilha,
  });

  Map<String, dynamic> toMap() {
    return {
      'nome': nome,
      'preco': preco,
      'precoPromocional': precoPromocional,
      'descricao': descricao,
      'categoria': categoria,
      'estoqueAtual': estoqueAtual,
      'estoqueMinimo': estoqueMinimo,
      'imagemUrl': imagemUrl,
      'imagemAutomaticaUrl': imagemAutomaticaUrl,
      'codigoBarras': codigoBarras,
      'custo': custo,
      'destacar': destacar,
      'exibirNoCatalogo': exibirNoCatalogo,
      'precoIfood': precoIfood,
      'validade': validade,
      'markup': markup,
      'lucro': lucro,
      'empresa': empresa,
      'precoConcorrencia': precoConcorrencia,
    };
  }

  factory Produto.fromMap(Map<String, dynamic> map, String documentId) {
    double? _parseDouble(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value.replaceAll(',', '.')); // Tenta converter string para double
      return null;
    }

    int? _parseInt(dynamic value) {
      if (value == null) return null;
      if (value is num) return value.toInt();
      if (value is String) return int.tryParse(value); // Tenta converter string para int
      return null;
    }

    return Produto(
      id: documentId,
      nome: map['nome']?.toString() ?? '', // Garantir que é string
      // Campos numéricos usando as funções auxiliares
      preco: _parseDouble(map['preco']) ?? 0.0,
      precoPromocional: _parseDouble(map['precoPromocional']), // Pode ser nulo
      descricao: map['descricao']?.toString() ?? '',
      categoria: map['categoria']?.toString() ?? '',
      estoqueAtual: _parseInt(map['estoqueAtual']) ?? 0,
      estoqueMinimo: _parseInt(map['estoqueMinimo']) ?? 0,
      imagemUrl: map['imagemUrl']?.toString() ?? '',
      imagemAutomaticaUrl: map['imagemAutomaticaUrl']?.toString(),
      codigoBarras: map['codigoBarras']?.toString() ?? '',
      custo: _parseDouble(map['custo']) ?? 0.0,

      // Campos booleanos (ajustar conforme como estão salvos)
      destacar: (map['destacar'] is int) ? (map['destacar'] == 1) : (map['destacar'] ?? false),
      exibirNoCatalogo: (map['exibirNoCatalogo'] is int) ? (map['exibirNoCatalogo'] == 1) : (map['exibirNoCatalogo'] ?? true),
      // OU se já são booleanos no Firestore:
      // destacar: map['destacar'] ?? false,
      // exibirNoCatalogo: map['exibirNoCatalogo'] ?? true,

      precoIfood: _parseDouble(map['precoIfood']), // Pode ser nulo
      validade: map['validade']?.toString(),
      markup: map['markup']?.toString(),
      lucro: map['lucro']?.toString(),
      empresa: map['empresa']?.toString(),
      precoConcorrencia: _parseDouble(map['precoConcorrencia']), // Se for double? no modelo
      // OU se precoConcorrencia for String? no modelo:
      // precoConcorrencia: map['precoConcorrencia']?.toString(),
    );
  }
}

// class Produto {
//   final String id;
//   final String nome;
//   final String categoria;
//   final String codigoBarras;
//
//   final double custo;
//   final double preco;
//   final double precoIfood;
//   final double precoPromocional;
//   final double precoConcorrencia;
//
//   final int estoqueAtual;
//   final int estoqueMinimo;
//
//   final String markup; // pode continuar como String para exibição (%)
//   final String lucro;
//
//   final String descricao;
//   final String imagemUrl;
//
//   final String empresa;
//   final bool destacar;
//   final bool exibirNoCatalogo;
//
//   // Estratégicos
//   final DateTime? dataCadastro;
//   final int quantidadeVendida;
//   final bool ativo;
//   final String codigoFornecedor;
//   final String localizacaoEstoque;
//
//   Produto({
//     required this.id,
//     required this.nome,
//     required this.categoria,
//     required this.codigoBarras,
//     required this.custo,
//     required this.preco,
//     required this.precoIfood,
//     required this.precoPromocional,
//     required this.precoConcorrencia,
//     required this.estoqueAtual,
//     required this.estoqueMinimo,
//     required this.markup,
//     required this.lucro,
//     required this.descricao,
//     required this.imagemUrl,
//     required this.empresa,
//     required this.destacar,
//     required this.exibirNoCatalogo,
//     this.dataCadastro,
//     this.quantidadeVendida = 0,
//     this.ativo = true,
//     this.codigoFornecedor = '',
//     this.localizacaoEstoque = '',
//   });
//
//   Map<String, dynamic> toMap() {
//     return {
//       'id': id,
//       'nome': nome,
//       'categoria': categoria,
//       'codigoBarras': codigoBarras,
//       'custo': custo,
//       'preco': preco,
//       'precoIfood': precoIfood,
//       'precoPromocional': precoPromocional,
//       'precoConcorrencia': precoConcorrencia,
//       'estoqueAtual': estoqueAtual,
//       'estoqueMinimo': estoqueMinimo,
//       'markup': markup,
//       'lucro': lucro,
//       'descricao': descricao,
//       'imagemUrl': imagemUrl,
//       'empresa': empresa,
//       'destacar': destacar,
//       'exibirNoCatalogo': exibirNoCatalogo,
//       'dataCadastro': dataCadastro?.toIso8601String(),
//       'quantidadeVendida': quantidadeVendida,
//       'ativo': ativo,
//       'codigoFornecedor': codigoFornecedor,
//       'localizacaoEstoque': localizacaoEstoque,
//     };
//   }
//
//   factory Produto.fromMap(Map<String, dynamic> map) {
//     return Produto(
//       id: map['id'] ?? '',
//       nome: map['nome'] ?? '',
//       categoria: map['categoria'] ?? '',
//       codigoBarras: map['codigoBarras'] ?? '',
//       custo: (map['custo'] ?? 0).toDouble(),
//       preco: (map['preco'] ?? 0).toDouble(),
//       precoIfood: (map['precoIfood'] ?? 0).toDouble(),
//       precoPromocional: (map['precoPromocional'] ?? 0).toDouble(),
//       precoConcorrencia: (map['precoConcorrencia'] ?? 0).toDouble(),
//       estoqueAtual: map['estoqueAtual'] ?? 0,
//       estoqueMinimo: map['estoqueMinimo'] ?? 0,
//       markup: map['markup'] ?? '',
//       lucro: map['lucro'] ?? '',
//       descricao: map['descricao'] ?? '',
//       imagemUrl: map['imagemUrl'] ?? '',
//       empresa: map['empresa'] ?? '',
//       destacar: map['destacar'] ?? false,
//       exibirNoCatalogo: map['exibirNoCatalogo'] ?? false,
//       dataCadastro: map['dataCadastro'] != null
//           ? DateTime.tryParse(map['dataCadastro'])
//           : null,
//       quantidadeVendida: map['quantidadeVendida'] ?? 0,
//       ativo: map['ativo'] ?? true,
//       codigoFornecedor: map['codigoFornecedor'] ?? '',
//       localizacaoEstoque: map['localizacaoEstoque'] ?? '',
//     );
//   }
// }
