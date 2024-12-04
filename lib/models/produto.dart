class Produto {
  final String id;
  final String nome;
  final double preco;
  final double precoPromocional;
  final double custo;
  final String categoria;
  final String descricao;
  final String codigoBarras;
  final String imagemUrl;
  final int estoqueAtual;
  final int estoqueMinimo;
  final bool destacar;
  final bool exibirNoCatalogo;

  Produto({
    required this.id,
    required this.nome,
    required this.preco,
    required this.precoPromocional,
    required this.custo,
    required this.categoria,
    required this.descricao,
    required this.codigoBarras,
    required this.imagemUrl,
    required this.estoqueAtual,
    required this.estoqueMinimo,
    required this.destacar,
    required this.exibirNoCatalogo,
  });
}
