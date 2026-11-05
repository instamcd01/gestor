import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/cliente.dart';
import '../providers/auth_provider.dart';
import '../providers/cliente_provider.dart';
import '../providers/modulo_provider.dart';
import '../repositories/cliente_repository.dart';
import '../theme/app_theme.dart';
import '../utils/app_destinos.dart';
import '../utils/busca_utils.dart';
import '../utils/cliente_validators.dart';
import '../widgets/categoria_cliente_badge.dart';
import '../widgets/estado_erro_lista.dart';
import '../widgets/faixa_rolavel.dart';
import '../widgets/importar_clientes_planilha.dart';
import '../widgets/menu_secao.dart';
import 'adicionar_cliente_screen.dart';
import 'cliente_detalhes_screen.dart';
import 'clientes_hub_screen.dart';
import 'vendas_screen.dart';
import 'vender_pc_screen.dart';

enum _Filtro { todos, vip, regular, novo, inativo, comSaldo, semComprar }

enum _Coluna { cliente, celular, bairro, compras, total, ultima, saldo, petcash }

/// Quantos dias sem comprar contam como "sumiu" (filtro e data em vermelho).
const _diasSemComprar = 60;

/// Clientes no PC (janela ≥ 1200 px): tabela ordenável com filtros e o cliente
/// aberto ao lado, sem passar pelo menu de Relacionamento. A ficha do painel é
/// a própria `ClienteDetalhesScreen` (modo embutida) — nada de regra duplicada.
/// No celular segue o caminho de sempre (Hub → `ClientesScreen` → ficha).
class ClientesPc extends StatefulWidget {
  const ClientesPc({super.key});

  static const larguraPc = 1200.0;

  @override
  State<ClientesPc> createState() => _ClientesPcState();
}

class _ClientesPcState extends State<ClientesPc> with SingleTickerProviderStateMixin {
  final _buscaController = TextEditingController();
  final _buscaFoco = FocusNode(debugLabel: 'busca-clientes');
  final _tabelaFoco = FocusNode(debugLabel: 'tabela-clientes');
  final _rolagem = ScrollController();
  late final TabController _abas;

  final _kyteRepository = ClienteRepository();
  List<Cliente>? _kyte;
  String? _erroKyte;

  _Filtro _filtro = _Filtro.todos;
  _Coluna _ordem = _Coluna.total;
  bool _crescente = false;
  String? _selecionadoId;
  bool _visivel = false;
  DateTime? _ultimoClique;
  String? _ultimoCliqueId;

  static const _alturaLinha = 46.0;

  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  bool get _naAbaKyte => _abas.index == 1;

  @override
  void initState() {
    super.initState();
    _abas = TabController(length: 2, vsync: this);
    _abas.addListener(_trocouAba);
    HardwareKeyboard.instance.addHandler(_teclaGlobal);
  }

  /// A tela fica montada por trás (IndexedStack do menu) mesmo escondida: só
  /// busca os dados quando aparece, e busca de novo a cada volta — uma venda
  /// feita no Vender muda total gasto e última compra daqui.
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visivel = TickerMode.valuesOf(context).enabled;
    if (visivel && !_visivel) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _recarregar();
        _tabelaFoco.requestFocus();
      });
    }
    _visivel = visivel;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_teclaGlobal);
    _abas.removeListener(_trocouAba);
    _abas.dispose();
    _buscaController.dispose();
    _buscaFoco.dispose();
    _tabelaFoco.dispose();
    _rolagem.dispose();
    super.dispose();
  }

  // ───────────────────────── dados ─────────────────────────

  Future<void> _recarregar() async {
    await context.read<ClientProvider>().carregarClientes();
    if (mounted && (_kyte != null || _naAbaKyte)) await _carregarKyte();
  }

  Future<void> _carregarKyte() async {
    try {
      final lista = await _kyteRepository.listarHistoricoKyte();
      if (mounted) {
        setState(() {
          _kyte = lista;
          _erroKyte = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _erroKyte = 'Erro ao carregar histórico do Kyte: $e');
    }
  }

  void _trocouAba() {
    if (_abas.indexIsChanging) return;
    setState(() {
      _selecionadoId = null;
      _filtro = _Filtro.todos;
    });
    if (_rolagem.hasClients) _rolagem.jumpTo(0);
    if (_naAbaKyte && _kyte == null) _carregarKyte();
    _tabelaFoco.requestFocus();
  }

  // ───────────────────────── filtros ─────────────────────────

  /// Dias desde a última compra, contados por dia do calendário; null = nunca.
  int? _diasDesde(Cliente c) {
    final u = c.ultimaCompra?.toLocal();
    if (u == null) return null;
    final agora = DateTime.now();
    return DateTime(agora.year, agora.month, agora.day).difference(DateTime(u.year, u.month, u.day)).inDays;
  }

  bool _passaFiltro(Cliente c) {
    final categoria = (c.categoriaCliente ?? '').toLowerCase();
    return switch (_filtro) {
      _Filtro.todos => true,
      _Filtro.vip => categoria == 'vip',
      _Filtro.regular => categoria == 'regular',
      _Filtro.novo => categoria == 'novo',
      _Filtro.inativo => categoria == 'inativo',
      _Filtro.comSaldo => c.saldo > 0,
      _Filtro.semComprar => (_diasDesde(c) ?? -1) >= _diasSemComprar,
    };
  }

  /// Aba Clientes: busca do provider (mesma do celular). Aba Kyte: nome/telefone.
  List<Cliente> _base(ClientProvider provider) {
    if (!_naAbaKyte) return provider.clientesFiltrados;
    final termo = _buscaController.text;
    final kyte = _kyte ?? const <Cliente>[];
    if (termo.trim().isEmpty) return kyte;
    return kyte.where((c) => contemTodasPalavras('${c.nome} ${c.telefoneKyte ?? ''}', termo)).toList();
  }

  List<Cliente> _ordenar(List<Cliente> lista) {
    int compara(Comparable<dynamic>? a, Comparable<dynamic>? b) {
      // Vazio fica sempre no fim, em qualquer direção.
      if (a == null || b == null) return a == null ? (b == null ? 0 : (_crescente ? 1 : -1)) : (_crescente ? -1 : 1);
      return a.compareTo(b);
    }

    int c(Cliente a, Cliente b) => switch (_ordem) {
          _Coluna.cliente => a.nome.toLowerCase().compareTo(b.nome.toLowerCase()),
          _Coluna.celular => a.telefoneContato.compareTo(b.telefoneContato),
          _Coluna.bairro => compara(_vazioNulo(a.bairro.toLowerCase()), _vazioNulo(b.bairro.toLowerCase())),
          _Coluna.compras => (a.quantidadeCompras ?? 0).compareTo(b.quantidadeCompras ?? 0),
          _Coluna.total => (a.totalGasto ?? 0).compareTo(b.totalGasto ?? 0),
          _Coluna.ultima => compara(a.ultimaCompra, b.ultimaCompra),
          _Coluna.saldo => a.saldo.compareTo(b.saldo),
          _Coluna.petcash => a.saldoPetCash.compareTo(b.saldoPetCash),
        };

    return [...lista]..sort((a, b) {
        final x = c(a, b);
        return x != 0 ? (_crescente ? x : -x) : a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
      });
  }

  String? _vazioNulo(String s) => s.isEmpty ? null : s;

  void _trocarOrdem(_Coluna coluna) => setState(() {
        if (_ordem == coluna) {
          _crescente = !_crescente;
        } else {
          _ordem = coluna;
          // Texto começa do A; número/data, do maior.
          _crescente = coluna == _Coluna.cliente || coluna == _Coluna.celular || coluna == _Coluna.bairro;
        }
      });

  void _buscar(String texto) {
    setState(() {});
    context.read<ClientProvider>().pesquisarClientes(texto);
  }

  void _limparBusca() {
    _buscaController.clear();
    _buscar('');
  }

  // ───────────────────────── ações ─────────────────────────

  void _selecionar(Cliente c, List<Cliente> lista) {
    _tabelaFoco.requestFocus();
    setState(() => _selecionadoId = c.idCliente);
    // Altura de linha fixa: dá pra rolar até linha que ainda nem foi desenhada.
    if (!_rolagem.hasClients) return;
    final topo = lista.indexOf(c) * _alturaLinha;
    final posicao = _rolagem.position;
    if (topo < posicao.pixels) {
      _rolagem.jumpTo(topo);
    } else if (topo + _alturaLinha > posicao.pixels + posicao.viewportDimension) {
      _rolagem.jumpTo(topo + _alturaLinha - posicao.viewportDimension);
    }
  }

  /// Duplo clique abre a ficha completa. Contado à mão: o `onDoubleTap` faz o
  /// clique simples esperar 300 ms pra reagir, e aqui o painel abre na hora.
  void _cliqueNaLinha(Cliente c, List<Cliente> lista) {
    final agora = DateTime.now();
    final duplo = _ultimoClique != null &&
        _ultimoCliqueId == c.idCliente &&
        agora.difference(_ultimoClique!) < const Duration(milliseconds: 350);
    _ultimoClique = duplo ? null : agora;
    _ultimoCliqueId = c.idCliente;
    _selecionar(c, lista);
    if (duplo) _abrirCompleta(c);
  }

  Future<void> _abrirCompleta(Cliente c) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ClienteDetalhesScreen(cliente: c)));
    if (mounted) _tabelaFoco.requestFocus();
  }

  Future<void> _novoCliente() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => AdicionarClienteScreen()));
    if (mounted) _tabelaFoco.requestFocus();
  }

  Future<void> _importar() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ImportarClientesScreen()));
    if (mounted) await context.read<ClientProvider>().carregarClientes();
  }

  /// Leva o cliente pro Vender (quem resolve venda em andamento e entrega é o
  /// próprio Vender). Histórico Kyte não entra: precisa antes de "Usar este
  /// cadastro", igual no resto do app.
  void _novaVenda(Cliente c) {
    if (c.canalOrigem == 'kyte_historico') return;
    // Aberta por cima (vindo de um aviso): o menu fica por baixo, sai dela antes.
    final rota = ModalRoute.of(context);
    if (rota != null && !rota.isFirst) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
    final foi = irParaSecaoDoMenu?.call('Vender') == true;
    vendaParaCliente.value = c;
    if (!foi && mounted) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const VendasScreen()));
    }
  }

  /// F2 com um cliente aberto: "Nova venda" (ouvinte global porque o menu
  /// lateral também escuta o F2 — ele troca a seção, aqui só se diz pra quem).
  bool _teclaGlobal(KeyEvent evento) {
    if (evento is! KeyDownEvent || evento.logicalKey != LogicalKeyboardKey.f2) return false;
    if (!mounted || !TickerMode.valuesOf(context).enabled) return false;
    if (ModalRoute.of(context)?.isCurrent == false) return false;
    final sel = _selecionado(_ordenar(_base(context.read<ClientProvider>()).where(_passaFiltro).toList()));
    if (sel == null || sel.canalOrigem == 'kyte_historico') return false;
    _novaVenda(sel);
    return true;
  }

  Cliente? _selecionado(List<Cliente> lista) =>
      _selecionadoId == null ? null : lista.where((c) => c.idCliente == _selecionadoId).firstOrNull;

  KeyEventResult _tecla(KeyEvent evento, List<Cliente> lista) {
    if (evento is! KeyDownEvent && evento is! KeyRepeatEvent) return KeyEventResult.ignored;
    final tecla = evento.logicalKey;
    final sel = _selecionado(lista);
    if (tecla == LogicalKeyboardKey.escape && sel != null) {
      setState(() => _selecionadoId = null);
      return KeyEventResult.handled;
    }
    if (evento is KeyDownEvent && sel != null) {
      if (tecla == LogicalKeyboardKey.enter || tecla == LogicalKeyboardKey.numpadEnter) {
        _abrirCompleta(sel);
        return KeyEventResult.handled;
      }
      if (tecla == LogicalKeyboardKey.keyW) {
        abrirWhatsAppDoCliente(sel);
        return KeyEventResult.handled;
      }
    }
    final passo = tecla == LogicalKeyboardKey.arrowDown
        ? 1
        : tecla == LogicalKeyboardKey.arrowUp
            ? -1
            : 0;
    if (passo == 0 || lista.isEmpty) return KeyEventResult.ignored;
    final atual = sel == null ? -1 : lista.indexOf(sel);
    _selecionar(lista[atual < 0 ? 0 : (atual + passo).clamp(0, lista.length - 1)], lista);
    return KeyEventResult.handled;
  }

  // ───────────────────────── visual ─────────────────────────

  Color _tom(MaterialColor cor) => AppTheme.tomAdaptavel(cor, Theme.of(context).brightness);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ClientProvider>();
    final cores = Theme.of(context).colorScheme;
    final base = _base(provider);
    final lista = _ordenar(base.where(_passaFiltro).toList());
    final selecionado = _selecionado(lista);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => _buscaFoco.requestFocus(),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): _novoCliente,
      },
      child: Focus(
        child: Scaffold(
          appBar: _barraTopo(cores),
          body: Column(
            children: [
              _barraFiltros(cores, lista),
              if (provider.carregando) const LinearProgressIndicator(minHeight: 2),
              const Divider(height: 1),
              Expanded(
                child: LayoutBuilder(builder: (context, limites) {
                  final larguraPainel = (limites.maxWidth * 0.36).clamp(360.0, 460.0).toDouble();
                  final larguraTabela = limites.maxWidth - larguraPainel;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _tabela(cores, provider, lista, larguraTabela)),
                      const VerticalDivider(width: 1),
                      SizedBox(
                        width: larguraPainel,
                        child: selecionado == null
                            ? _painelVazio(cores)
                            : ClienteDetalhesScreen(
                                // Uma ficha por cliente: as abas carregam ao abrir.
                                key: ValueKey(selecionado.idCliente),
                                cliente: selecionado,
                                embutida: true,
                                onNovaVenda: selecionado.canalOrigem == 'kyte_historico'
                                    ? null
                                    : () => _novaVenda(selecionado),
                                onAlterado: () {
                                  if (mounted && _kyte != null) _carregarKyte();
                                },
                              ),
                      ),
                    ],
                  );
                }),
              ),
              const Divider(height: 1),
              Container(
                constraints: const BoxConstraints(minHeight: 32),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                alignment: Alignment.centerLeft,
                child: Text(
                  [
                    '↑ ↓ trocar de cliente',
                    'Enter abrir ficha completa',
                    'W WhatsApp',
                    'F2 nova venda',
                    'Ctrl F buscar',
                    'Ctrl N novo cliente',
                    'Esc fechar',
                    'Clique no título da coluna pra ordenar',
                  ].join('     ·     '),
                  style: TextStyle(fontSize: 12, color: cores.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _barraTopo(ColorScheme cores) {
    final auth = context.watch<AuthProvider>();
    final modulos = context.watch<ModuloProvider>();
    final relacionamento = itensRelacionamento(auth.podeVerFinancas)
        .where((i) => i.modulos == null || modulos.algumAtivo(i.modulos!))
        .toList();
    final corTopo = AppBarTheme.of(context).foregroundColor ?? cores.onPrimary;
    final contorno = OutlinedButton.styleFrom(
      foregroundColor: corTopo,
      side: BorderSide(color: corTopo.withValues(alpha: 0.7)),
      minimumSize: const Size(0, 34),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      textStyle: const TextStyle(fontSize: 13),
      visualDensity: VisualDensity.compact,
    );

    return AppBar(
      title: const Text('Clientes'),
      actions: [
        IconButton(tooltip: 'Atualizar', icon: const Icon(Icons.refresh), onPressed: _recarregar),
        if (relacionamento.isNotEmpty) ...[
          _menuRelacionamento(relacionamento, corTopo),
          const SizedBox(width: 8),
        ],
        // Importar/exportar mexe na base inteira (telefone, endereço, CPF,
        // saldo): vendedor não deveria conseguir baixar isso.
        if (!auth.isVendedor) ...[
          OutlinedButton(style: contorno, onPressed: _importar, child: const Text('Importar / exportar')),
          const SizedBox(width: 8),
        ],
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: corTopo,
            foregroundColor: cores.primary,
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            visualDensity: VisualDensity.compact,
          ),
          onPressed: _novoCliente,
          child: const Text('+ Novo cliente · Ctrl N'),
        ),
        const SizedBox(width: 16),
      ],
      bottom: TabBar(
        controller: _abas,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: const [Tab(text: 'Clientes', height: 38), Tab(text: 'Histórico Kyte', height: 38)],
      ),
    );
  }

  Widget _menuRelacionamento(List<MenuItem> itens, Color corTopo) {
    return PopupMenuButton<MenuItem>(
      tooltip: 'Campanhas, vínculos e sugestões',
      onSelected: (item) async {
        await Navigator.push(context, MaterialPageRoute(builder: (_) => item.tela));
        if (mounted) _tabelaFoco.requestFocus();
      },
      itemBuilder: (_) => [
        for (final item in itens)
          PopupMenuItem(
            value: item,
            child: Row(
              children: [
                Icon(item.icone, size: 18),
                const SizedBox(width: 10),
                Text(item.titulo),
              ],
            ),
          ),
      ],
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: corTopo.withValues(alpha: 0.7)),
          borderRadius: BorderRadius.circular(17),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Relacionamento', style: TextStyle(fontSize: 13, color: corTopo)),
            Icon(Icons.arrow_drop_down, size: 18, color: corTopo),
          ],
        ),
      ),
    );
  }

  Widget _barraFiltros(ColorScheme cores, List<Cliente> lista) {
    const filtros = [
      (_Filtro.todos, 'Todos'),
      (_Filtro.vip, 'VIP'),
      (_Filtro.regular, 'Regular'),
      (_Filtro.novo, 'Novo'),
      (_Filtro.inativo, 'Inativo'),
      (_Filtro.comSaldo, 'Com saldo'),
      (_Filtro.semComprar, 'Sem comprar há $_diasSemComprar+ dias'),
    ];
    final compraram = lista.where((c) => (c.quantidadeCompras ?? 0) > 0).length;
    final rotulo = _naAbaKyte ? 'cadastro' : 'cliente';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          SizedBox(
            width: 300,
            child: Focus(
              // ↓ na busca desce pra tabela, sem precisar do mouse.
              onKeyEvent: (_, e) {
                if (e is! KeyDownEvent) return KeyEventResult.ignored;
                if (e.logicalKey == LogicalKeyboardKey.arrowDown && lista.isNotEmpty) {
                  _selecionar(lista.first, lista);
                  return KeyEventResult.handled;
                }
                if (e.logicalKey == LogicalKeyboardKey.escape && _buscaController.text.isNotEmpty) {
                  _limparBusca();
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(
                controller: _buscaController,
                focusNode: _buscaFoco,
                decoration: InputDecoration(
                  hintText: _naAbaKyte ? 'Nome ou telefone' : 'Nome, celular ou endereço',
                  hintStyle: const TextStyle(fontSize: 13),
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  suffixIcon: _buscaController.text.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Center(
                            widthFactor: 1,
                            child: Text('Ctrl F', style: TextStyle(fontSize: 11, color: cores.onSurfaceVariant)),
                          ),
                        )
                      : IconButton(
                          tooltip: 'Limpar busca',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: _limparBusca,
                        ),
                ),
                onChanged: _buscar,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FaixaRolavel(
              espacoBarra: 6,
              child: Row(
                children: [
                  for (final (f, nome) in filtros) ...[
                    ChoiceChip(
                      label: Text(nome),
                      selected: _filtro == f,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _filtro = f),
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '${lista.length} $rotulo${lista.length == 1 ? '' : 's'} · $compraram já compr${compraram == 1 ? 'ou' : 'aram'}',
            style: TextStyle(fontSize: 12, color: cores.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  // ───── tabela ─────

  Widget _celulas({
    required double largura,
    required Widget cliente,
    required Widget celular,
    required Widget bairro,
    required Widget compras,
    required Widget total,
    required Widget ultima,
    required Widget saldo,
    required Widget petcash,
  }) {
    // O que não couber continua à vista no painel do cliente. Janela de ~1200
    // px: nome, total, última compra e saldo; depois vêm celular e compras;
    // bairro e PetCash só com bastante espaço.
    final media = largura >= 700;
    final larga = largura >= 1000;
    Widget coluna(double w, Widget filho) => Padding(
          padding: const EdgeInsets.only(left: 10),
          child: SizedBox(width: w, child: filho),
        );
    return Row(
      children: [
        Expanded(child: cliente),
        if (media) coluna(118, celular),
        if (larga) coluna(120, bairro),
        if (media) coluna(64, compras),
        coluna(100, total),
        coluna(92, ultima),
        coluna(84, saldo),
        if (larga) coluna(84, petcash),
      ],
    );
  }

  Widget _titulo(ColorScheme cores, String texto, _Coluna coluna, {bool direita = false}) {
    final ativa = _ordem == coluna;
    final cor = ativa ? cores.primary : cores.onSurfaceVariant;
    return InkWell(
      onTap: () => _trocarOrdem(coluna),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          mainAxisAlignment: direita ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            Flexible(
              child: Text(texto.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, letterSpacing: 0.5, fontWeight: FontWeight.w700, color: cor)),
            ),
            if (ativa) Icon(_crescente ? Icons.arrow_upward : Icons.arrow_downward, size: 13, color: cor),
          ],
        ),
      ),
    );
  }

  Widget _tabela(ColorScheme cores, ClientProvider provider, List<Cliente> lista, double largura) {
    final kyte = _naAbaKyte;
    final erro = kyte ? _erroKyte : provider.erro;
    final semDados = kyte ? (_kyte ?? const []).isEmpty : provider.clientes.isEmpty;
    if (erro != null && semDados) {
      return EstadoErroLista(mensagem: erro, onTentarNovamente: _recarregar);
    }
    if (lista.isEmpty) {
      final carregando = kyte ? _kyte == null : provider.carregando;
      if (carregando) return const Center(child: CircularProgressIndicator());
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.people_outline, size: 48, color: cores.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              semDados
                  ? (kyte ? 'Nenhum cadastro de histórico do Kyte' : 'Nenhum cliente cadastrado ainda')
                  : 'Nenhum cliente nessa busca e filtro',
              style: TextStyle(fontSize: 16, color: cores.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return Focus(
      focusNode: _tabelaFoco,
      onKeyEvent: (_, e) => _tecla(e, lista),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _celulas(
              largura: largura,
              cliente: _titulo(cores, 'Cliente', _Coluna.cliente),
              celular: _titulo(cores, 'Celular', _Coluna.celular),
              bairro: _titulo(cores, 'Bairro', _Coluna.bairro),
              compras: _titulo(cores, 'Compras', _Coluna.compras, direita: true),
              total: _titulo(cores, 'Total gasto', _Coluna.total, direita: true),
              ultima: _titulo(cores, 'Última', _Coluna.ultima),
              saldo: _titulo(cores, 'Saldo', _Coluna.saldo, direita: true),
              petcash: _titulo(cores, 'PetCash', _Coluna.petcash, direita: true),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              controller: _rolagem,
              itemExtent: _alturaLinha,
              itemCount: lista.length,
              itemBuilder: (_, i) => _linha(cores, lista[i], lista, largura),
            ),
          ),
        ],
      ),
    );
  }

  String _textoUltima(Cliente c) {
    final dias = _diasDesde(c);
    if (dias == null) return '—';
    if (dias <= 0) return 'hoje';
    if (dias == 1) return 'ontem';
    return 'há $dias dias';
  }

  Widget _linha(ColorScheme cores, Cliente c, List<Cliente> lista, double largura) {
    final selecionada = c.idCliente == _selecionadoId;
    final apagado = cores.onSurfaceVariant;
    final telefone = c.telefoneContato;
    final dias = _diasDesde(c);
    final sumiu = dias != null && dias >= _diasSemComprar;
    final pets = c.pets.length;
    final corSaldo = c.saldo > 0
        ? _tom(Colors.green)
        : c.saldo < 0
            ? cores.error
            : apagado;

    return Material(
      color: selecionada ? cores.primary.withValues(alpha: 0.12) : Colors.transparent,
      child: InkWell(
        onTap: () => _cliqueNaLinha(c, lista),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: selecionada ? cores.primary : Colors.transparent, width: 3),
              bottom: BorderSide(color: cores.outlineVariant.withValues(alpha: 0.35)),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(13, 0, 16, 0),
          child: _celulas(
            largura: largura,
            cliente: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: cores.primaryContainer,
                  child: Text(
                    c.nome.isNotEmpty ? c.nome[0].toUpperCase() : '?',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cores.onPrimaryContainer),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(c.nome,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 6),
                CategoriaClienteBadge(categoria: c.categoriaCliente),
                // Sem sobra de espaço, o nome vem primeiro: os pets estão no painel.
                if (pets > 0 && largura >= 1000) ...[
                  const SizedBox(width: 6),
                  Text('$pets pet${pets == 1 ? '' : 's'}', style: TextStyle(fontSize: 11, color: apagado)),
                ],
              ],
            ),
            celular: Text(telefone.isEmpty ? '—' : ClienteValidators.celularParaEdicao(telefone),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: apagado)),
            bairro: Text(c.bairro.isEmpty ? '—' : c.bairro,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: apagado)),
            compras: Text('${c.quantidadeCompras ?? 0}', textAlign: TextAlign.right, style: const TextStyle(fontSize: 12.5)),
            total: Text(_moeda.format(c.totalGasto ?? 0),
                maxLines: 1,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ultima: Text(_textoUltima(c),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5,
                    color: sumiu ? cores.error : apagado,
                    fontWeight: sumiu ? FontWeight.w600 : FontWeight.normal)),
            saldo: Text(_moeda.format(c.saldo),
                maxLines: 1,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12.5, color: corSaldo, fontWeight: c.saldo != 0 ? FontWeight.w700 : FontWeight.normal)),
            petcash: Text(c.saldoPetCash > 0 ? _moeda.format(c.saldoPetCash) : '—',
                maxLines: 1, textAlign: TextAlign.right, style: TextStyle(fontSize: 12.5, color: apagado)),
          ),
        ),
      ),
    );
  }

  Widget _painelVazio(ColorScheme cores) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app_outlined, size: 40, color: cores.onSurfaceVariant),
              const SizedBox(height: 12),
              const Text('Clique num cliente pra abrir aqui', textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text('↑ ↓ passam pro próximo · Enter abre a ficha completa',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cores.onSurfaceVariant)),
            ],
          ),
        ),
      );
}
