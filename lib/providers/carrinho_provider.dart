import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/cliente.dart';
import '../models/cupom.dart';
import '../models/produto.dart'; // Seu modelo de Produto
import '../models/zona_entrega.dart';
import '../repositories/cupom_repository.dart';

// Modelo para um item no carrinho (mais robusto que Map<String, dynamic>)
class ItemCarrinho {
  final Produto produto;
  int quantidade;

  ItemCarrinho({required this.produto, required this.quantidade});

  double get precoUnitario =>
      produto.precoPromocional ?? produto.preco;

  double get precoTotalItem =>
      precoUnitario * quantidade;

  /// Formato Map esperado pelas telas de pagamento (que ainda trabalham
  /// com Map<String, dynamic> em vez do objeto ItemCarrinho diretamente).
  Map<String, dynamic> toMap() {
    return {
      'produto': produto,
      'quantidade': quantidade,
      'precoUnitario': precoUnitario,
      'precoTotalItem': precoTotalItem,
    };
  }
}

class CarrinhoProvider with ChangeNotifier {
  final CupomRepository _cupomRepository = CupomRepository();

  final List<ItemCarrinho> _itens = [];
  Cliente? _clienteSelecionado;
  double _desconto = 0.0;
  ZonaEntrega? _zonaSelecionada; // null = retirada na loja (sem frete)
  String _idVenda = const Uuid().v4();
  Cupom? _cupomAplicado;
  bool _validandoCupom = false;
  String? _erroCupom;

  // Getters
  List<ItemCarrinho> get itens => [..._itens]; // Retorna uma cópia para evitar modificação externa
  Cliente? get clienteSelecionado => _clienteSelecionado;
  double get desconto => _desconto;
  ZonaEntrega? get zonaEntregaSelecionada => _zonaSelecionada;
  Cupom? get cupomAplicado => _cupomAplicado;
  bool get validandoCupom => _validandoCupom;
  String? get erroCupom => _erroCupom;

  /// Nome pra exibição/registro da venda — mantém esse getter (usado em
  /// vários lugares como rótulo descritivo) mesmo não sendo mais um ID
  /// interno de um mapa fixo.
  String get entregaSelecionadaId => _zonaSelecionada?.nome ?? 'Retirada na Loja';
  String get idVenda => _idVenda;
  double get subtotal {
    return _itens.fold(0.0, (sum, item) => sum + item.precoTotalItem);
  }

  double get valorEntregaCalculado {
    final zona = _zonaSelecionada;
    if (zona == null) return 0.0; // retirada na loja
    final minimoFreteGratis = zona.valorMinimoFreteGratis;
    if (minimoFreteGratis != null && subtotal >= minimoFreteGratis) {
      return 0.0; // Frete grátis
    }
    return zona.valor;
  }

  double get totalCarrinho {
    return subtotal - _desconto + valorEntregaCalculado;
  }

  int get totalUnidades {
    return _itens.fold(0, (sum, item) => sum + item.quantidade);
  }

  double get valorFaltanteParaFreteGratis {
    final minimoFreteGratis = _zonaSelecionada?.valorMinimoFreteGratis ?? 0.0;
    if (minimoFreteGratis == 0) return 0.0; // Se não há mínimo, não falta nada

    if (subtotal < minimoFreteGratis) {
      return minimoFreteGratis - subtotal;
    }
    return 0.0;
  }

  // Métodos para manipular o carrinho
  void adicionarProduto(Produto produto, {int quantidade = 1}) {
    final index = _itens.indexWhere((item) => item.produto.id == produto.id);
    if (index >= 0) {
      // Produto já existe, verifica estoque antes de aumentar a quantidade
      if ((_itens[index].quantidade + quantidade) <= produto.estoqueAtual) {
        _itens[index].quantidade += quantidade;
      } else {
        // Opcional: Lançar um erro ou notificar de alguma forma que o estoque é insuficiente
        print('Estoque insuficiente para adicionar mais ${produto.nome}');
        // Poderia até mesmo ajustar a quantidade para o máximo possível em estoque.
        // _itens[index].quantidade = produto.estoqueAtual;
        throw Exception('Estoque insuficiente para ${produto.nome}. Disponível: ${produto.estoqueAtual}');
      }
    } else {
      // Novo produto, verifica estoque
      if (quantidade <= produto.estoqueAtual) {
        _itens.add(ItemCarrinho(produto: produto, quantidade: quantidade));
      } else {
        print('Estoque insuficiente para adicionar ${produto.nome}');
        throw Exception('Estoque insuficiente para ${produto.nome}. Disponível: ${produto.estoqueAtual}');
      }
    }
    notifyListeners();
  }

  void atualizarQuantidadeProduto(String produtoId, int novaQuantidade) {
    final index = _itens.indexWhere((item) => item.produto.id == produtoId);
    if (index >= 0) {
      if (novaQuantidade <= 0) {
        _itens.removeAt(index);
      } else {
        // Verifica estoque antes de atualizar
        if (novaQuantidade <= _itens[index].produto.estoqueAtual) {
          _itens[index].quantidade = novaQuantidade;
        } else {
          print('Estoque insuficiente para atualizar ${produtoId} para ${novaQuantidade}');
          throw Exception('Estoque insuficiente para ${produtoId}. Disponível: ${_itens[index].produto.estoqueAtual}');
        }
      }
      notifyListeners();
    }
  }

  void removerProduto(String produtoId) {
    _itens.removeWhere((item) => item.produto.id == produtoId);
    notifyListeners();
  }

  void aplicarDesconto(double valor) {
    if (valor < 0) valor = 0;
    if (valor > subtotal) { // Não permitir desconto maior que o subtotal
      _desconto = subtotal;
    } else {
      _desconto = valor;
    }
    // Desconto manual substitui um cupom já aplicado — evita mandar um
    // cupom_id junto de um valor de desconto que não é mais o dele.
    _cupomAplicado = null;
    notifyListeners();
  }

  /// Valida via validar_cupom() no Postgres (mesma função usada pelo
  /// site) e, se válido, aplica o desconto retornado — nunca calcula o
  /// valor no Dart. empresaId vem de fora (AuthProvider) porque esse
  /// provider não conhece a empresa sozinho.
  Future<void> aplicarCupom(String empresaId, String codigo) async {
    if (codigo.trim().isEmpty) return;
    _validandoCupom = true;
    _erroCupom = null;
    notifyListeners();

    try {
      final itensPayload = _itens.map((item) => {
        'produto_id': item.produto.id,
        'categoria': item.produto.categoria,
        'subcategoria': item.produto.subcategoria,
        'marca': item.produto.fabricante,
        'subtotal': item.precoTotalItem,
      }).toList();

      final resultado = await _cupomRepository.validar(
        empresaId: empresaId,
        codigo: codigo.trim(),
        clienteId: _clienteSelecionado?.idCliente,
        subtotal: subtotal,
        itens: itensPayload,
      );

      if (!resultado.valido) {
        _erroCupom = resultado.motivo ?? 'Cupom inválido';
        _validandoCupom = false;
        notifyListeners();
        return;
      }

      _cupomAplicado = Cupom(
        id: resultado.cupomId,
        codigo: codigo.trim().toUpperCase(),
        tipoDesconto: TipoDescontoCupom.fixo,
        valor: resultado.valorDesconto,
        vendedorId: resultado.vendedorId,
      );
      _desconto = resultado.valorDesconto;
    } catch (e) {
      _erroCupom = 'Não foi possível validar o cupom agora.';
      debugPrint('Erro ao validar cupom: $e');
    } finally {
      _validandoCupom = false;
      notifyListeners();
    }
  }

  void removerCupom() {
    _cupomAplicado = null;
    _desconto = 0.0;
    _erroCupom = null;
    notifyListeners();
  }

  /// Define a zona de entrega escolhida (calculada a partir da distância
  /// real até o cliente). Passe null pra "retirada na loja" (sem frete).
  void selecionarZonaEntrega(ZonaEntrega? zona) {
    _zonaSelecionada = zona;
    notifyListeners();
  }

  void selecionarCliente(Cliente cliente) {
    _clienteSelecionado = cliente;
    notifyListeners();
  }

  void limparCarrinho() {
    _itens.clear();
    _desconto = 0.0;
    _clienteSelecionado = null;
    _zonaSelecionada = null;
    _idVenda = const Uuid().v4();
    _cupomAplicado = null;
    _erroCupom = null;
    notifyListeners();
  }
}