/// Um canal de venda externo (iFood, 99Food, Rappi, etc). Cadastro
/// compartilhado entre todas as empresas do SaaS — cada empresa escolhe
/// em quais desses canais cada produto seu aparece (ver [ProdutoCanal]).
class Marketplace {
  final String id;
  final String nome;
  final String tipo;
  final bool ativo;

  Marketplace({
    required this.id,
    required this.nome,
    required this.tipo,
    this.ativo = true,
  });

  factory Marketplace.fromSupabase(Map<String, dynamic> row) {
    return Marketplace(
      id: row['id'] as String,
      nome: row['nome']?.toString() ?? '',
      tipo: row['tipo']?.toString() ?? '',
      ativo: row['ativo'] as bool? ?? true,
    );
  }
}
