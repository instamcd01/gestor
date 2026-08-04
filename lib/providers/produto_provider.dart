import 'package:flutter/material.dart';
import '../models/produto.dart';
import '../models/sugestao_variante.dart';
import '../repositories/produto_repository.dart';

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

  Future<void> rejeitarSugestaoVariante(String sugestaoId) async {
    await _repository.rejeitarSugestaoVariante(sugestaoId);
    _sugestoesVariante.removeWhere((s) => s.id == sugestaoId);
    notifyListeners();
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
