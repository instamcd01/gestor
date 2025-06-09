
// class Produto {
//   String _id;
//   String _nome;
//   double _preco;
//   double _precoPromocional;
//   double _precoIfood;
//   double _custo;
//   String _categoria;
//   String _validade;
//   String _descricao;
//   String _codigoBarras;
//   String _imagemUrl;
//   double _markup;  // Alterado para double
//   double _lucro;  // Alterado para double
//   String _empresa;
//   double _precoConcorrencia;  // Alterado para double
//   int _estoqueAtual;
//   int _estoqueMinimo;
//   bool _destacar;
//   bool _exibirNoCatalogo;
//
//   Produto({
//     required String id,
//     required String nome,
//     required double preco,
//     required double precoPromocional,
//     required double precoIfood,
//     required double custo,
//     required String categoria,
//     required String validade,
//     required String descricao,
//     required String codigoBarras,
//     required String imagemUrl,
//     required double markup,  // Alterado para double
//     required double lucro,  // Alterado para double
//     required String empresa,
//     required double precoConcorrencia,  // Alterado para double
//     required int estoqueAtual,
//     required int estoqueMinimo,
//     required bool destacar,
//     required bool exibirNoCatalogo,
//   })  : _id = id,
//         _nome = nome,
//         _preco = preco,
//         _precoPromocional = precoPromocional,
//         _precoIfood = precoIfood,
//         _custo = custo,
//         _categoria = categoria,
//         _validade = validade,
//         _descricao = descricao,
//         _codigoBarras = codigoBarras,
//         _imagemUrl = imagemUrl,
//         _markup = markup,
//         _lucro = lucro,
//         _empresa = empresa,
//         _precoConcorrencia = precoConcorrencia,
//         _estoqueAtual = estoqueAtual,
//         _estoqueMinimo = estoqueMinimo,
//         _destacar = destacar,
//         _exibirNoCatalogo = exibirNoCatalogo;
//
//   // Getters
//   String get id => _id;
//   String get nome => _nome;
//   double get preco => _preco;
//   double get precoPromocional => _precoPromocional;
//   double get precoIfood => _precoIfood;
//   double get custo => _custo;
//   String get categoria => _categoria;
//   String get validade => _validade;
//   String get descricao => _descricao;
//   String get codigoBarras => _codigoBarras;
//   String get imagemUrl => _imagemUrl;
//   double get markup => _markup;  // Alterado para double
//   double get lucro => _lucro;  // Alterado para double
//   String get empresa => _empresa;
//   double get precoConcorrencia => _precoConcorrencia;  // Alterado para double
//   int get estoqueAtual => _estoqueAtual;
//   int get estoqueMinimo => _estoqueMinimo;
//   bool get destacar => _destacar;
//   bool get exibirNoCatalogo => _exibirNoCatalogo;
//
//   // Setters
//   set id(String novoId) {
//     _id = novoId;
//   }
//
//   set nome(String novoNome) {
//     _nome = novoNome;
//   }
//
//   set preco(double novoPreco) {
//     _preco = novoPreco;
//   }
//
//   set precoPromocional(double novoPrecoPromocional) {
//     _precoPromocional = novoPrecoPromocional;
//   }
//
//   set precoIfood(double novoPrecoIfood) {
//     _precoIfood = novoPrecoIfood;
//   }
//
//   set custo(double novoCusto) {
//     _custo = novoCusto;
//   }
//
//   set categoria(String novaCategoria) {
//     _categoria = novaCategoria;
//   }
//
//   set validade(String novaValidade) {
//     _validade = novaValidade;
//   }
//
//   set descricao(String novaDescricao) {
//     _descricao = novaDescricao;
//   }
//
//   set codigoBarras(String novoCodigoBarras) {
//     _codigoBarras = novoCodigoBarras;
//   }
//
//   set imagemUrl(String novaImagemUrl) {
//     _imagemUrl = novaImagemUrl;
//   }
//
//   set markup(double novoMarkup) {  // Alterado para double
//     _markup = novoMarkup;
//   }
//
//   set lucro(double novoLucro) {  // Alterado para double
//     _lucro = novoLucro;
//   }
//
//   set empresa(String novaEmpresa) {
//     _empresa = novaEmpresa;
//   }
//
//   set precoConcorrencia(double novoPrecoConcorrencia) {  // Alterado para double
//     _precoConcorrencia = novoPrecoConcorrencia;
//   }
//
//   set estoqueAtual(int novoEstoqueAtual) {
//     _estoqueAtual = novoEstoqueAtual;
//   }
//
//   set estoqueMinimo(int novoEstoqueMinimo) {
//     _estoqueMinimo = novoEstoqueMinimo;
//   }
//
//   set destacar(bool novoDestacar) {
//     _destacar = novoDestacar;
//   }
//
//   set exibirNoCatalogo(bool novoExibirNoCatalogo) {
//     _exibirNoCatalogo = novoExibirNoCatalogo;
//   }
// }



class Produto {
  int? id;
  String nome;
  double preco;
  double precoPromocional;
  String descricao;
  String categoria;
  int estoqueAtual;
  int estoqueMinimo;
  String imagemUrl;
  String codigoBarras;
  double custo;
  bool destacar;
  bool exibirNoCatalogo;
  double precoIfood;
  String validade;
  String markup;
  String lucro;
  String empresa;
  String precoConcorrencia;

  Produto({
    this.id,
    required this.nome,
    required this.preco,
    required this.precoPromocional,
    required this.descricao,
    required this.categoria,
    required this.estoqueAtual,
    required this.estoqueMinimo,
    required this.imagemUrl,
    required this.codigoBarras,
    required this.custo,
    required this.destacar,
    required this.exibirNoCatalogo,
    required this.precoIfood,
    required this.validade,
    required this.markup,
    required this.lucro,
    required this.empresa,
    required this.precoConcorrencia,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'preco': preco,
      'precoPromocional': precoPromocional,
      'descricao': descricao,
      'categoria': categoria,
      'estoqueAtual': estoqueAtual,
      'estoqueMinimo': estoqueMinimo,
      'imagemUrl': imagemUrl,
      'codigoBarras': codigoBarras,
      'custo': custo,
      'destacar': destacar ? 1 : 0,
      'exibirNoCatalogo': exibirNoCatalogo ? 1 : 0,
      'precoIfood': precoIfood,
      'validade': validade,
      'markup': markup,
      'lucro': lucro,
      'empresa': empresa,
      'precoConcorrencia': precoConcorrencia,
    };
  }

  factory Produto.fromMap(Map<String, dynamic> map) {
    return Produto(
      id: map['id'],
      nome: map['nome'],
      preco: map['preco'],
      precoPromocional: map['precoPromocional'],
      descricao: map['descricao'],
      categoria: map['categoria'],
      estoqueAtual: map['estoqueAtual'],
      estoqueMinimo: map['estoqueMinimo'],
      imagemUrl: map['imagemUrl'],
      codigoBarras: map['codigoBarras'],
      custo: map['custo'],
      destacar: map['destacar'] == 1,
      exibirNoCatalogo: map['exibirNoCatalogo'] == 1,
      precoIfood: map['precoIfood'],
      validade: map['validade'],
      markup: map['markup'],
      lucro: map['lucro'],
      empresa: map['empresa'],
      precoConcorrencia: map['precoConcorrencia'],
    );
  }
}

