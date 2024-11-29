class Produto {
  final String id;
  final String nome;
  final double preco;
  final String descricao;
  final String categoria;
  final int estoque;
  final String imagemUrl;

  Produto({
    required this.id,
    required this.nome,
    required this.preco,
    required this.descricao,
    required this.categoria,
    required this.estoque,
    required this.imagemUrl,
  });
}
