import 'package:flutter/material.dart';
import '../models/produto.dart';
import '../models/sugestao_variante.dart';
import '../repositories/produto_repository.dart';
import '../utils/variante_label_utils.dart';

class ProdutoProvider with ChangeNotifier {
  final ProdutoRepository _repository = ProdutoRepository();

  List<Produto> _produtos = [];
  bool _carregando = false;
  String? _erro;
  String? _empresaId;

  List<Produto> get produtos => _produtos;
  bool get carregando => _carregando;
  String? get erro => _erro;

  List<SugestaoVariante> _sugestoesVariante = [];

  /// Todas as sugestões pendentes pra este produto — um produto pode ter
  /// mais de uma (ex: 3+ variantes da mesma linha), por isso é lista, não
  /// uma só. Usada pra mostrar o chip (com contador) e o diálogo de revisão
  /// em produtos_screen.dart.
  List<SugestaoVariante> sugestoesVariantePara(String produtoId) =>
      _sugestoesVariante.where((s) => s.produtoId == produtoId).toList();

  /// Quantos produtos distintos têm ao menos uma sugestão pendente — usado
  /// no badge do filtro "Sugestão de variante" em produtos_screen.dart.
  int get totalProdutosComSugestaoVariante =>
      _sugestoesVariante.map((s) => s.produtoId).toSet().length;

  /// Quantos produtos distintos têm sugestão pendente, por eixo
  /// (`"peso"`, `"dose"`, `"sabor"`...) — usado no filtro por tipo em
  /// produtos_screen.dart, pra dar pra ignorar um eixo específico (ex:
  /// "não quero ver sugestão de sabor por enquanto").
  Map<String, int> get contagemSugestoesPorTipo {
    final porTipo = <String, Set<String>>{};
    for (final s in _sugestoesVariante) {
      (porTipo[s.tipoVariacao] ??= {}).add(s.produtoId);
    }
    return porTipo.map((tipo, produtoIds) => MapEntry(tipo, produtoIds.length));
  }

  /// Chamado uma vez pelo AuthGate assim que sabemos a empresa do usuário
  /// logado — necessário pra criar novos produtos (empresa_id é obrigatório).
  void definirEmpresa(String empresaId) {
    _empresaId = empresaId;
  }

  Future<void> carregarProdutos() async {
    _carregando = true;
    _erro = null;
    notifyListeners();

    try {
      _produtos = await _repository.listar();
      _sugestoesVariante = await _repository.listarSugestoesVariantePendentes();
    } catch (e) {
      _erro = 'Erro ao carregar produtos: $e';
      debugPrint(_erro);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  /// Mantido pelo nome antigo por compatibilidade com telas existentes.
  Future<void> atualizarProdutosDoFirestore() async {
    await carregarProdutos();
  }

  Future<Produto> adicionarProduto(Produto produto) async {
    if (_empresaId == null) {
      throw StateError('Nenhuma empresa definida no ProdutoProvider ainda.');
    }
    try {
      final novoProduto = await _repository.criar(produto, empresaId: _empresaId!);
      _produtos.add(novoProduto);
      notifyListeners();
      return novoProduto;
    } catch (e) {
      debugPrint('Erro ao adicionar produto: $e');
      rethrow;
    }
  }

  Future<void> atualizarProduto(Produto produto) async {
    if (produto.id == null || produto.id!.isEmpty) {
      debugPrint('Erro: produto sem id para atualização.');
      return;
    }
    try {
      await _repository.atualizar(produto);
      final index = _produtos.indexWhere((p) => p.id == produto.id);
      if (index != -1) {
        _produtos[index] = produto;
      }
      notifyListeners();
    } catch (e) {
      debugPrint('Erro ao atualizar produto: $e');
      rethrow;
    }
  }

  Produto? getProdutoPorId(String id) {
    try {
      return _produtos.firstWhere((p) => p.id == id);
    } catch (e) {
      return null;
    }
  }

  Future<void> deletarProduto(String id) async {
    if (id.isEmpty) return;
    try {
      await _repository.excluir(id);
      _produtos.removeWhere((produto) => produto.id == id);
      notifyListeners();
    } catch (e) {
      debugPrint('Erro ao deletar produto: $e');
      rethrow;
    }
  }

  List<Produto> _excluidos = [];
  List<Produto> get excluidos => _excluidos;

  Future<void> carregarExcluidos() async {
    try {
      _excluidos = await _repository.listarExcluidos();
      notifyListeners();
    } catch (e) {
      debugPrint('Erro ao carregar produtos excluídos: $e');
      rethrow;
    }
  }

  Future<void> restaurarProduto(String id) async {
    await _repository.restaurar(id);
    _excluidos.removeWhere((p) => p.id == id);
    notifyListeners();
    await carregarProdutos();
  }

  Future<void> marcarPrecoRevisado(String id) async {
    await _repository.marcarPrecoRevisado(id);
    final index = _produtos.indexWhere((p) => p.id == id);
    if (index != -1) {
      _produtos[index].revisarPreco = false;
      notifyListeners();
    }
  }

  /// Dispensa a revisão de vários produtos de uma vez, sem mudar o preço —
  /// usado na aba "Revisar preço" da Análise de Produtos em massa quando o
  /// usuário decide manter o preço atual mesmo assim.
  Future<void> marcarPrecoRevisadoEmMassa(List<String> ids) async {
    if (ids.isEmpty) return;
    await _repository.marcarPrecoRevisadoEmMassa(ids);
    for (final id in ids) {
      final index = _produtos.indexWhere((p) => p.id == id);
      if (index != -1) _produtos[index].revisarPreco = false;
    }
    notifyListeners();
  }

  /// Aplica um novo preço (calculado a partir do markup) em vários produtos
  /// de uma vez — cada um com seu próprio preço, calculado em cima do
  /// próprio custo (ver `CalculadoraPrecoMarkup`), por isso é um mapa em vez
  /// de um valor único. Roda em paralelo pra não esperar produto por
  /// produto; se algum falhar, o restante já aplicado permanece salvo (o
  /// chamador recebe as exceptions agregadas no relatório).
  Future<List<String>> aplicarPrecoRevisadoEmMassa(Map<String, double> precoPorId) async {
    final falhas = <String>[];
    await Future.wait(precoPorId.entries.map((entrada) async {
      try {
        await _repository.aplicarPrecoRevisado(entrada.key, entrada.value);
        final index = _produtos.indexWhere((p) => p.id == entrada.key);
        if (index != -1) {
          _produtos[index].preco = entrada.value;
          _produtos[index].revisarPreco = false;
        }
      } catch (e) {
        debugPrint('Erro ao aplicar preço revisado em massa ($entrada.key): $e');
        falhas.add(entrada.key);
      }
    }));
    notifyListeners();
    return falhas;
  }

  /// Define (ou limpa) o ciclo de recompra de vários produtos de uma vez —
  /// usado na aba "Ciclo de recompra" da Análise de Produtos em massa.
  Future<void> atualizarCicloRecompraEmMassa(List<String> ids, int? dias) async {
    if (ids.isEmpty) return;
    await _repository.atualizarCicloRecompraEmMassa(ids, dias);
    for (final id in ids) {
      final index = _produtos.indexWhere((p) => p.id == id);
      if (index != -1) _produtos[index].cicloRecompraDias = dias;
    }
    notifyListeners();
  }

  Future<List<String>> listarCategoriasDisponiveis() => _repository.listarCategoriasDisponiveis();

  Future<List<String>> listarFabricantesDisponiveis() => _repository.listarFabricantesDisponiveis();

  Future<void> atualizarCategoriaEmMassa(List<String> ids, String categoria, String? subcategoria) async {
    if (ids.isEmpty) return;
    await _repository.atualizarCategoriaEmMassa(ids, categoria, subcategoria);
    for (final id in ids) {
      final index = _produtos.indexWhere((p) => p.id == id);
      if (index != -1) {
        _produtos[index].categoria = categoria;
        _produtos[index].subcategoria = subcategoria;
      }
    }
    notifyListeners();
  }

  Future<void> atualizarFabricanteEmMassa(List<String> ids, String fabricante) async {
    if (ids.isEmpty) return;
    await _repository.atualizarFabricanteEmMassa(ids, fabricante);
    for (final id in ids) {
      final index = _produtos.indexWhere((p) => p.id == id);
      if (index != -1) _produtos[index].fabricante = fabricante;
    }
    notifyListeners();
  }

  Future<void> atualizarExibirCatalogoEmMassa(List<String> ids, bool exibir) async {
    if (ids.isEmpty) return;
    await _repository.atualizarExibirCatalogoEmMassa(ids, exibir);
    for (final id in ids) {
      final index = _produtos.indexWhere((p) => p.id == id);
      if (index != -1) _produtos[index].exibirNoCatalogo = exibir;
    }
    notifyListeners();
  }

  Future<void> atualizarAtivoEmMassa(List<String> ids, bool ativo) async {
    if (ids.isEmpty) return;
    await _repository.atualizarAtivoEmMassa(ids, ativo);
    for (final id in ids) {
      final index = _produtos.indexWhere((p) => p.id == id);
      if (index != -1) _produtos[index].ativo = ativo;
    }
    notifyListeners();
  }

  Future<void> atualizarDestaqueEmMassa(List<String> ids, bool destacar) async {
    if (ids.isEmpty) return;
    await _repository.atualizarDestaqueEmMassa(ids, destacar);
    for (final id in ids) {
      final index = _produtos.indexWhere((p) => p.id == id);
      if (index != -1) _produtos[index].destacar = destacar;
    }
    notifyListeners();
  }

  Future<void> atualizarEstoqueMinimoEmMassa(List<String> ids, int minimo) async {
    if (ids.isEmpty) return;
    await _repository.atualizarEstoqueMinimoEmMassa(ids, minimo);
    for (final id in ids) {
      final index = _produtos.indexWhere((p) => p.id == id);
      if (index != -1) _produtos[index].estoqueMinimo = minimo;
    }
    notifyListeners();
  }

  Future<void> aprovarSugestaoVariante({
    required SugestaoVariante sugestao,
    required String tipoVariacao,
    required String varianteLabelProduto,
    required String varianteLabelCandidato,
  }) async {
    await _repository.aprovarSugestaoVariante(
      sugestao: sugestao,
      tipoVariacao: tipoVariacao,
      varianteLabelProduto: varianteLabelProduto,
      varianteLabelCandidato: varianteLabelCandidato,
    );
    // produtoPaiId/tipoVariacao/varianteLabel são imutáveis no Produto local
    // (só mudam via aprovação) — recarrega pra refletir o estado real.
    _sugestoesVariante.removeWhere((s) => s.id == sugestao.id);
    await carregarProdutos();
  }

  /// Todos os produtos da mesma família de variantes que `produto`
  /// (incluindo a âncora e o próprio `produto`) — usado pra listar as
  /// "variantes irmãs" em editar_produto_screen.dart. Lista vazia = produto
  /// não faz parte de nenhuma família. `tipoVariacao` é preenchido tanto na
  /// âncora quanto nos filhos ao aprovar (ver `aprovar_sugestao_variante`),
  /// por isso serve pra detectar os dois casos com a mesma checagem.
  List<Produto> familiaDeVariantes(Produto produto) {
    if (produto.tipoVariacao == null) return [];
    final ancoraId = produto.produtoPaiId ?? produto.id;
    return _produtos.where((p) => p.id == ancoraId || p.produtoPaiId == ancoraId).toList();
  }

  /// Tira o produto da família de variantes (RPC `desvincular_variante`,
  /// ver produto_repository.dart pra por que precisa ser atômico no
  /// servidor). Recarrega o catálogo porque, quando o produto que sai é a
  /// âncora, outras linhas também mudam (novo âncora promovido, filhos
  /// reapontados).
  Future<void> desvincularVariante(String produtoId) async {
    await _repository.desvincularVariante(produtoId);
    await carregarProdutos();
  }

  Future<void> rejeitarSugestaoVariante(String sugestaoId) async {
    await _repository.rejeitarSugestaoVariante(sugestaoId);
    _sugestoesVariante.removeWhere((s) => s.id == sugestaoId);
    notifyListeners();
  }

  /// Aprova em massa, mas só sugestões de origem `estruturado` (campos
  /// batendo exatamente — alta confiança). As de origem `heuristico`
  /// (semelhança de nome) continuam exigindo revisão individual pelo
  /// diálogo, porque não há como confirmar o rótulo de cada variante sem
  /// olhar produto por produto — aprovar errado corrompe o agrupamento da
  /// família (nome estruturado, filtros do site). Usa o mesmo rótulo padrão
  /// que o diálogo individual usaria (ver `labelPadraoVariante`), já que não
  /// há correção manual possível num fluxo em massa. Sequencial (não
  /// paralelo) porque a RPC resolve a família no servidor com base no que já
  /// foi aprovado antes — paralelizar arriscaria duas aprovações do mesmo
  /// produto pisarem uma na outra.
  Future<List<String>> aprovarSugestoesEstruturadasEmMassa(List<SugestaoVariante> sugestoes) async {
    final falhas = <String>[];
    for (final sugestao in sugestoes) {
      if (sugestao.origem != 'estruturado') continue;
      final candidato = getProdutoPorId(sugestao.produtoCandidatoId);
      if (candidato == null) {
        falhas.add(sugestao.id);
        continue;
      }
      try {
        await aprovarSugestaoVariante(
          sugestao: sugestao,
          tipoVariacao: sugestao.tipoVariacao,
          varianteLabelProduto: sugestao.varianteLabelSugerido,
          varianteLabelCandidato: labelPadraoVariante(candidato, sugestao.tipoVariacao),
        );
      } catch (e) {
        debugPrint('Erro ao aprovar sugestão em massa (${sugestao.id}): $e');
        falhas.add(sugestao.id);
      }
    }
    return falhas;
  }

  /// Rejeita várias sugestões de uma vez (qualquer origem) — sempre seguro
  /// e reversível (ver `reconsiderarSugestaoVariante`).
  Future<void> rejeitarSugestoesEmMassa(List<String> sugestaoIds) async {
    for (final id in sugestaoIds) {
      try {
        await rejeitarSugestaoVariante(id);
      } catch (e) {
        debugPrint('Erro ao rejeitar sugestão em massa ($id): $e');
      }
    }
  }

  List<SugestaoVariante> _sugestoesRejeitadas = [];
  List<SugestaoVariante> get sugestoesRejeitadas => _sugestoesRejeitadas;

  Future<void> carregarSugestoesRejeitadas() async {
    try {
      _sugestoesRejeitadas = await _repository.listarSugestoesVarianteRejeitadas();
      notifyListeners();
    } catch (e) {
      debugPrint('Erro ao carregar sugestões rejeitadas: $e');
      rethrow;
    }
  }

  Future<void> reconsiderarSugestaoVariante(String sugestaoId) async {
    await _repository.reconsiderarSugestaoVariante(sugestaoId);
    _sugestoesRejeitadas.removeWhere((s) => s.id == sugestaoId);
    notifyListeners();
    await carregarProdutos();
  }
}
