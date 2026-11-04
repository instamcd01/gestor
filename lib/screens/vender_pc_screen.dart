import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/supabase_config.dart';
import '../models/kit_produto.dart';
import '../models/produto.dart';
import '../models/venda.dart';
import '../providers/auth_provider.dart';
import '../providers/carrinho_provider.dart';
import '../providers/kit_produto_provider.dart';
import '../providers/metodos_pagamento_provider.dart';
import '../providers/produto_provider.dart';
import '../repositories/carrinho_cliente_repository.dart';
import '../theme/app_theme.dart';
import '../utils/busca_utils.dart';
import '../utils/cliente_validators.dart';
import '../utils/formatadores_input.dart';
import 'cadastro_produto_screen.dart';
import 'carrinho_screen.dart';
import 'carrinhos_do_dia_screen.dart';
import 'conclusao_venda_screen.dart';
import 'conversas_whatsapp_screen.dart';
import 'desconto_screen.dart';
import 'pagamento_credito_screen.dart';
import 'pagamento_link_screen.dart';
import 'pagamento_outros_screen.dart';
import 'pagamento_pix_screen.dart';
import 'recibo_screen.dart';

const _categoriaKits = '__kits__';

enum _Fase { montando, pagando, concluida }

/// Vender no PC (janela ≥ 1200 px): produtos à esquerda e carrinho fixo à
/// direita, numa tela só — o painel da direita vira o pagamento (F9) e
/// depois a venda concluída, sem trocar de tela. No celular continua o
/// fluxo de sempre (`VendasScreen` → Carrinho → Entrega → Pagamento...).
///
/// Nenhuma regra é copiada: cliente/entrega abrem a tela de Entrega de
/// sempre (`escolherClienteEEntrega`), a venda é gravada pela mesma função
/// da conclusão do celular (`registrarVendaDoCheckout`), e Pix, crédito,
/// link e "outros" abrem as telas de pagamento de sempre.
class VenderPcScreen extends StatefulWidget {
  const VenderPcScreen({super.key});

  static const larguraPc = 1200.0;

  @override
  State<VenderPcScreen> createState() => _VenderPcScreenState();
}

class _VenderPcScreenState extends State<VenderPcScreen> {
  final _buscaController = TextEditingController();
  final _buscaFoco = FocusNode(debugLabel: 'busca-pdv');
  final _cupomController = TextEditingController();
  final _cupomFoco = FocusNode(debugLabel: 'cupom-pdv');
  final _recebidoController = TextEditingController();
  final _recebidoFoco = FocusNode(debugLabel: 'recebido-pdv');
  final _painelFoco = FocusNode(debugLabel: 'painel-pdv');
  final _listaScroll = ScrollController();

  bool _carregando = true;
  bool _modoGrade = false;
  String _categoria = 'Tudo';
  int _destaque = 0;
  String? _itemSelecionadoId;
  double? _valorMinimoPedido;
  int? _carrinhosDoDia;
  bool _salvandoOrcamento = false;

  _Fase _fase = _Fase.montando;
  String _metodo = '';
  double _saldoUsado = 0;
  bool _registrando = false;
  String? _erro;
  Venda? _vendaRegistrada;

  static const _alturaLinha = 57.0;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_tecla);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _carregar();
    });
  }

  bool _visivel = false;

  /// A tela fica montada por trás (IndexedStack do menu) mesmo escondida:
  /// o `autofocus` acontece com ela invisível. Quando ela passa a aparecer
  /// (F2 ou clique no menu), o cursor vai pra busca.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visivel = TickerMode.valuesOf(context).enabled;
    if (visivel && !_visivel) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _fase != _Fase.montando) return;
        _buscaFoco.requestFocus();
      });
    }
    _visivel = visivel;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_tecla);
    _buscaController.dispose();
    _buscaFoco.dispose();
    _cupomController.dispose();
    _cupomFoco.dispose();
    _recebidoController.dispose();
    _recebidoFoco.dispose();
    _painelFoco.dispose();
    _listaScroll.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    // Produtos e kits: quem carrega é a VendasScreen (que monta esta tela
    // no PC) — aqui só o que é desta tela.
    final empresaId = context.read<AuthProvider>().empresaId;
    context.read<MetodosPagamentoProvider>().carregar();
    await Future.wait([
      _carregarValorMinimo(empresaId),
      _contarCarrinhosDoDia(),
    ]);
    if (!mounted) return;
    setState(() => _carregando = false);
    _buscaFoco.requestFocus();
  }

  Future<void> _carregarValorMinimo(String? empresaId) async {
    if (empresaId == null) return;
    try {
      final data = await supabase.from('empresas').select('valor_minimo_pedido').eq('id', empresaId).single();
      _valorMinimoPedido = (data['valor_minimo_pedido'] as num?)?.toDouble();
    } catch (e) {
      debugPrint('Erro ao carregar valor mínimo de pedido: $e');
    }
  }

  Future<void> _contarCarrinhosDoDia() async {
    try {
      final lista = await CarrinhoClienteRepository().listarAtivosHoje();
      if (mounted) setState(() => _carrinhosDoDia = lista.length);
    } catch (_) {}
  }

  // ───────────────────────── dados ─────────────────────────

  List<Produto> _produtosFiltrados(List<Produto> todos) {
    final termo = _buscaController.text.trim();
    final normalizada = _normalizar(_categoria);
    return todos.where((p) {
      if (_categoria != 'Tudo' && _normalizar(p.categoria) != normalizada) return false;
      if (termo.isEmpty) return true;
      return contemTodasPalavras(p.nome, termo) || (p.codigoBarras.isNotEmpty && p.codigoBarras.contains(termo));
    }).toList();
  }

  List<KitProduto> _kitsFiltrados(List<KitProduto> todos) {
    final termo = _buscaController.text.trim();
    return termo.isEmpty ? todos : todos.where((k) => contemTodasPalavras(k.nome, termo)).toList();
  }

  String _normalizar(String s) => normalizarBusca(s).trim();

  bool get _naKits => _categoria == _categoriaKits;

  int _tamanhoLista() {
    if (_naKits) return _kitsFiltrados(context.read<KitProdutoProvider>().kits).length;
    return _produtosFiltrados(context.read<ProdutoProvider>().produtos).length;
  }

  // ───────────────────────── ações ─────────────────────────

  void _aviso(String texto) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  void _focarBusca() {
    _buscaFoco.requestFocus();
    _buscaController.selection = TextSelection(baseOffset: 0, extentOffset: _buscaController.text.length);
  }

  void _adicionarProduto(Produto produto) {
    if (produto.estoqueAtual <= 0) {
      _aviso('${produto.nome} está sem estoque.');
      return;
    }
    try {
      context.read<CarrinhoProvider>().adicionarProduto(produto);
      setState(() => _itemSelecionadoId = produto.id);
    } catch (_) {
      _aviso('Não foi possível adicionar: estoque insuficiente de ${produto.nome}.');
    }
  }

  void _adicionarKit(KitProduto kit) {
    try {
      context.read<CarrinhoProvider>().adicionarKit(kit, context.read<ProdutoProvider>().produtos);
    } catch (e) {
      _aviso('Não foi possível adicionar o kit "${kit.nome}": $e');
    }
  }

  /// Enter na busca: código de barras exato entra direto; senão entra o
  /// produto destacado na lista. A busca limpa pro próximo item.
  void _enterNaBusca() {
    final termo = _buscaController.text.trim();
    if (_naKits) {
      final kits = _kitsFiltrados(context.read<KitProdutoProvider>().kits);
      if (kits.isEmpty) return;
      _adicionarKit(kits[_destaque.clamp(0, kits.length - 1)]);
    } else {
      final todos = context.read<ProdutoProvider>().produtos;
      final porCodigo = termo.isEmpty ? null : todos.where((p) => p.codigoBarras == termo).firstOrNull;
      if (porCodigo != null) {
        _adicionarProduto(porCodigo);
      } else {
        final lista = _produtosFiltrados(todos);
        if (lista.isEmpty) {
          if (termo.isNotEmpty) _aviso('Nenhum produto com "$termo".');
          return;
        }
        _adicionarProduto(lista[_destaque.clamp(0, lista.length - 1)]);
      }
    }
    _buscaController.clear();
    setState(() => _destaque = 0);
    _buscaFoco.requestFocus();
  }

  void _moverDestaque(int passo) {
    final total = _tamanhoLista();
    if (total == 0) return;
    setState(() => _destaque = (_destaque + passo).clamp(0, total - 1));
    if (_modoGrade || !_listaScroll.hasClients) return;
    final topo = _destaque * _alturaLinha;
    final pos = _listaScroll.position;
    if (topo < pos.pixels) {
      _listaScroll.jumpTo(topo);
    } else if (topo + _alturaLinha > pos.pixels + pos.viewportDimension) {
      _listaScroll.jumpTo(topo + _alturaLinha - pos.viewportDimension);
    }
  }

  void _mudarQuantidade(ItemCarrinho item, int nova) {
    try {
      context.read<CarrinhoProvider>().atualizarQuantidadeProduto(item.produto.id!, nova);
      if (nova <= 0 && _itemSelecionadoId == item.produto.id) setState(() => _itemSelecionadoId = null);
    } catch (_) {
      _aviso('Estoque insuficiente de ${item.produto.nome}. Disponível: ${item.produto.estoqueAtual}');
    }
  }

  ItemCarrinho? _itemSelecionado(CarrinhoProvider carrinho) {
    final itens = carrinho.itens;
    if (itens.isEmpty) return null;
    return itens.where((i) => i.produto.id == _itemSelecionadoId).firstOrNull ?? itens.last;
  }

  Future<void> _escolherCliente() async {
    await escolherClienteEEntrega(context, context.read<CarrinhoProvider>(), comoJanela: true);
    if (mounted && _fase == _Fase.montando) _buscaFoco.requestFocus();
  }

  Future<void> _salvarOrcamento() async {
    final carrinho = context.read<CarrinhoProvider>();
    final nome = carrinho.clienteSelecionado?.nome ?? '';
    setState(() => _salvandoOrcamento = true);
    try {
      await salvarOrcamentoNoCliente(carrinho);
      _aviso('Orçamento salvo pra $nome — retome em "Carrinhos do dia".');
      _contarCarrinhosDoDia();
    } catch (e) {
      _aviso('Não foi possível salvar: $e');
    } finally {
      if (mounted) setState(() => _salvandoOrcamento = false);
    }
  }

  Future<void> _aplicarDesconto() async {
    final carrinho = context.read<CarrinhoProvider>();
    final base = carrinho.subtotal + carrinho.valorEntregaCalculado;
    final novoValor = await Navigator.push<double>(
      context,
      MaterialPageRoute(builder: (_) => DescontoScreen(valorTotal: base)),
    );
    if (novoValor != null) carrinho.aplicarDesconto((base - novoValor).clamp(0, base).toDouble());
  }

  Future<void> _abrirCarrinhosDoDia() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const CarrinhosDoDiaScreen()));
    if (!mounted) return;
    _contarCarrinhosDoDia();
    _buscaFoco.requestFocus();
  }

  // ───────────────────────── pagamento ─────────────────────────

  bool _podePagar(CarrinhoProvider carrinho) =>
      carrinho.itens.isNotEmpty &&
      carrinho.clienteSelecionado != null &&
      !(_valorMinimoPedido != null && carrinho.totalCarrinho < _valorMinimoPedido!);

  void _irPagar() {
    final carrinho = context.read<CarrinhoProvider>();
    if (carrinho.itens.isEmpty) return;
    if (carrinho.clienteSelecionado == null) {
      _escolherCliente();
      return;
    }
    if (!_podePagar(carrinho)) return;
    setState(() {
      _fase = _Fase.pagando;
      _metodo = '';
      _saldoUsado = 0;
      _erro = null;
      _recebidoController.clear();
    });
    _painelFoco.requestFocus();
  }

  void _voltarAoCarrinho() {
    setState(() {
      _fase = _Fase.montando;
      _erro = null;
    });
    _buscaFoco.requestFocus();
  }

  double _antesDoSaldo(CarrinhoProvider c) => math.max(0, c.totalCarrinho);
  double _aPagar(CarrinhoProvider c) => double.parse(math.max(0, _antesDoSaldo(c) - _saldoUsado).toStringAsFixed(2));

  double get _recebido => ClienteValidators.parseNumero(_recebidoController.text) ?? 0;

  void _escolherMetodo(String metodo) {
    setState(() {
      _metodo = metodo;
      _erro = null;
    });
    if (metodo == 'Dinheiro') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _recebidoFoco.requestFocus());
    } else {
      _painelFoco.requestFocus();
    }
  }

  bool get _metodoNoPainel => _metodo == 'Dinheiro' || _metodo == 'Cartão de Débito';

  Future<void> _concluir() async {
    if (_registrando || _metodo.isEmpty) return;
    final carrinho = context.read<CarrinhoProvider>();
    final total = _aPagar(carrinho);
    if (!_metodoNoPainel) return _abrirTelaDoMetodo(carrinho, total);

    double? valorPago;
    double? troco;
    if (_metodo == 'Dinheiro') {
      // Campo vazio = valor exato (o mais comum no balcão).
      valorPago = _recebidoController.text.trim().isEmpty ? total : _recebido;
      if (valorPago + 0.001 < total) {
        _aviso('Pagamento incompleto! Faltam R\$ ${_moeda(total - valorPago)}.');
        return;
      }
      troco = double.parse((valorPago - total).toStringAsFixed(2));
    }

    setState(() {
      _registrando = true;
      _erro = null;
    });
    try {
      final venda = await registrarVendaDoCheckout(
        context,
        carrinho: carrinho.itens.map((i) => i.toMap()).toList(),
        cliente: carrinho.clienteSelecionado!,
        metodoPagamento: _metodo,
        valorTotal: total,
        valorPago: valorPago,
        troco: troco,
        desconto: carrinho.desconto,
        cupomId: carrinho.cupomAplicado?.id,
        valorEntrega: carrinho.valorEntregaCalculado,
        entregaSelecionada: carrinho.entregaSelecionadaId,
        saldoUsado: _saldoUsado,
        zonaEntrega: carrinho.zonaEntregaSelecionada,
        agendamento: carrinho.agendamentoSelecionado,
      );
      if (!mounted) return;
      setState(() {
        _vendaRegistrada = venda;
        _fase = _Fase.concluida;
        _itemSelecionadoId = null;
      });
      _painelFoco.requestFocus();
    } catch (e) {
      debugPrint('Erro ao registrar venda: $e');
      if (mounted) setState(() => _erro = mensagemErroRegistroVenda(e));
    } finally {
      if (mounted) setState(() => _registrando = false);
    }
  }

  /// Pix, crédito, link e "outros" seguem nas telas de sempre (que gravam
  /// pela mesma conclusão). Ao voltar com a venda feita, o carrinho está
  /// vazio e a tela volta pra uma venda nova.
  Future<void> _abrirTelaDoMetodo(CarrinhoProvider carrinho, double total) async {
    final itens = carrinho.itens.map((i) => i.toMap()).toList();
    final cliente = carrinho.clienteSelecionado!;
    final Widget tela = switch (_metodo) {
      'Pix' => PagamentoPixScreen(
          valorTotal: total,
          carrinho: itens,
          metodoPagamento: _metodo,
          cliente: cliente,
          desconto: carrinho.desconto,
          cupomId: carrinho.cupomAplicado?.id,
          valorEntrega: carrinho.valorEntregaCalculado,
          entregaSelecionada: carrinho.entregaSelecionadaId,
          zonaEntrega: carrinho.zonaEntregaSelecionada,
          agendamento: carrinho.agendamentoSelecionado,
          saldoUsado: _saldoUsado,
        ),
      'Cartão de Crédito' => PagamentoCartaoCreditoScreen(
          valorTotal: total,
          carrinho: itens,
          metodoPagamento: _metodo,
          cliente: cliente,
          desconto: carrinho.desconto,
          cupomId: carrinho.cupomAplicado?.id,
          valorEntrega: carrinho.valorEntregaCalculado,
          entregaSelecionada: carrinho.entregaSelecionadaId,
          zonaEntrega: carrinho.zonaEntregaSelecionada,
          agendamento: carrinho.agendamentoSelecionado,
          saldoUsado: _saldoUsado,
        ),
      'Link de Pagamento' => PagamentoLinkScreen(
          valorTotal: total,
          carrinho: itens,
          metodoPagamento: _metodo,
          cliente: cliente,
          desconto: carrinho.desconto,
          cupomId: carrinho.cupomAplicado?.id,
          valorEntrega: carrinho.valorEntregaCalculado,
          entregaSelecionada: carrinho.entregaSelecionadaId,
          zonaEntrega: carrinho.zonaEntregaSelecionada,
          agendamento: carrinho.agendamentoSelecionado,
          saldoUsado: _saldoUsado,
        ),
      _ => PagamentoOutrosScreen(
          valorTotal: total,
          carrinho: itens,
          cliente: cliente,
          desconto: carrinho.desconto,
          cupomId: carrinho.cupomAplicado?.id,
          valorEntrega: carrinho.valorEntregaCalculado,
          entregaSelecionada: carrinho.entregaSelecionadaId,
          zonaEntrega: carrinho.zonaEntregaSelecionada,
          agendamento: carrinho.agendamentoSelecionado,
          saldoUsado: _saldoUsado,
        ),
    };
    await Navigator.push(context, MaterialPageRoute(builder: (_) => tela));
    if (!mounted) return;
    if (context.read<CarrinhoProvider>().itens.isEmpty) {
      _novaVenda();
    } else {
      _painelFoco.requestFocus();
    }
  }

  void _novaVenda() {
    setState(() {
      _fase = _Fase.montando;
      _vendaRegistrada = null;
      _metodo = '';
      _saldoUsado = 0;
      _erro = null;
      _destaque = 0;
    });
    _buscaController.clear();
    _cupomController.clear();
    _recebidoController.clear();
    _buscaFoco.requestFocus();
  }

  void _abrirRecibo() {
    final venda = _vendaRegistrada;
    if (venda == null) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => ReciboScreen(venda: venda)));
  }

  List<String> _metodosAtivos() {
    const conhecidos = {
      'Dinheiro',
      'Pix',
      'Cartão de Débito',
      'Cartão de Crédito',
      'Link de Pagamento',
      'Outros',
    };
    return (context.read<MetodosPagamentoProvider>().metodos ?? const []).where(conhecidos.contains).toList();
  }

  // ───────────────────────── teclado ─────────────────────────

  bool get _telaAtiva =>
      mounted &&
      (ModalRoute.of(context)?.isCurrent ?? true) &&
      TickerMode.valuesOf(context).enabled &&
      MediaQuery.sizeOf(context).width >= VenderPcScreen.larguraPc;

  /// Atalhos da tela inteira. Ouvinte global (como o F2/F3/F4 do menu)
  /// porque o cursor fica na busca e o campo de texto seguraria as teclas.
  bool _tecla(KeyEvent evento) {
    if (evento is! KeyDownEvent && evento is! KeyRepeatEvent) return false;
    if (!_telaAtiva) return false;
    final tecla = evento.logicalKey;
    final repetida = evento is KeyRepeatEvent;

    switch (_fase) {
      case _Fase.concluida:
        if (repetida) return false;
        if (tecla == LogicalKeyboardKey.enter || tecla == LogicalKeyboardKey.numpadEnter || tecla == LogicalKeyboardKey.f2) {
          _novaVenda();
          return true;
        }
        if (tecla == LogicalKeyboardKey.keyR) {
          _abrirRecibo();
          return true;
        }
        return false;

      case _Fase.pagando:
        if (repetida) return false;
        if (tecla == LogicalKeyboardKey.escape) {
          _voltarAoCarrinho();
          return true;
        }
        if (tecla == LogicalKeyboardKey.f9 ||
            ((tecla == LogicalKeyboardKey.enter || tecla == LogicalKeyboardKey.numpadEnter) && !_recebidoFoco.hasFocus)) {
          _concluir();
          return true;
        }
        if (!_recebidoFoco.hasFocus) {
          final numero = int.tryParse(evento.character ?? '');
          final metodos = _metodosAtivos();
          if (numero != null && numero >= 1 && numero <= metodos.length) {
            _escolherMetodo(metodos[numero - 1]);
            return true;
          }
        }
        return false;

      case _Fase.montando:
        if (_cupomFoco.hasFocus) return false;
        final buscaVazia = _buscaController.text.isEmpty;
        if (tecla == LogicalKeyboardKey.f2 && !repetida) {
          _focarBusca();
          return true;
        }
        if (tecla == LogicalKeyboardKey.f8 && !repetida) {
          _escolherCliente();
          return true;
        }
        if (tecla == LogicalKeyboardKey.f9 && !repetida) {
          _irPagar();
          return true;
        }
        if (tecla == LogicalKeyboardKey.escape && !repetida) {
          if (buscaVazia) return false;
          _buscaController.clear();
          setState(() => _destaque = 0);
          return true;
        }
        if (tecla == LogicalKeyboardKey.arrowDown || tecla == LogicalKeyboardKey.arrowUp) {
          _moverDestaque(tecla == LogicalKeyboardKey.arrowDown ? 1 : -1);
          return true;
        }
        if ((tecla == LogicalKeyboardKey.enter || tecla == LogicalKeyboardKey.numpadEnter) &&
            !_buscaFoco.hasFocus &&
            !repetida) {
          _enterNaBusca();
          return true;
        }
        final carrinho = context.read<CarrinhoProvider>();
        final item = _itemSelecionado(carrinho);
        if (item == null) return _digitarNaBusca(evento);
        final mais = tecla == LogicalKeyboardKey.numpadAdd || (buscaVazia && evento.character == '+');
        final menos = tecla == LogicalKeyboardKey.numpadSubtract || (buscaVazia && evento.character == '-');
        if (mais || menos) {
          _mudarQuantidade(item, item.quantidade + (mais ? 1 : -1));
          return true;
        }
        if (tecla == LogicalKeyboardKey.delete && buscaVazia && !repetida) {
          context.read<CarrinhoProvider>().removerProduto(item.produto.id!);
          setState(() => _itemSelecionadoId = null);
          return true;
        }
        return _digitarNaBusca(evento);
    }
  }

  /// Letra ou número digitado sem nenhum campo com o cursor (depois de um
  /// clique fora, por exemplo) vai pra busca em vez de se perder.
  bool _digitarNaBusca(KeyEvent evento) {
    final c = evento.character;
    if (c == null || c.length != 1 || c.codeUnitAt(0) < 32 || c.codeUnitAt(0) == 127) return false;
    final foco = FocusManager.instance.primaryFocus;
    if (_buscaFoco.hasFocus || (foco != null && foco != _painelFoco && foco.context?.findAncestorWidgetOfExactType<EditableText>() != null)) return false;
    final texto = _buscaController.text + c;
    _buscaController.value = TextEditingValue(text: texto, selection: TextSelection.collapsed(offset: texto.length));
    _buscaFoco.requestFocus();
    setState(() => _destaque = 0);
    return true;
  }

  // ───────────────────────── visual ─────────────────────────

  String _moeda(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

  Color get _verde => AppTheme.tomAdaptavel(Colors.green, Theme.of(context).brightness);
  Color get _vermelho => AppTheme.tomAdaptavel(Colors.red, Theme.of(context).brightness);
  Color get _tinta => Theme.of(context).colorScheme.primary.withValues(alpha: 0.12);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final carrinho = context.watch<CarrinhoProvider>();

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: IgnorePointer(
              ignoring: _fase != _Fase.montando,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: _fase == _Fase.montando ? 1 : 0.4,
                child: _ladoProdutos(colorScheme, carrinho),
              ),
            ),
          ),
          Container(
            width: 440,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border(left: BorderSide(color: colorScheme.outlineVariant)),
            ),
            child: Focus(
              focusNode: _painelFoco,
              child: switch (_fase) {
                _Fase.montando => _painelCarrinho(colorScheme, carrinho),
                _Fase.pagando => _painelPagamento(colorScheme, carrinho),
                _Fase.concluida => _painelConcluida(colorScheme),
              },
            ),
          ),
        ],
      ),
    );
  }

  // ───── esquerda: busca + produtos ─────

  Widget _ladoProdutos(ColorScheme colorScheme, CarrinhoProvider carrinho) {
    final produtos = context.watch<ProdutoProvider>().produtos;
    final kits = context.watch<KitProdutoProvider>().kits;
    final categorias = ['Tudo', ...{for (final p in produtos) p.categoria}.where((c) => c.isNotEmpty).toList()..sort(), _categoriaKits];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _barraTopo(colorScheme),
                const SizedBox(height: 14),
                _campoBusca(colorScheme),
                const SizedBox(height: 14),
                SizedBox(
                  height: 32,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: categorias.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (_, i) => _chipCategoria(colorScheme, categorias[i]),
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      border: Border.all(color: colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: _carregando || (produtos.isEmpty && context.watch<ProdutoProvider>().carregando)
                        ? const Center(child: CircularProgressIndicator())
                        : _naKits
                            ? _listaKits(colorScheme, _kitsFiltrados(kits))
                            : _listaProdutos(colorScheme, _produtosFiltrados(produtos), carrinho),
                  ),
                ),
                const SizedBox(height: 14),
              ],
            ),
          ),
        ),
        _rodapeAtalhos(colorScheme),
      ],
    );
  }

  Widget _barraTopo(ColorScheme colorScheme) {
    return Row(
      children: [
        Expanded(child: Text('Vender', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: colorScheme.onSurface))),
        _botaoContorno(
          colorScheme,
          rotulo: 'Conversas do WhatsApp',
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ConversasWhatsappScreen())),
        ),
        const SizedBox(width: 12),
        _botaoContorno(
          colorScheme,
          rotulo: 'Carrinhos do dia',
          contador: _carrinhosDoDia,
          onPressed: _abrirCarrinhosDoDia,
        ),
        const SizedBox(width: 12),
        _botaoContorno(
          colorScheme,
          rotulo: '+ Cadastrar produto',
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CadastroProdutoScreen())),
        ),
      ],
    );
  }

  Widget _botaoContorno(ColorScheme colorScheme,
      {required String rotulo, required VoidCallback? onPressed, int? contador, double altura = 36}) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: Size(0, altura),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        foregroundColor: colorScheme.onSurface,
        backgroundColor: colorScheme.surface,
        side: BorderSide(color: colorScheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w400),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(rotulo),
          if (contador != null && contador > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              decoration: BoxDecoration(color: colorScheme.primary, borderRadius: BorderRadius.circular(9)),
              child: Text('$contador',
                  style: TextStyle(color: colorScheme.onPrimary, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _campoBusca(ColorScheme colorScheme) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              border: Border.all(color: colorScheme.primary, width: 2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(Icons.search, size: 22, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _buscaController,
                    focusNode: _buscaFoco,
                    autofocus: true,
                    style: const TextStyle(fontSize: 18),
                    decoration: const InputDecoration(
                      hintText: 'Buscar produto ou bipar o código de barras',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (_) => setState(() => _destaque = 0),
                    onSubmitted: (_) => _enterNaBusca(),
                  ),
                ),
                Icon(Icons.qr_code_scanner, size: 18, color: colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Text('bipou, entrou no carrinho', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          height: 52,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.outlineVariant),
            borderRadius: BorderRadius.circular(8),
            color: colorScheme.surface,
          ),
          child: Row(
            children: [
              _segmento(colorScheme, 'Lista', !_modoGrade, () => setState(() => _modoGrade = false)),
              _segmento(colorScheme, 'Grade', _modoGrade, () => setState(() => _modoGrade = true)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _segmento(ColorScheme colorScheme, String rotulo, bool ativo, VoidCallback onTap) {
    return Material(
      color: ativo ? _tinta : colorScheme.surface,
      child: InkWell(
        onTap: () {
          onTap();
          _buscaFoco.requestFocus();
        },
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(rotulo,
              style: TextStyle(
                fontSize: 13,
                fontWeight: ativo ? FontWeight.w600 : FontWeight.w400,
                color: ativo ? colorScheme.primary : colorScheme.onSurface,
              )),
        ),
      ),
    );
  }

  Widget _chipCategoria(ColorScheme colorScheme, String categoria) {
    final ativa = _categoria == categoria;
    return Material(
      color: ativa ? colorScheme.primary : colorScheme.surface,
      shape: StadiumBorder(side: ativa ? BorderSide.none : BorderSide(color: colorScheme.outlineVariant)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: () {
          setState(() {
            _categoria = categoria;
            _destaque = 0;
          });
          _buscaFoco.requestFocus();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            categoria == _categoriaKits ? 'Kits' : categoria,
            style: TextStyle(
              fontSize: 13,
              fontWeight: ativa ? FontWeight.w600 : FontWeight.w400,
              color: ativa ? colorScheme.onPrimary : colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }

  Widget _vazio(ColorScheme colorScheme, String texto) => Center(
        child: Text(texto, style: TextStyle(color: colorScheme.onSurfaceVariant)),
      );

  Widget _listaProdutos(ColorScheme colorScheme, List<Produto> lista, CarrinhoProvider carrinho) {
    if (lista.isEmpty) return _vazio(colorScheme, 'Nenhum produto encontrado — tente outra busca ou categoria.');
    final destaque = _destaque.clamp(0, lista.length - 1);
    final qtdNoCarrinho = <String, int>{};
    for (final i in carrinho.itens) {
      qtdNoCarrinho[i.produto.id!] = (qtdNoCarrinho[i.produto.id!] ?? 0) + i.quantidade;
    }

    if (_modoGrade) {
      return GridView.builder(
        padding: const EdgeInsets.all(12),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.72,
        ),
        itemCount: lista.length,
        itemBuilder: (_, i) => _cartaoGrade(colorScheme, lista[i], i == destaque, qtdNoCarrinho[lista[i].id]),
      );
    }

    return Column(
      children: [
        _linhaGrade(
          colorScheme,
          cabecalho: true,
          foto: const SizedBox(),
          nome: _textoCab(colorScheme, 'Produto'),
          preco: _textoCab(colorScheme, 'Preço', direita: true),
          estoque: _textoCab(colorScheme, 'Estoque', direita: true),
          noCarrinho: _textoCab(colorScheme, 'No carrinho', direita: true),
        ),
        Divider(height: 1, color: colorScheme.outlineVariant),
        Expanded(
          child: ListView.builder(
            controller: _listaScroll,
            itemExtent: _alturaLinha,
            itemCount: lista.length,
            itemBuilder: (_, i) => _linhaProduto(colorScheme, lista[i], i, i == destaque, qtdNoCarrinho[lista[i].id]),
          ),
        ),
      ],
    );
  }

  Widget _textoCab(ColorScheme colorScheme, String t, {bool direita = false}) => Text(
        t,
        textAlign: direita ? TextAlign.right : TextAlign.left,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colorScheme.onSurfaceVariant),
      );

  Widget _linhaGrade(
    ColorScheme colorScheme, {
    bool cabecalho = false,
    required Widget foto,
    required Widget nome,
    required Widget preco,
    required Widget estoque,
    required Widget noCarrinho,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: cabecalho ? 10 : 8),
      child: Row(
        children: [
          SizedBox(width: 52, child: Align(alignment: Alignment.centerLeft, child: foto)),
          const SizedBox(width: 12),
          Expanded(child: nome),
          const SizedBox(width: 12),
          SizedBox(width: 140, child: preco),
          const SizedBox(width: 12),
          SizedBox(width: 110, child: estoque),
          const SizedBox(width: 12),
          SizedBox(width: 90, child: noCarrinho),
        ],
      ),
    );
  }

  String _imagemUrl(Produto p) =>
      p.imagemUrl.isNotEmpty ? p.imagemUrlExibicao : 'http://imagens.lukz.com.br/produtos/${p.codigoBarras}.png';

  Widget _foto(ColorScheme colorScheme, String url, {double tamanho = 40, IconData icone = Icons.image_not_supported_outlined}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: tamanho,
        height: tamanho,
        color: colorScheme.surfaceContainerHighest,
        child: url.isEmpty
            ? Icon(icone, size: 18, color: colorScheme.onSurfaceVariant)
            : CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Icon(icone, size: 18, color: colorScheme.onSurfaceVariant),
              ),
      ),
    );
  }

  bool _temPromo(Produto p) => p.precoVendaAtual < p.preco;

  Widget _linhaProduto(ColorScheme colorScheme, Produto p, int indice, bool destacado, int? noCarrinho) {
    final semEstoque = p.estoqueAtual <= 0;
    final sub = [if ((p.empresa ?? '').isNotEmpty) p.empresa!, if (p.codigoBarras.isNotEmpty) p.codigoBarras].join(' · ');
    return Material(
      color: destacado ? _tinta : Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() => _destaque = indice);
          _adicionarProduto(p);
          _buscaFoco.requestFocus();
        },
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: destacado ? colorScheme.primary : Colors.transparent, width: 4),
              bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
          ),
          child: Opacity(
            opacity: semEstoque ? 0.5 : 1,
            child: _linhaGrade(
              colorScheme,
              foto: _foto(colorScheme, _imagemUrl(p)),
              nome: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(p.nome, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  if (sub.isNotEmpty)
                    Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                ],
              ),
              preco: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_temPromo(p))
                    Text('R\$ ${_moeda(p.preco)}',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant, decoration: TextDecoration.lineThrough)),
                  Text('R\$ ${_moeda(p.precoVendaAtual)}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                ],
              ),
              estoque: Text(
                semEstoque ? 'Sem estoque' : '${p.estoqueAtual} un.',
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: semEstoque ? FontWeight.w600 : FontWeight.w400,
                  color: semEstoque ? _vermelho : colorScheme.onSurfaceVariant,
                ),
              ),
              noCarrinho: Text(
                noCarrinho == null ? '' : '$noCarrinho',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: colorScheme.primary),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cartaoGrade(ColorScheme colorScheme, Produto p, bool destacado, int? noCarrinho) {
    final semEstoque = p.estoqueAtual <= 0;
    return Material(
      color: destacado ? _tinta : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: destacado ? colorScheme.primary : colorScheme.outlineVariant, width: destacado ? 2 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          _adicionarProduto(p);
          _buscaFoco.requestFocus();
        },
        child: Opacity(
          opacity: semEstoque ? 0.5 : 1,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: double.infinity,
                      color: colorScheme.surfaceContainerHighest,
                      child: CachedNetworkImage(
                        imageUrl: _imagemUrl(p),
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Icon(Icons.image_not_supported_outlined, color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(p.nome, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                Text('R\$ ${_moeda(p.precoVendaAtual)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                Text(
                  semEstoque ? 'Sem estoque' : '${p.estoqueAtual} em estoque${noCarrinho == null ? '' : ' · $noCarrinho no carrinho'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: semEstoque ? _vermelho : colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _listaKits(ColorScheme colorScheme, List<KitProduto> kits) {
    if (kits.isEmpty) return _vazio(colorScheme, 'Nenhum kit encontrado.');
    final destaque = _destaque.clamp(0, kits.length - 1);
    return Column(
      children: [
        _linhaGrade(
          colorScheme,
          cabecalho: true,
          foto: const SizedBox(),
          nome: _textoCab(colorScheme, 'Kit'),
          preco: _textoCab(colorScheme, 'Preço', direita: true),
          estoque: _textoCab(colorScheme, 'Disponível', direita: true),
          noCarrinho: const SizedBox(),
        ),
        Divider(height: 1, color: colorScheme.outlineVariant),
        Expanded(
          child: ListView.builder(
            controller: _listaScroll,
            itemExtent: _alturaLinha,
            itemCount: kits.length,
            itemBuilder: (_, i) {
              final kit = kits[i];
              final destacado = i == destaque;
              final semEstoque = kit.estoqueDisponivel <= 0;
              return Material(
                color: destacado ? _tinta : Colors.transparent,
                child: InkWell(
                  onTap: semEstoque
                      ? null
                      : () {
                          setState(() => _destaque = i);
                          _adicionarKit(kit);
                          _buscaFoco.requestFocus();
                        },
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: destacado ? colorScheme.primary : Colors.transparent, width: 4),
                        bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                      ),
                    ),
                    child: Opacity(
                      opacity: semEstoque ? 0.5 : 1,
                      child: _linhaGrade(
                        colorScheme,
                        foto: _foto(colorScheme, kit.imagemUrl, icone: Icons.card_giftcard),
                        nome: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(kit.nome, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                            Text('Kit · ${kit.componentes.length} produtos', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                          ],
                        ),
                        preco: Text('R\$ ${_moeda(kit.precoPromocional ?? kit.preco)}',
                            textAlign: TextAlign.right, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        estoque: Text(
                          semEstoque ? 'Sem estoque' : '${kit.estoqueDisponivel} kits',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 13, color: semEstoque ? _vermelho : colorScheme.onSurfaceVariant),
                        ),
                        noCarrinho: const SizedBox(),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _rodapeAtalhos(ColorScheme colorScheme) {
    final atalhos = switch (_fase) {
      _Fase.montando => const [
          ('F2', 'buscar'),
          ('↑↓', 'escolher'),
          ('Enter', 'adicionar'),
          ('+ −', 'quantidade do item'),
          ('Del', 'tirar item'),
          ('F8', 'cliente e entrega'),
          ('F9', 'pagar'),
          ('Esc', 'limpar busca'),
        ],
      _Fase.pagando => const [
          ('1–6', 'forma de pagamento'),
          ('Enter', 'concluir'),
          ('Esc', 'voltar ao carrinho'),
        ],
      _Fase.concluida => const [
          ('Enter', 'nova venda'),
          ('R', 'recibo'),
        ],
    };
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          for (final (tecla, texto) in atalhos) ...[
            _teclaVisual(colorScheme, tecla),
            const SizedBox(width: 5),
            Text(texto, style: TextStyle(fontSize: 12, color: colorScheme.onSurface)),
            const SizedBox(width: 18),
          ],
        ],
      ),
    );
  }

  Widget _teclaVisual(ColorScheme colorScheme, String tecla) => Container(
        constraints: const BoxConstraints(minWidth: 18),
        padding: const EdgeInsets.symmetric(horizontal: 5),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(
            top: BorderSide(color: colorScheme.outline.withValues(alpha: 0.5)),
            left: BorderSide(color: colorScheme.outline.withValues(alpha: 0.5)),
            right: BorderSide(color: colorScheme.outline.withValues(alpha: 0.5)),
            bottom: BorderSide(color: colorScheme.outline.withValues(alpha: 0.5), width: 2),
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(tecla, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      );

  // ───── direita: carrinho ─────

  Widget _painelCarrinho(ColorScheme colorScheme, CarrinhoProvider carrinho) {
    final itens = carrinho.itens;
    final selecionado = _itemSelecionado(carrinho);
    final cliente = carrinho.clienteSelecionado;
    final abaixoDoMinimo = _valorMinimoPedido != null && carrinho.totalCarrinho < _valorMinimoPedido!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  itens.isEmpty
                      ? 'Carrinho'
                      : 'Carrinho · ${carrinho.totalUnidades} ite${carrinho.totalUnidades == 1 ? 'm' : 'ns'}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              if (itens.isNotEmpty && cliente != null) ...[
                _botaoContorno(
                  colorScheme,
                  rotulo: _salvandoOrcamento ? 'Salvando...' : 'Salvar orçamento',
                  altura: 32,
                  onPressed: _salvandoOrcamento ? null : _salvarOrcamento,
                ),
                const SizedBox(width: 8),
              ],
              if (itens.isNotEmpty)
                _botaoContorno(colorScheme, rotulo: 'Esvaziar', altura: 32, onPressed: () {
                  carrinho.limparCarrinho();
                  _buscaFoco.requestFocus();
                }),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: cliente == null ? _semCliente(colorScheme) : _cartaoCliente(colorScheme, carrinho),
        ),
        Expanded(
          child: itens.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Busque ou bipe um produto pra começar.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                  itemCount: itens.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) => _itemCarrinho(colorScheme, itens[i], itens[i].produto.id == selecionado?.produto.id),
                ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _cupomEDesconto(colorScheme, carrinho),
              const SizedBox(height: 10),
              _linhaResumo('Subtotal', 'R\$ ${_moeda(carrinho.subtotal)}'),
              if (carrinho.desconto > 0)
                _linhaResumo(
                  carrinho.cupomAplicado != null ? 'Cupom (${carrinho.cupomAplicado!.codigo})' : 'Desconto',
                  '− R\$ ${_moeda(carrinho.desconto)}',
                  cor: _verde,
                ),
              _linhaResumo(
                cliente == null
                    ? 'Entrega'
                    : (carrinho.zonaEntregaSelecionada == null ? 'Retirada na loja' : 'Entrega · ${carrinho.zonaEntregaSelecionada!.nome}'),
                cliente == null
                    ? 'A calcular'
                    : (carrinho.valorEntregaCalculado == 0
                        ? (carrinho.zonaEntregaSelecionada == null ? 'R\$ 0,00' : 'Frete grátis')
                        : 'R\$ ${_moeda(carrinho.valorEntregaCalculado)}'),
                cor: cliente != null && carrinho.zonaEntregaSelecionada != null && carrinho.valorEntregaCalculado == 0 ? _verde : null,
              ),
              if (carrinho.valorFaltanteParaFreteGratis > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('Faltam R\$ ${_moeda(carrinho.valorFaltanteParaFreteGratis)} para frete grátis',
                      style: TextStyle(fontSize: 12, color: _vermelho)),
                ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  const Expanded(child: Text('Total', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
                  Text('R\$ ${_moeda(carrinho.totalCarrinho)}', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                ],
              ),
              if (abaixoDoMinimo && itens.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Pedido mínimo: R\$ ${_moeda(_valorMinimoPedido!)} (faltam R\$ ${_moeda(_valorMinimoPedido! - carrinho.totalCarrinho)})',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: _vermelho),
                  ),
                ),
              const SizedBox(height: 10),
              _botaoPrincipal(
                colorScheme,
                rotulo: itens.isNotEmpty && cliente == null ? 'Escolher cliente · F8' : 'Pagar · F9',
                onPressed: itens.isEmpty
                    ? null
                    : cliente == null
                        ? _escolherCliente
                        : (_podePagar(carrinho) ? _irPagar : null),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _botaoPrincipal(ColorScheme colorScheme, {required String rotulo, required VoidCallback? onPressed}) {
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      child: Text(rotulo),
    );
  }

  Widget _semCliente(ColorScheme colorScheme) {
    return OutlinedButton.icon(
      onPressed: _escolherCliente,
      icon: const Icon(Icons.person_add_alt, size: 18),
      label: const Text('Escolher cliente e entrega · F8'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Widget _cartaoCliente(ColorScheme colorScheme, CarrinhoProvider carrinho) {
    final cliente = carrinho.clienteSelecionado!;
    final retirada = carrinho.zonaEntregaSelecionada == null;
    final agendamento = carrinho.agendamentoSelecionado;
    final distancia = cliente.rangeDistancia;
    final endereco = [
      if (cliente.enderecoCompleto.isNotEmpty) cliente.enderecoExibicao else cliente.celular,
      if (distancia != null) '${distancia.toStringAsFixed(1).replaceAll('.', ',')} km',
    ].join(' · ');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 17,
                backgroundColor: _tinta,
                child: Text(cliente.nome.isNotEmpty ? cliente.nome[0].toUpperCase() : '?',
                    style: TextStyle(fontWeight: FontWeight.w700, color: colorScheme.primary)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(cliente.nome, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    Text(endereco, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              TextButton(
                onPressed: _escolherCliente,
                style: TextButton.styleFrom(
                  backgroundColor: colorScheme.surfaceContainer,
                  foregroundColor: colorScheme.onSurface,
                  minimumSize: const Size(0, 30),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text.rich(TextSpan(children: [
                  TextSpan(text: 'Trocar '),
                  TextSpan(text: 'F8', style: TextStyle(fontWeight: FontWeight.w700)),
                ]), style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _pilula(
                colorScheme,
                carrinho.zonaEntregaSelecionada != null ? 'Entrega · ${carrinho.zonaEntregaSelecionada!.nome}' : 'Entrega',
                !retirada,
                () => retirada ? resolverZonaEntregaParaCliente(context, cliente, carrinho) : null,
              ),
              _pilula(colorScheme, 'Retirar na loja', retirada, () => carrinho.selecionarZonaEntrega(null)),
              _pilula(colorScheme, 'Quero agora', agendamento == null, () => carrinho.selecionarAgendamento(null)),
              _pilula(colorScheme, agendamento == null ? 'Agendar' : 'Agendado · ${agendamento.label}', agendamento != null, _escolherCliente),
              if (cliente.saldo > 0)
                Text('Saldo R\$ ${_moeda(cliente.saldo)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _verde)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pilula(ColorScheme colorScheme, String texto, bool ativa, VoidCallback? onTap) {
    return Material(
      color: ativa ? _tinta : colorScheme.surfaceContainer,
      shape: const StadiumBorder(),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text(texto,
              style: TextStyle(
                fontSize: 12,
                fontWeight: ativa ? FontWeight.w600 : FontWeight.w400,
                color: ativa ? colorScheme.primary : colorScheme.onSurface,
              )),
        ),
      ),
    );
  }

  Widget _itemCarrinho(ColorScheme colorScheme, ItemCarrinho item, bool selecionado) {
    return Material(
      color: selecionado ? _tinta : Theme.of(context).scaffoldBackgroundColor,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () {
          setState(() => _itemSelecionadoId = item.produto.id);
          _buscaFoco.requestFocus();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.produto.nome, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                    Text('R\$ ${_moeda(item.precoUnitario)} un.', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                decoration: BoxDecoration(color: colorScheme.surfaceContainer, borderRadius: BorderRadius.circular(16)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _botaoQtd(Icons.remove, 'Menos um', () => _mudarQuantidade(item, item.quantidade - 1)),
                    SizedBox(
                      width: 22,
                      child: Text('${item.quantidade}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                    _botaoQtd(Icons.add, 'Mais um', () => _mudarQuantidade(item, item.quantidade + 1)),
                  ],
                ),
              ),
              SizedBox(
                width: 84,
                child: Text('R\$ ${_moeda(item.precoTotalItem)}',
                    textAlign: TextAlign.right, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _botaoQtd(IconData icone, String dica, VoidCallback onPressed) => IconButton(
        onPressed: onPressed,
        tooltip: dica,
        icon: Icon(icone, size: 16),
        constraints: const BoxConstraints.tightFor(width: 28, height: 28),
        padding: EdgeInsets.zero,
        style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
      );

  Widget _cupomEDesconto(ColorScheme colorScheme, CarrinhoProvider carrinho) {
    final cupom = carrinho.cupomAplicado;
    final descontoManual = cupom == null && carrinho.desconto > 0;
    final Widget esquerda;
    if (cupom != null) {
      esquerda = _caixaVerde(colorScheme, 'Cupom "${cupom.codigo}" aplicado', carrinho.removerCupom);
    } else if (descontoManual) {
      esquerda = _caixaVerde(colorScheme, 'Desconto de R\$ ${_moeda(carrinho.desconto)}', () => carrinho.aplicarDesconto(0));
    } else {
      esquerda = SizedBox(
        height: 34,
        child: TextField(
          controller: _cupomController,
          focusNode: _cupomFoco,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: 'Cupom de desconto',
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            errorText: null,
            suffixIcon: TextButton(
              onPressed: carrinho.validandoCupom ? null : () => _aplicarCupom(carrinho),
              child: Text(carrinho.validandoCupom ? '...' : 'Aplicar', style: const TextStyle(fontSize: 12)),
            ),
          ),
          onSubmitted: (_) => _aplicarCupom(carrinho),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: esquerda),
            const SizedBox(width: 8),
            _botaoContorno(colorScheme, rotulo: 'Desconto %', altura: 34, onPressed: carrinho.itens.isEmpty ? null : _aplicarDesconto),
          ],
        ),
        if (carrinho.erroCupom != null && cupom == null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(carrinho.erroCupom!, style: TextStyle(fontSize: 12, color: _vermelho)),
          ),
      ],
    );
  }

  Future<void> _aplicarCupom(CarrinhoProvider carrinho) async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;
    await carrinho.aplicarCupom(empresaId, _cupomController.text);
    if (mounted && carrinho.cupomAplicado != null) {
      _cupomController.clear();
      _buscaFoco.requestFocus();
    }
  }

  Widget _caixaVerde(ColorScheme colorScheme, String texto, VoidCallback onRemover) {
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        color: _verde.withValues(alpha: 0.1),
        border: Border.all(color: _verde),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(texto,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _verde)),
          ),
          TextButton(
            onPressed: onRemover,
            style: TextButton.styleFrom(minimumSize: const Size(0, 30), padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: const Text('Remover', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _linhaResumo(String rotulo, String valor, {Color? cor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(rotulo, style: TextStyle(fontSize: 14, color: cor))),
          Text(valor, style: TextStyle(fontSize: 14, color: cor)),
        ],
      ),
    );
  }

  // ───── direita: pagamento ─────

  Widget _painelPagamento(ColorScheme colorScheme, CarrinhoProvider carrinho) {
    final cliente = carrinho.clienteSelecionado!;
    final total = _aPagar(carrinho);
    final metodos = _metodosAtivos();
    final modalidade = carrinho.zonaEntregaSelecionada == null
        ? 'retira na loja'
        : (carrinho.agendamentoSelecionado == null ? 'entrega agora' : 'entrega ${carrinho.agendamentoSelecionado!.label}');
    final detalhe = [
      'Subtotal R\$ ${_moeda(carrinho.subtotal)}',
      if (carrinho.desconto > 0) '${carrinho.cupomAplicado != null ? 'cupom' : 'desconto'} − R\$ ${_moeda(carrinho.desconto)}',
      if (carrinho.zonaEntregaSelecionada != null)
        carrinho.valorEntregaCalculado == 0 ? 'frete grátis' : 'entrega R\$ ${_moeda(carrinho.valorEntregaCalculado)}',
      if (_saldoUsado > 0) 'saldo − R\$ ${_moeda(_saldoUsado)}',
    ].join(' · ');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Row(
            children: [
              _botaoContorno(colorScheme, rotulo: '← Carrinho  Esc', altura: 32, onPressed: _voltarAoCarrinho),
              const Expanded(
                child: Text('Pagamento', textAlign: TextAlign.right, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: BorderRadius.circular(10)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Text('${cliente.nome} · $modalidade', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13))),
                  Text('${carrinho.totalUnidades} ite${carrinho.totalUnidades == 1 ? 'm' : 'ns'}',
                      style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
                ],
              ),
              const SizedBox(height: 4),
              Text(detalhe, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
              const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  const Expanded(child: Text('A pagar', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
                  Text('R\$ ${_moeda(total)}', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
                ],
              ),
            ],
          ),
        ),
        if (cliente.saldo > 0)
          Container(
            margin: const EdgeInsets.fromLTRB(20, 10, 20, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(border: Border.all(color: colorScheme.outlineVariant), borderRadius: BorderRadius.circular(10)),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      const TextSpan(text: 'Saldo do cliente: ', style: TextStyle(fontWeight: FontWeight.w700)),
                      TextSpan(text: 'R\$ ${_moeda(cliente.saldo)}'),
                      if (_saldoUsado > 0) TextSpan(text: '  (usando R\$ ${_moeda(_saldoUsado)})', style: TextStyle(color: _verde)),
                    ]),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                OutlinedButton(
                  onPressed: () => setState(() {
                    _saldoUsado = _saldoUsado > 0 ? 0 : math.min(cliente.saldo, _antesDoSaldo(carrinho));
                    _recebidoController.clear();
                  }),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    foregroundColor: _saldoUsado > 0 ? _vermelho : _verde,
                    side: BorderSide(color: _saldoUsado > 0 ? _vermelho : _verde),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  child: Text(_saldoUsado > 0 ? 'Remover saldo' : 'Usar saldo'),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            children: [
              Text.rich(
                TextSpan(children: [
                  const TextSpan(text: 'Forma de pagamento ', style: TextStyle(fontWeight: FontWeight.w700)),
                  TextSpan(text: '(teclas 1 a ${metodos.length})', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                ]),
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 128 / 58,
                children: [
                  for (final (i, m) in metodos.indexed) _botaoMetodo(colorScheme, i + 1, m),
                ],
              ),
              const SizedBox(height: 14),
              if (_metodo.isNotEmpty) _detalheMetodo(colorScheme, total),
              if (_erro != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: _vermelho.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Não foi possível registrar a venda.', style: TextStyle(fontWeight: FontWeight.w700, color: _vermelho)),
                      const SizedBox(height: 4),
                      Text(_erro!, style: const TextStyle(fontSize: 13)),
                      if (_erro!.toLowerCase().contains('estoque')) ...[
                        const SizedBox(height: 8),
                        OutlinedButton(onPressed: _voltarAoCarrinho, child: const Text('Voltar e ajustar o carrinho')),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)))),
          child: _botaoPrincipal(
            colorScheme,
            rotulo: _registrando
                ? 'Registrando...'
                : _metodo.isEmpty
                    ? 'Escolha a forma de pagamento'
                    : _metodoNoPainel
                        ? 'Concluir venda · Enter'
                        : 'Continuar no ${_rotuloMetodo(_metodo)} · Enter',
            onPressed: _metodo.isEmpty || _registrando ? null : _concluir,
          ),
        ),
      ],
    );
  }

  String _rotuloMetodo(String metodo) => switch (metodo) {
        'Cartão de Débito' => 'Débito',
        'Cartão de Crédito' => 'Crédito',
        'Link de Pagamento' => 'Link',
        'Outros' => 'Dividir',
        _ => metodo,
      };

  Widget _botaoMetodo(ColorScheme colorScheme, int tecla, String metodo) {
    final sel = _metodo == metodo;
    return Material(
      color: sel ? _tinta : colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: sel ? colorScheme.primary : colorScheme.outlineVariant, width: sel ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _escolherMetodo(metodo),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('$tecla', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
            Text(_rotuloMetodo(metodo),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                  color: sel ? colorScheme.primary : colorScheme.onSurface,
                )),
          ],
        ),
      ),
    );
  }

  Widget _detalheMetodo(ColorScheme colorScheme, double total) {
    final caixa = BoxDecoration(
      border: Border.all(color: colorScheme.primary, width: 2),
      borderRadius: BorderRadius.circular(12),
    );
    if (_metodo == 'Dinheiro') {
      final recebido = _recebidoController.text.trim().isEmpty ? total : _recebido;
      final troco = recebido - total;
      final arredondados = <double>{
        for (final passo in const [10.0, 50.0, 100.0]) ((total / passo).ceil() * passo),
      }.where((v) => v > total + 0.001).toList()
        ..sort();
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: caixa,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Valor recebido em dinheiro', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            TextField(
              controller: _recebidoController,
              focusNode: _recebidoFoco,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [MoedaInputFormatter()],
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                prefixText: 'R\$ ',
                hintText: _moeda(total),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _concluir(),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final (i, v) in [null, ...arredondados.take(3)].indexed) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: _botaoContorno(
                      colorScheme,
                      rotulo: v == null ? 'Valor exato' : 'R\$ ${v.toStringAsFixed(0)}',
                      altura: 32,
                      onPressed: () {
                        _recebidoController.text = ClienteValidators.formatarMoeda(v ?? total);
                        setState(() {});
                        _recebidoFoco.requestFocus();
                      },
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: (troco >= -0.001 ? _verde : _vermelho).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(troco >= -0.001 ? 'Troco' : 'Falta',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: troco >= -0.001 ? _verde : _vermelho)),
                  ),
                  Text('R\$ ${_moeda(troco.abs() < 0.001 ? 0 : troco.abs())}',
                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: troco >= -0.001 ? _verde : _vermelho)),
                ],
              ),
            ),
          ],
        ),
      );
    }
    final texto = switch (_metodo) {
      'Cartão de Débito' => 'Passe o cartão na maquininha e conclua.',
      'Pix' => 'Abre a tela de Pix de sempre (chave da loja pra copiar).',
      'Cartão de Crédito' => 'Abre a tela de crédito de sempre (parcelas).',
      'Link de Pagamento' => 'Abre a tela de link de pagamento de sempre.',
      _ => 'Abre a tela de pagamento dividido de sempre.',
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: caixa,
      child: Text(texto, style: const TextStyle(fontSize: 13)),
    );
  }

  // ───── direita: concluída ─────

  Widget _painelConcluida(ColorScheme colorScheme) {
    final venda = _vendaRegistrada;
    if (venda == null) return const SizedBox();
    final numero = venda.numeroSequencial == null ? '' : ' · Pedido #${venda.numeroSequencial}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(color: _verde.withValues(alpha: 0.12), shape: BoxShape.circle),
                  child: Icon(Icons.check_rounded, size: 46, color: _verde),
                ),
                const SizedBox(height: 10),
                const Text('Venda concluída', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('${venda.cliente.nome} · ${_rotuloMetodo(venda.metodoPagamento)}$numero',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Theme.of(context).scaffoldBackgroundColor, borderRadius: BorderRadius.circular(12)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('R\$ ${_moeda(venda.valorTotal)}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                      if (venda.desconto > 0) _linhaConcluida(colorScheme, 'Desconto aplicado', '− R\$ ${_moeda(venda.desconto)}'),
                      if (venda.saldoUsado > 0) _linhaConcluida(colorScheme, 'Saldo do cliente', '− R\$ ${_moeda(venda.saldoUsado)}'),
                      if (venda.metodoPagamento == 'Dinheiro') ...[
                        _linhaConcluida(colorScheme, 'Valor pago', 'R\$ ${_moeda(venda.valorPago)}'),
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Row(
                            children: [
                              Expanded(child: Text('Troco', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _verde))),
                              Text('R\$ ${_moeda(venda.troco)}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: _verde)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: _abrirRecibo,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
              side: BorderSide(color: colorScheme.primary),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            child: const Text('Recibo / enviar no WhatsApp · R'),
          ),
          const SizedBox(height: 8),
          _botaoPrincipal(colorScheme, rotulo: 'Nova venda · Enter', onPressed: _novaVenda),
          const SizedBox(height: 8),
          Text('a busca já volta com o cursor pronto pro próximo cliente',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _linhaConcluida(ColorScheme colorScheme, String rotulo, String valor) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          children: [
            Expanded(child: Text(rotulo, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant))),
            Text(valor, style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant)),
          ],
        ),
      );
}
