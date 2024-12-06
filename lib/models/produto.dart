// class Produto {
//   final String id;
//   final String nome;
//   final double preco;
//   final double precoPromocional;
//   final double precoIfood;
//   final double custo;
//   final String categoria;
//   final String validade;
//   final String descricao;
//   final String codigoBarras;
//   final String imagemUrl;
//   final String markup;
//   final String lucro;
//   final String empresa;
//   final String precoConcorrencia;
//   final int estoqueAtual;
//   final int estoqueMinimo;
//   final bool destacar;
//   final bool exibirNoCatalogo;
//
//   Produto({
//     required this.id,
//     required this.nome,
//     required this.preco,
//     required this.precoPromocional,
//     required this.custo,
//     required this.categoria,
//     required this.descricao,
//     required this.codigoBarras,
//     required this.imagemUrl,
//     required this.estoqueAtual,
//     required this.estoqueMinimo,
//     required this.destacar,
//     required this.exibirNoCatalogo,
//     required this.precoIfood,
//     required this.validade,
//     required this.markup,
//     required this.lucro,
//     required this.empresa,
//     required this.precoConcorrencia,
//   });
// }


class Produto {
  String _id;
  String _nome;
  double _preco;
  double _precoPromocional;
  double _precoIfood;
  double _custo;
  String _categoria;
  String _validade;
  String _descricao;
  String _codigoBarras;
  String _imagemUrl;
  String _markup;
  String _lucro;
  String _empresa;
  String _precoConcorrencia;
  int _estoqueAtual;
  int _estoqueMinimo;
  bool _destacar;
  bool _exibirNoCatalogo;


  Produto({
    required String id,
    required String nome,
    required double preco,
    required double precoPromocional,
    required double precoIfood,
    required double custo,
    required String categoria,
    required String validade,
    required String descricao,
    required String codigoBarras,
    required String imagemUrl,
    required String markup,
    required String lucro,
    required String empresa,
    required String precoConcorrencia,
    required int estoqueAtual,
    required int estoqueMinimo,
    required bool destacar,
    required bool exibirNoCatalogo,
  })  : _id = id,
        _nome = nome,
        _preco = preco,
        _precoPromocional = precoPromocional,
        _precoIfood = precoIfood,
        _custo = custo,
        _categoria = categoria,
        _validade = validade,
        _descricao = descricao,
        _codigoBarras = codigoBarras,
        _imagemUrl = imagemUrl,
        _markup = markup,
        _lucro = lucro,
        _empresa = empresa,
        _precoConcorrencia = precoConcorrencia,
        _estoqueAtual = estoqueAtual,
        _estoqueMinimo = estoqueMinimo,
        _destacar = destacar,
        _exibirNoCatalogo = exibirNoCatalogo;

  // Getters
  String get id => _id;
  String get nome => _nome;
  double get preco => _preco;
  double get precoPromocional => _precoPromocional;
  double get precoIfood => _precoIfood;
  double get custo => _custo;
  String get categoria => _categoria;
  String get validade => _validade;
  String get descricao => _descricao;
  String get codigoBarras => _codigoBarras;
  String get imagemUrl => _imagemUrl;
  String get markup => _markup;
  String get lucro => _lucro;
  String get empresa => _empresa;
  String get precoConcorrencia => _precoConcorrencia;
  int get estoqueAtual => _estoqueAtual;
  int get estoqueMinimo => _estoqueMinimo;
  bool get destacar => _destacar;
  bool get exibirNoCatalogo => _exibirNoCatalogo;

  // Setters

  set id(String novoId) {
    _id = novoId;
  }
  set nome(String novoNome) {
    _nome = novoNome;
  }

  set preco(double novoPreco) {
    _preco = novoPreco;
  }

  set precoPromocional(double novoPrecoPromocional) {
    _precoPromocional = novoPrecoPromocional;
  }

  set precoIfood(double novoPrecoIfood) {
    _precoIfood = novoPrecoIfood;
  }

  set custo(double novoCusto) {
    _custo = novoCusto;
  }

  set categoria(String novaCategoria) {
    _categoria = novaCategoria;
  }

  set validade(String novaValidade) {
    _validade = novaValidade;
  }

  set descricao(String novaDescricao) {
    _descricao = novaDescricao;
  }

  set codigoBarras(String novoCodigoBarras) {
    _codigoBarras = novoCodigoBarras;
  }

  set imagemUrl(String novaImagemUrl) {
    _imagemUrl = novaImagemUrl;
  }

  set markup(String novoMarkup) {
    _markup = novoMarkup;
  }

  set lucro(String novoLucro) {
    _lucro = novoLucro;
  }

  set empresa(String novaEmpresa) {
    _empresa = novaEmpresa;
  }

  set precoConcorrencia(String novoPrecoConcorrencia) {
    _precoConcorrencia = novoPrecoConcorrencia;
  }

  set estoqueAtual(int novoEstoqueAtual) {
    _estoqueAtual = novoEstoqueAtual;
  }

  set estoqueMinimo(int novoEstoqueMinimo) {
    _estoqueMinimo = novoEstoqueMinimo;
  }

  set destacar(bool novoDestacar) {
    _destacar = novoDestacar;
  }

  set exibirNoCatalogo(bool novoExibirNoCatalogo) {
    _exibirNoCatalogo = novoExibirNoCatalogo;
  }
 }
