import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/cliente.dart';
import '../models/produto.dart'; // Seu modelo de Produto

// Modelo para um item no carrinho (mais robusto que Map<String, dynamic>)
class ItemCarrinho {
  final Produto produto;
  int quantidade;

  ItemCarrinho({required this.produto, required this.quantidade});

  double get precoUnitario =>
      produto.precoPromocional ?? produto.preco;

  double get precoTotalItem =>
      precoUnitario * quantidade;
}

class CarrinhoProvider with ChangeNotifier {
  final List<ItemCarrinho> _itens = [];
  Cliente? _clienteSelecionado;
  double _desconto = 0.0;
  String _entregaSelecionadaId = 'retirada'; // ID da opção de entrega padrão
  double _valorEntrega = 0.0;
  double _valorEntregaNormalAplicado = 0.0; // Valor da entrega antes de verificar frete grátis
  String _idVenda = const Uuid().v4();
  // Exemplo de estrutura para opções de entrega (pode vir de configurações/outro provider)
  final Map<String, Map<String, dynamic>> _opcoesEntregaConfig = {
    'retirada': {'nome': 'Retirar na Loja', 'valor': 0.0, 'minimoFreteGratis': 0.0},
    'local_5km': {'nome': 'Entrega Local (até 5km)', 'valor': 10.0, 'minimoFreteGratis': 100.0},
    'local_10km': {'nome': 'Entrega Local (5-10km)', 'valor': 15.0, 'minimoFreteGratis': 150.0},
  };

  // Getters
  List<ItemCarrinho> get itens => [..._itens]; // Retorna uma cópia para evitar modificação externa
  Cliente? get clienteSelecionado => _clienteSelecionado;
  double get desconto => _desconto;
  String get entregaSelecionadaId => _entregaSelecionadaId;
  Map<String, dynamic> get detalhesEntregaSelecionada => _opcoesEntregaConfig[_entregaSelecionadaId] ?? _opcoesEntregaConfig.values.first;
  Map<String, Map<String, dynamic>> get opcoesEntregaDisponiveis => _opcoesEntregaConfig;
  String get idVenda => _idVenda;
  double get subtotal {
    return _itens.fold(0.0, (sum, item) => sum + item.precoTotalItem);
  }

  double get valorEntregaCalculado {
    final detalhes = detalhesEntregaSelecionada;
    double minimoFreteGratis = detalhes['minimoFreteGratis'] as double? ?? double.infinity;
    if (minimoFreteGratis > 0 && subtotal >= minimoFreteGratis) {
      return 0.0; // Frete grátis
    }
    return _valorEntregaNormalAplicado; // Valor normal da entrega
  }

  double get totalCarrinho {
    return subtotal - _desconto + valorEntregaCalculado;
  }

  int get totalUnidades {
    return _itens.fold(0, (sum, item) => sum + item.quantidade);
  }

  double get valorFaltanteParaFreteGratis {
    final detalhes = detalhesEntregaSelecionada;
    double minimoFreteGratis = detalhes['minimoFreteGratis'] as double? ?? 0.0;
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
    notifyListeners();
  }

  void selecionarEntrega(String idOpcaoEntrega) {
    if (_opcoesEntregaConfig.containsKey(idOpcaoEntrega)) {
      _entregaSelecionadaId = idOpcaoEntrega;
      final detalhes = _opcoesEntregaConfig[idOpcaoEntrega]!;
      _valorEntregaNormalAplicado = detalhes['valor'] as double; // Armazena o valor base da entrega
      // O getter valorEntregaCalculado já lida com a lógica de frete grátis
      notifyListeners();
    }
  }
  void selecionarCliente(Cliente cliente) {
    _clienteSelecionado = cliente;
    notifyListeners();
  }

  void limparCarrinho() {
    _itens.clear();
    _desconto = 0.0;
    _itens.clear();
    _desconto = 0.0;
    _clienteSelecionado = null;
    _entregaSelecionadaId = 'retirada';
    _valorEntregaNormalAplicado =
    _opcoesEntregaConfig['retirada']!['valor']
    as double;
    _idVenda = const Uuid().v4();

    // Resetar entrega para o padrão ou manter a seleção do usuário?
    // _entregaSelecionadaId = 'retirada';
    // _valorEntregaNormalAplicado = _opcoesEntregaConfig['retirada']!['valor'] as double;
    notifyListeners();
  }
}