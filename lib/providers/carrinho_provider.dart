import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../models/cliente.dart';
import '../models/cupom.dart';
import '../models/kit_produto.dart';
import '../models/produto.dart'; // Seu modelo de Produto
import '../models/zona_entrega.dart';
import '../repositories/cupom_repository.dart';
import '../utils/agendamento_utils.dart';

// Modelo para um item no carrinho (mais robusto que Map<String, dynamic>)
class ItemCarrinho {
  final Produto produto;
  int quantidade;

  /// Id do KIT (não do componente) que originou este item, quando ele veio
  /// da explosão de um kit em produtos reais (ver `CarrinhoProvider.adicionarKit`)
  /// — null pra item avulso normal. Usado só pra reagrupar visualmente
  /// depois (recibo), não muda estoque/custo/margem, que já são os reais
  /// do componente.
  final String? grupoKitId;

  /// Preço unitário calculado (rateio do preço fechado do kit) — quando
  /// presente, sobrepõe o preço de catálogo do produto. Item avulso normal
  /// não define isso, e o preço continua vindo do catálogo como sempre.
  final double? precoUnitarioOverride;

  ItemCarrinho({
    required this.produto,
    required this.quantidade,
    this.grupoKitId,
    this.precoUnitarioOverride,
  });

  double get precoUnitario =>
      precoUnitarioOverride ?? (produto.precoPromocional ?? produto.preco);

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
      'grupoKitId': grupoKitId,
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
  JanelaHorarioAgendamento? _agendamentoSelecionado; // null = "quero agora" (previsão automática)

  // Getters
  List<ItemCarrinho> get itens => [..._itens]; // Retorna uma cópia para evitar modificação externa
  Cliente? get clienteSelecionado => _clienteSelecionado;
  double get desconto => _desconto;
  ZonaEntrega? get zonaEntregaSelecionada => _zonaSelecionada;
  Cupom? get cupomAplicado => _cupomAplicado;
  bool get validandoCupom => _validandoCupom;
  String? get erroCupom => _erroCupom;
  JanelaHorarioAgendamento? get agendamentoSelecionado => _agendamentoSelecionado;

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
    _adicionarItemUnico(produto, quantidade);
    notifyListeners();
  }

  /// Vende um kit: em vez de 1 item do kit em si, adiciona um `ItemCarrinho`
  /// POR COMPONENTE real (quantidade = quantidade pedida do kit × quantidade
  /// do componente no kit) — é assim que o pedido registrado já sai com os
  /// produtos reais pra baixar estoque/aparecer na separação, sem precisar
  /// de nenhuma lógica nova no RPC de registro (`registrar_pedido_completo`
  /// já trata qualquer produto_id normalmente).
  ///
  /// `catalogoProdutos` é a lista de produtos reais já carregada (Produto
  /// tem `estoqueAtual`, necessário pra validar estoque igual a um item
  /// avulso) — evita uma ida extra ao banco só pra resolver os componentes,
  /// já que `KitProduto.componentes` só carrega nome/preço/custo.
  void adicionarKit(KitProduto kit, List<Produto> catalogoProdutos, {int quantidade = 1}) {
    if (kit.componentes.isEmpty) {
      throw Exception('Kit "${kit.nome}" não tem componentes cadastrados.');
    }

    final precoEfetivoKit =
        kit.precoPromocional != null && kit.precoPromocional! < kit.preco ? kit.precoPromocional! : kit.preco;
    final somaPrecoCheio = kit.precoCheioCalculado;

    // Resolve os produtos reais primeiro e valida estoque de TODOS os
    // componentes antes de mexer no carrinho — evita deixar o carrinho
    // pela metade se um componente do meio da lista não tiver estoque
    // (senão os componentes já adicionados ficariam órfãos, sem o resto
    // do kit que os acompanha).
    final resolvidos = kit.componentes.map((componente) {
      final produtoReal = catalogoProdutos.firstWhere(
        (p) => p.id == componente.produtoId,
        orElse: () => throw Exception('Produto "${componente.nome}" do kit não foi encontrado no catálogo.'),
      );
      return (produto: produtoReal, quantidadeNecessaria: quantidade * componente.quantidade, precoComponente: componente.preco);
    }).toList();

    for (final r in resolvidos) {
      final jaNoCarrinho =
          _itens.where((i) => i.produto.id == r.produto.id).fold<int>(0, (soma, i) => soma + i.quantidade);
      if (jaNoCarrinho + r.quantidadeNecessaria > r.produto.estoqueAtual) {
        throw Exception(
          'Estoque insuficiente para ${r.produto.nome} (componente do kit "${kit.nome}"). Disponível: ${r.produto.estoqueAtual}',
        );
      }
    }

    // Rateio com reconciliação exata — mesma técnica usada em
    // _finalizar_pedido_core (banco): todo componente, exceto o último,
    // recebe round(precoEfetivoKit * precoComponente / somaPrecoCheio, 2)
    // "por kit" (ainda não dividido pela quantidade dele dentro do kit); o
    // ÚLTIMO componente absorve a diferença restante. Isso garante que
    // soma(quantidade × precoUnitario) bata centavo a centavo com
    // precoEfetivoKit × quantidade de kits vendidos — importante porque
    // esse total vira literalmente o valor cobrado do cliente
    // (registrar_pedido_completo grava exatamente o que mandamos, sem
    // recalcular). Preço "feio" (mais casas decimais) só existe no dado
    // interno — toda tela formata pra 2 casas na exibição.
    final valoresPorKitPreliminares = somaPrecoCheio > 0
        ? resolvidos
            .map((r) => double.parse((precoEfetivoKit * r.precoComponente / somaPrecoCheio).toStringAsFixed(2)))
            .toList()
        : List<double>.filled(resolvidos.length, 0.0);
    final somaPreliminarTotal = valoresPorKitPreliminares.fold<double>(0.0, (soma, v) => soma + v);

    for (var i = 0; i < resolvidos.length; i++) {
      final r = resolvidos[i];
      final ultimo = i == resolvidos.length - 1;
      final valorAlocadoPorKit =
          ultimo ? precoEfetivoKit - somaPreliminarTotal + valoresPorKitPreliminares[i] : valoresPorKitPreliminares[i];
      final quantidadeNoKit = r.quantidadeNecessaria ~/ quantidade;
      final precoUnitarioRateado = quantidadeNoKit > 0 ? valorAlocadoPorKit / quantidadeNoKit : 0.0;

      _adicionarItemUnico(
        r.produto,
        r.quantidadeNecessaria,
        grupoKitId: kit.id,
        precoUnitarioOverride: precoUnitarioRateado,
      );
    }
    notifyListeners();
  }

  /// Lógica compartilhada de adicionar 1 produto real ao carrinho (avulso ou
  /// componente de kit já expandido) — mesma validação de estoque de sempre,
  /// mesclando com uma linha existente do mesmo produto em vez de duplicar.
  /// Não chama notifyListeners (quem chama decide quando notificar, já que
  /// adicionarKit chama isso várias vezes numa só operação lógica).
  void _adicionarItemUnico(
    Produto produto,
    int quantidade, {
    String? grupoKitId,
    double? precoUnitarioOverride,
  }) {
    final index = _itens.indexWhere((item) => item.produto.id == produto.id);
    if (index >= 0) {
      if ((_itens[index].quantidade + quantidade) <= produto.estoqueAtual) {
        _itens[index].quantidade += quantidade;
      } else {
        throw Exception('Estoque insuficiente para ${produto.nome}. Disponível: ${produto.estoqueAtual}');
      }
    } else {
      if (quantidade <= produto.estoqueAtual) {
        _itens.add(ItemCarrinho(
          produto: produto,
          quantidade: quantidade,
          grupoKitId: grupoKitId,
          precoUnitarioOverride: precoUnitarioOverride,
        ));
      } else {
        throw Exception('Estoque insuficiente para ${produto.nome}. Disponível: ${produto.estoqueAtual}');
      }
    }
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

  /// Define a janela agendada pelo vendedor (entrega ou retirada, escolhida
  /// na tela de Entrega) — null = "quero agora" (previsão automática pela
  /// zona, calculada no fechamento da venda).
  void selecionarAgendamento(JanelaHorarioAgendamento? agendamento) {
    _agendamentoSelecionado = agendamento;
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
    _agendamentoSelecionado = null;
    notifyListeners();
  }
}