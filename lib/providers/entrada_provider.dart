import 'package:flutter/material.dart';
import '../models/entrada.dart';
import '../repositories/entrada_repository.dart';
import '../services/nfe_xml_parser.dart';

class EntradaProvider with ChangeNotifier {
  final EntradaRepository _repository = EntradaRepository();

  String? _empresaId;
  List<Entrada> _entradas = [];
  bool _carregando = false;
  String? _erro;

  List<Entrada> get entradas => _entradas;
  bool get carregando => _carregando;
  String? get erro => _erro;

  void definirEmpresa(String empresaId) => _empresaId = empresaId;

  Future<void> carregar() async {
    _carregando = true;
    _erro = null;
    notifyListeners();

    try {
      _entradas = await _repository.listar();
    } catch (e) {
      _erro = 'Erro ao carregar entradas: $e';
      debugPrint(_erro);
    } finally {
      _carregando = false;
      notifyListeners();
    }
  }

  /// Cria a entrada a partir de uma NF-e já parseada e conferida na tela
  /// de prévia. `itensResolvidos` já vem com `produtoId` preenchido onde
  /// houve correspondência por código de barras (feito na tela, contra
  /// os produtos já carregados no `ProdutoProvider`) — resolução de
  /// fornecedor (usar existente ou criar um novo) também é feita pela
  /// tela, via `FornecedorProvider`, antes de chamar este método.
  Future<void> importarNfe({
    required NfeImportada nfe,
    required List<ItemEntrada> itensResolvidos,
    String? fornecedorId,
    String? pedidoCompraId,
    String? criadoPor,
  }) async {
    if (_empresaId == null) {
      throw StateError('Nenhuma empresa definida no EntradaProvider ainda.');
    }

    final entrada = Entrada(
      nfeChaveAcesso: nfe.chaveAcesso,
      nfeNumero: nfe.numero,
      nfeSerie: nfe.serie,
      valorTotalProdutos: nfe.valorTotalProdutos,
      valorTotalNota: nfe.valorTotalNota,
      dataEmissao: nfe.dataEmissao,
      itens: itensResolvidos,
    );

    await _repository.criar(
      entrada: entrada,
      empresaId: _empresaId!,
      fornecedorId: fornecedorId,
      pedidoCompraId: pedidoCompraId,
      parcelas: nfe.parcelas,
      criadoPor: criadoPor,
    );
    await carregar();
  }
}
