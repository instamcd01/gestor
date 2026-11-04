import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/venda.dart';
import '../providers/branding_provider.dart';
import '../providers/historico_vendas_provider.dart';
import '../theme/app_theme.dart';
import '../utils/busca_utils.dart';
import '../utils/canal_venda_utils.dart';
import '../utils/mensagem_status_dialog.dart';
import '../utils/mensagens_status_pedido.dart';
import '../widgets/categoria_cliente_badge.dart';
import '../widgets/estado_erro_lista.dart';
import '../widgets/faixa_rolavel.dart';
import 'recibo_screen.dart';
import 'venda_detalhes_screen.dart';

// Dia da semana escrito à mão, como no resto do app (o app não chama
// initializeDateFormatting('pt_BR'); sem isso o DateFormat sai em inglês).
const _diasDaSemana = ['segunda-feira', 'terça-feira', 'quarta-feira', 'quinta-feira', 'sexta-feira', 'sábado', 'domingo'];

enum _Periodo { hoje, semana, mes, mesPassado, tudo, escolhido }

enum _Coluna { data, numero, cliente, canal, pagamento, itens, status, total }

/// Histórico de Vendas no PC (janela ≥ 1200 px): filtros numa linha, tabela
/// ordenável com faixas por dia, resumo do período no rodapé e a venda
/// aberta ao lado. Cancelar, estornar, editar itens e corrigir pagamento
/// continuam na tela completa de sempre (`VendaDetalhesScreen`) — nada de
/// regra duplicada. No celular segue a `HistoricoVendasScreen` de sempre.
class HistoricoVendasPc extends StatefulWidget {
  /// Vendas que essa pessoa pode ver (vendedor: só as dele) — a tela de
  /// sempre já faz esse corte.
  final List<Venda> vendas;
  final Future<void> Function() recarregar;

  const HistoricoVendasPc({super.key, required this.vendas, required this.recarregar});

  @override
  State<HistoricoVendasPc> createState() => _HistoricoVendasPcState();
}

class _HistoricoVendasPcState extends State<HistoricoVendasPc> {
  final _buscaController = TextEditingController();
  final _buscaFoco = FocusNode(debugLabel: 'busca-historico');
  final _tabelaFoco = FocusNode(debugLabel: 'tabela-historico');
  final _chaveSelecionada = GlobalKey();

  _Periodo _periodo = _Periodo.mes;
  DateTimeRange? _escolhido;
  String? _pagamento;
  String? _canal;
  _Coluna _ordem = _Coluna.data;
  bool _crescente = false;
  String? _selecionadoId;

  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

  @override
  void dispose() {
    _buscaController.dispose();
    _buscaFoco.dispose();
    _tabelaFoco.dispose();
    super.dispose();
  }

  // ───────────────────────── filtros ─────────────────────────

  DateTimeRange? get _intervalo {
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    return switch (_periodo) {
      _Periodo.hoje => DateTimeRange(start: hoje, end: hoje),
      _Periodo.semana => DateTimeRange(start: hoje.subtract(const Duration(days: 6)), end: hoje),
      _Periodo.mes => DateTimeRange(start: DateTime(hoje.year, hoje.month, 1), end: hoje),
      _Periodo.mesPassado => DateTimeRange(
          start: DateTime(hoje.year, hoje.month - 1, 1), end: DateTime(hoje.year, hoje.month, 0)),
      _Periodo.tudo => null,
      _Periodo.escolhido => _escolhido,
    };
  }

  String get _rotuloPeriodo {
    final i = _intervalo;
    final f = DateFormat('dd/MM');
    return switch (_periodo) {
      _Periodo.hoje => 'Hoje',
      _Periodo.semana => 'Últimos 7 dias',
      _Periodo.mes => 'Este mês',
      _Periodo.mesPassado => 'Mês passado',
      _Periodo.tudo => 'Tudo que está carregado',
      _Periodo.escolhido => i == null ? 'Período' : '${f.format(i.start)} a ${f.format(i.end)}',
    };
  }

  Future<void> _escolherPeriodo(_Periodo p) async {
    if (p == _Periodo.escolhido) {
      final escolhido = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2020),
        lastDate: DateTime.now(),
        initialDateRange: _escolhido ?? _intervalo,
      );
      if (escolhido == null || !mounted) return;
      _escolhido = escolhido;
    }
    setState(() => _periodo = p);
    // Período antes da janela carregada busca o que falta (igual o celular).
    final inicio = _intervalo?.start;
    if (inicio != null) {
      context.read<HistoricoVendasProvider>().garantirPeriodo(inicio);
    }
  }

  bool _passa(Venda v) {
    final i = _intervalo;
    if (i != null) {
      final dia = DateTime(v.dataVenda.year, v.dataVenda.month, v.dataVenda.day);
      if (dia.isBefore(i.start) || dia.isAfter(i.end)) return false;
    }
    if (_pagamento != null && v.metodoPagamento != _pagamento) return false;
    if (_canal != null && rotuloCanalVenda(v.canalVenda) != _canal) return false;
    final termo = _buscaController.text.trim();
    if (termo.isNotEmpty) {
      final semCerquilha = termo.replaceAll('#', '');
      final porNumero = '${v.numeroSequencial ?? ''}' == semCerquilha ||
          (v.numeroExibicaoMarketplace ?? '').toLowerCase() == semCerquilha.toLowerCase();
      final porId = (v.idVenda ?? '').toLowerCase().contains(termo.toLowerCase());
      if (!porNumero && !porId && !contemTodasPalavras(v.cliente.nome, termo)) return false;
    }
    return true;
  }

  List<Venda> _ordenar(List<Venda> lista) {
    int c(Venda a, Venda b) => switch (_ordem) {
          _Coluna.data => a.dataVenda.compareTo(b.dataVenda),
          _Coluna.numero => (a.numeroSequencial ?? 0).compareTo(b.numeroSequencial ?? 0),
          _Coluna.cliente => a.cliente.nome.toLowerCase().compareTo(b.cliente.nome.toLowerCase()),
          _Coluna.canal => rotuloCanalVenda(a.canalVenda).compareTo(rotuloCanalVenda(b.canalVenda)),
          _Coluna.pagamento => a.metodoPagamento.compareTo(b.metodoPagamento),
          _Coluna.itens => a.itens.length.compareTo(b.itens.length),
          _Coluna.status => StatusPedido.rotulo(a.status).compareTo(StatusPedido.rotulo(b.status)),
          _Coluna.total => a.valorTotal.compareTo(b.valorTotal),
        };
    final r = [...lista]..sort((a, b) {
        final x = c(a, b);
        // Empate: mais recente primeiro.
        return x != 0 ? (_crescente ? x : -x) : b.dataVenda.compareTo(a.dataVenda);
      });
    return r;
  }

  void _trocarOrdem(_Coluna coluna) => setState(() {
        if (_ordem == coluna) {
          _crescente = !_crescente;
        } else {
          _ordem = coluna;
          // Texto começa do A; número/data/valor, do maior.
          _crescente = coluna == _Coluna.cliente || coluna == _Coluna.canal || coluna == _Coluna.pagamento;
        }
      });

  // ───────────────────────── ações ─────────────────────────

  void _selecionar(Venda v) {
    _tabelaFoco.requestFocus();
    setState(() => _selecionadoId = v.idVenda);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _chaveSelecionada.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
        final ctx2 = _chaveSelecionada.currentContext;
        if (ctx2 != null) {
          Scrollable.ensureVisible(ctx2, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart);
        }
      }
    });
  }

  Future<void> _abrirCompleta(Venda v) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => VendaDetalhesScreen(venda: v)));
    if (mounted) _tabelaFoco.requestFocus();
  }

  void _abrirRecibo(Venda v) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => ReciboScreen(venda: v)));

  String? _mensagemWhatsapp(Venda v) => v.ehMarketplace
      ? null
      : mensagemPadraoStatus(v, v.status, nomeLoja: context.read<BrandingProvider>().nomeEmpresa);

  KeyEventResult _tecla(KeyEvent evento, List<Venda> lista) {
    if (evento is! KeyDownEvent && evento is! KeyRepeatEvent) return KeyEventResult.ignored;
    final tecla = evento.logicalKey;
    final atual = lista.indexWhere((v) => v.idVenda == _selecionadoId);
    final sel = atual < 0 ? null : lista[atual];
    if (tecla == LogicalKeyboardKey.escape && sel != null) {
      setState(() => _selecionadoId = null);
      return KeyEventResult.handled;
    }
    if (evento is KeyDownEvent && sel != null) {
      if (tecla == LogicalKeyboardKey.enter || tecla == LogicalKeyboardKey.numpadEnter) {
        _abrirCompleta(sel);
        return KeyEventResult.handled;
      }
      if (tecla == LogicalKeyboardKey.keyR) {
        _abrirRecibo(sel);
        return KeyEventResult.handled;
      }
      if (tecla == LogicalKeyboardKey.keyW) {
        final m = _mensagemWhatsapp(sel);
        if (m != null) enviarMensagemStatusWhatsApp(context, sel, m);
        return KeyEventResult.handled;
      }
    }
    final passo = tecla == LogicalKeyboardKey.arrowDown
        ? 1
        : tecla == LogicalKeyboardKey.arrowUp
            ? -1
            : 0;
    if (passo == 0 || lista.isEmpty) return KeyEventResult.ignored;
    _selecionar(lista[atual < 0 ? 0 : (atual + passo).clamp(0, lista.length - 1)]);
    return KeyEventResult.handled;
  }

  // ───────────────────────── visual ─────────────────────────

  Color _tom(MaterialColor cor) => AppTheme.tomAdaptavel(cor, Theme.of(context).brightness);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HistoricoVendasProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final filtradas = widget.vendas.where(_passa).toList();
    final lista = _ordenar(filtradas);
    final selecionada = lista.where((v) => v.idVenda == _selecionadoId).firstOrNull;
    final pagamentos = {for (final v in widget.vendas) v.metodoPagamento}.where((m) => m.isNotEmpty).toList()..sort();
    final canais = {for (final v in widget.vendas) rotuloCanalVenda(v.canalVenda)}.toList()..sort();

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () => _buscaFoco.requestFocus(),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Histórico de Vendas'),
            actions: [
              IconButton(tooltip: 'Atualizar', icon: const Icon(Icons.refresh), onPressed: widget.recarregar),
            ],
          ),
          body: Column(
            children: [
              _barraFiltros(colorScheme, pagamentos, canais, filtradas.length),
              if (provider.carregando) const LinearProgressIndicator(),
              const Divider(height: 1),
              Expanded(
                child: LayoutBuilder(builder: (context, limites) {
                  final larguraPainel = (limites.maxWidth * 0.36).clamp(360.0, 460.0).toDouble();
                  final compacto = limites.maxWidth - larguraPainel < 800;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            Expanded(child: _tabela(colorScheme, provider, lista, compacto)),
                            _resumo(colorScheme, provider, filtradas),
                          ],
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      SizedBox(
                        width: larguraPainel,
                        child: selecionada == null ? _painelVazio(colorScheme) : _painel(colorScheme, selecionada),
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
                    '↑ ↓ trocar de venda',
                    'Enter abrir completa (cancelar, estornar, editar)',
                    'R recibo',
                    'W WhatsApp',
                    'Ctrl F buscar',
                    'Esc fechar',
                    'Clique no título da coluna pra ordenar',
                  ].join('     ·     '),
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _barraFiltros(ColorScheme cores, List<String> pagamentos, List<String> canais, int quantidade) {
    const periodos = [
      (_Periodo.hoje, 'Hoje'),
      (_Periodo.semana, '7 dias'),
      (_Periodo.mes, 'Este mês'),
      (_Periodo.mesPassado, 'Mês passado'),
      (_Periodo.tudo, 'Tudo'),
      (_Periodo.escolhido, 'Escolher…'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          SizedBox(
            width: 280,
            child: TextField(
              controller: _buscaController,
              focusNode: _buscaFoco,
              decoration: InputDecoration(
                hintText: 'Cliente, nº do pedido ou ID',
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
                        onPressed: () => setState(_buscaController.clear),
                      ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FaixaRolavel(
              espacoBarra: 6,
              child: Row(
                children: [
                  for (final (p, rotulo) in periodos) ...[
                    ChoiceChip(
                      label: Text(p == _Periodo.escolhido && _periodo == p ? _rotuloPeriodo : rotulo),
                      selected: _periodo == p,
                      showCheckmark: false,
                      onSelected: (_) => _escolherPeriodo(p),
                    ),
                    const SizedBox(width: 6),
                  ],
                  const SizedBox(width: 6),
                  _menuFiltro(
                    cores,
                    rotulo: 'Pagamento',
                    valor: _pagamento,
                    opcoes: pagamentos,
                    todas: 'Todas',
                    onEscolher: (v) => setState(() => _pagamento = v),
                  ),
                  const SizedBox(width: 6),
                  _menuFiltro(
                    cores,
                    rotulo: 'Canal',
                    valor: _canal,
                    opcoes: canais,
                    todas: 'Todos',
                    onEscolher: (v) => setState(() => _canal = v),
                  ),
                  if (_pagamento != null || _canal != null || _buscaController.text.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    ActionChip(
                      avatar: const Icon(Icons.close, size: 16),
                      label: const Text('Limpar filtros'),
                      onPressed: () => setState(() {
                        _pagamento = null;
                        _canal = null;
                        _buscaController.clear();
                      }),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text('$quantidade venda${quantidade == 1 ? '' : 's'}',
              style: TextStyle(fontSize: 12, color: cores.onSurfaceVariant)),
        ],
      ),
    );
  }

  Widget _menuFiltro(
    ColorScheme cores, {
    required String rotulo,
    required String? valor,
    required List<String> opcoes,
    required String todas,
    required ValueChanged<String?> onEscolher,
  }) {
    // Menu do Flutter trata null como "cancelou": '' = todas.
    return PopupMenuButton<String>(
      tooltip: 'Filtrar por ${rotulo.toLowerCase()}',
      initialValue: valor ?? '',
      onSelected: (v) => onEscolher(v.isEmpty ? null : v),
      itemBuilder: (_) => [
        PopupMenuItem(value: '', child: Text(todas)),
        for (final o in opcoes) PopupMenuItem(value: o, child: Text(o)),
      ],
      child: Chip(
        label: Text('$rotulo: ${valor ?? todas.toLowerCase()}'),
        avatar: const Icon(Icons.arrow_drop_down, size: 18),
        backgroundColor: valor == null ? null : cores.primaryContainer,
      ),
    );
  }

  // ───── tabela ─────

  static const _wHora = 56.0, _wNum = 70.0, _wCanal = 100.0, _wPag = 140.0, _wItens = 50.0, _wStatus = 118.0, _wTotal = 100.0;

  Widget _celulas({
    required Widget hora,
    required Widget numero,
    required Widget cliente,
    required Widget canal,
    required Widget pagamento,
    required Widget itens,
    required Widget status,
    required Widget total,
    required bool compacto,
  }) {
    // Estreito (janela de ~1200 px): sem Pagamento e Itens (os dois estão
    // no painel da venda, e Pagamento continua no filtro) e colunas mais
    // finas — senão o nome do cliente sumia.
    return Row(
      children: [
        SizedBox(width: compacto ? 48 : _wHora, child: hora),
        SizedBox(width: compacto ? 62 : _wNum, child: numero),
        Expanded(child: cliente),
        const SizedBox(width: 10),
        SizedBox(width: compacto ? 84 : _wCanal, child: canal),
        if (!compacto) SizedBox(width: _wPag, child: pagamento),
        if (!compacto) SizedBox(width: _wItens, child: itens),
        const SizedBox(width: 14),
        SizedBox(width: compacto ? 104 : _wStatus, child: status),
        SizedBox(width: compacto ? 92 : _wTotal, child: total),
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

  Widget _tabela(ColorScheme cores, HistoricoVendasProvider provider, List<Venda> lista, bool compacto) {
    if (provider.erro != null && widget.vendas.isEmpty) {
      return EstadoErroLista(mensagem: provider.erro!, onTentarNovamente: widget.recarregar);
    }
    if (lista.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long, size: 48, color: cores.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              widget.vendas.isEmpty ? 'Nenhuma venda registrada' : 'Nenhuma venda nesse período e filtros',
              style: TextStyle(fontSize: 16, color: cores.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    // Por data: faixas por dia (com quantidade e total do dia, como no
    // celular). Ordenado por outra coluna, a lista fica corrida.
    final porDia = _ordem == _Coluna.data;
    final linhas = <Object>[];
    if (porDia) {
      DateTime? diaAtual;
      for (final v in lista) {
        final dia = DateTime(v.dataVenda.year, v.dataVenda.month, v.dataVenda.day);
        if (dia != diaAtual) {
          diaAtual = dia;
          linhas.add(dia);
        }
        linhas.add(v);
      }
    } else {
      linhas.addAll(lista);
    }
    final resumoDia = <DateTime, (int, double)>{};
    if (porDia) {
      for (final v in lista) {
        final dia = DateTime(v.dataVenda.year, v.dataVenda.month, v.dataVenda.day);
        final (n, t) = resumoDia[dia] ?? (0, 0.0);
        // Igual ao celular: conta todas do dia, soma só as concluídas.
        resumoDia[dia] = (n + 1, v.finalizada ? t + v.valorTotal : t);
      }
    }

    return Focus(
      focusNode: _tabelaFoco,
      onKeyEvent: (_, e) => _tecla(e, lista),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _celulas(
              compacto: compacto,
              hora: _titulo(cores, porDia ? 'Hora' : 'Data', _Coluna.data),
              numero: _titulo(cores, 'Nº', _Coluna.numero),
              cliente: _titulo(cores, 'Cliente', _Coluna.cliente),
              canal: _titulo(cores, 'Canal', _Coluna.canal),
              pagamento: _titulo(cores, 'Pagamento', _Coluna.pagamento),
              itens: _titulo(cores, 'Itens', _Coluna.itens, direita: true),
              status: _titulo(cores, 'Status', _Coluna.status),
              total: _titulo(cores, 'Total', _Coluna.total, direita: true),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: linhas.length,
              itemBuilder: (_, i) {
                final l = linhas[i];
                if (l is DateTime) {
                  final (n, t) = resumoDia[l] ?? (0, 0.0);
                  return Container(
                    color: cores.surfaceContainer,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text('${_diasDaSemana[l.weekday - 1]}, ${DateFormat('dd/MM').format(l)}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                        Text('$n venda${n == 1 ? '' : 's'} · ${_moeda.format(t)}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  );
                }
                final v = l as Venda;
                return _linha(cores, v, porDia, compacto);
              },
            ),
          ),
        ],
      ),
    );
  }

  ({String texto, Color cor})? _selo(Venda v) {
    if (v.cancelada) return (texto: 'Cancelada', cor: _tom(Colors.red));
    if (v.aguardandoPagamento) return (texto: StatusPedido.rotulo(v.status), cor: _tom(Colors.amber));
    if (v.emAndamento) return (texto: StatusPedido.rotulo(v.status), cor: _tom(Colors.orange));
    if (v.finalizada) return (texto: StatusPedido.rotulo(v.status), cor: _tom(Colors.green));
    return (texto: StatusPedido.rotulo(v.status), cor: Theme.of(context).colorScheme.onSurfaceVariant);
  }

  Widget _linha(ColorScheme cores, Venda v, bool porDia, bool compacto) {
    final selecionada = v.idVenda == _selecionadoId;
    final riscada = v.cancelada ? TextDecoration.lineThrough : null;
    final apagado = cores.onSurfaceVariant;
    final selo = _selo(v);
    return Material(
      key: selecionada ? _chaveSelecionada : null,
      color: selecionada ? cores.primary.withValues(alpha: 0.12) : Colors.transparent,
      child: InkWell(
        onTap: () => _selecionar(v),
        onDoubleTap: () => _abrirCompleta(v),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: selecionada ? cores.primary : Colors.transparent, width: 3),
              bottom: BorderSide(color: cores.outlineVariant.withValues(alpha: 0.35)),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(13, 9, 16, 9),
          child: _celulas(
            compacto: compacto,
            hora: Text(DateFormat(porDia ? 'HH:mm' : 'dd/MM').format(v.dataVenda),
                style: TextStyle(fontSize: 13, color: apagado)),
            numero: Text('#${v.numeroSequencial ?? '-'}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: apagado)),
            cliente: Text(v.cliente.nome,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    decoration: riscada,
                    color: v.cancelada ? apagado : null)),
            canal: Text(rotuloCanalVenda(v.canalVenda),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: apagado)),
            pagamento: Text(v.metodoPagamento,
                maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
            itens: Text('${v.itens.length}',
                textAlign: TextAlign.right, style: TextStyle(fontSize: 13, color: apagado)),
            status: Align(
              alignment: Alignment.centerLeft,
              child: selo == null
                  ? const SizedBox()
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: selo.cor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(selo.texto,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: selo.cor)),
                    ),
            ),
            total: Text(_moeda.format(v.valorTotal),
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    decoration: riscada,
                    color: v.cancelada ? apagado : null)),
          ),
        ),
      ),
    );
  }

  // ───── resumo do período (rodapé) ─────

  Widget _resumo(ColorScheme cores, HistoricoVendasProvider provider, List<Venda> filtradas) {
    // Mesma regra do resumo do celular: conta só venda concluída (entregue).
    final concluidas = filtradas.where((v) => v.finalizada).toList();
    final total = concluidas.fold<double>(0, (s, v) => s + v.valorTotal);
    final andamento = filtradas.where((v) => v.emAndamento || v.aguardandoPagamento).toList();
    final canceladas = filtradas.where((v) => v.cancelada).toList();
    final ticket = concluidas.isEmpty ? 0.0 : total / concluidas.length;
    final desde = provider.carregadoDesde;
    final i = _intervalo;
    final f = DateFormat('dd/MM');

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cores.surface,
        border: Border(top: BorderSide(color: cores.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Wrap(
        spacing: 22,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text.rich(TextSpan(children: [
            TextSpan(text: _rotuloPeriodo, style: const TextStyle(fontWeight: FontWeight.w700)),
            if (i != null && _periodo != _Periodo.escolhido)
              TextSpan(text: '  ${f.format(i.start)} a ${f.format(i.end)}', style: TextStyle(color: cores.onSurfaceVariant)),
          ])),
          Text.rich(TextSpan(children: [
            TextSpan(text: '${concluidas.length}', style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: ' concluída${concluidas.length == 1 ? '' : 's'}'),
          ])),
          Text.rich(TextSpan(children: [
            const TextSpan(text: 'Total '),
            TextSpan(text: _moeda.format(total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          ])),
          Text.rich(TextSpan(children: [
            const TextSpan(text: 'Ticket médio '),
            TextSpan(text: _moeda.format(ticket), style: const TextStyle(fontWeight: FontWeight.w700)),
          ])),
          if (andamento.isNotEmpty)
            Text('${andamento.length} em andamento · ${_moeda.format(andamento.fold<double>(0, (s, v) => s + v.valorTotal))} (fora do total)',
                style: TextStyle(color: _tom(Colors.orange))),
          if (canceladas.isNotEmpty)
            Text('${canceladas.length} cancelada${canceladas.length == 1 ? '' : 's'} · ${_moeda.format(canceladas.fold<double>(0, (s, v) => s + v.valorTotal))} (fora do total)',
                style: TextStyle(color: _tom(Colors.red))),
          if (desde != null)
            Wrap(
              spacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Mostrando desde ${DateFormat('dd/MM/yyyy').format(desde)} ·',
                    style: TextStyle(fontSize: 12, color: cores.onSurfaceVariant)),
                TextButton(
                  onPressed: provider.carregando
                      ? null
                      : () => provider.garantirPeriodo(DateTime(desde.year, desde.month - 3, 1)),
                  child: const Text('Mais 3 meses'),
                ),
                TextButton(
                  onPressed: provider.carregando ? null : () => provider.garantirPeriodo(null),
                  child: const Text('Histórico completo'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ───── venda aberta ─────

  Widget _painelVazio(ColorScheme cores) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.touch_app_outlined, size: 40, color: cores.onSurfaceVariant),
              const SizedBox(height: 12),
              const Text('Clique numa venda pra abrir aqui', textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text('↑ ↓ passam pra próxima · Enter abre a venda completa',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: cores.onSurfaceVariant)),
            ],
          ),
        ),
      );

  Widget _cartao(ColorScheme cores, String titulo, List<Widget> filhos) => Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          border: Border.all(color: cores.outlineVariant.withValues(alpha: 0.7)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(titulo.toUpperCase(),
                style: TextStyle(
                    fontSize: 11, letterSpacing: 0.5, fontWeight: FontWeight.w700, color: cores.onSurfaceVariant)),
            const SizedBox(height: 6),
            ...filhos,
          ],
        ),
      );

  Widget _texto(String t, {bool apagado = false}) => Padding(
        padding: const EdgeInsets.only(bottom: 3),
        child: Text(t,
            style: TextStyle(
                fontSize: 13, height: 1.35, color: apagado ? Theme.of(context).colorScheme.onSurfaceVariant : null)),
      );

  Widget _painel(ColorScheme cores, Venda v) {
    final selo = _selo(v);
    final mensagem = _mensagemWhatsapp(v);

    Widget linhaTotal(String rotulo, String valor, {bool forte = false}) => Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Row(
            children: [
              Expanded(
                child: Text(rotulo,
                    style: TextStyle(
                        fontSize: forte ? 16 : 13,
                        fontWeight: forte ? FontWeight.w700 : FontWeight.w400,
                        color: forte ? null : cores.onSurfaceVariant)),
              ),
              Text(valor,
                  style: TextStyle(
                      fontSize: forte ? 16 : 13,
                      fontWeight: forte ? FontWeight.w700 : FontWeight.w500,
                      color: forte ? null : cores.onSurfaceVariant)),
            ],
          ),
        );

    final pagamento = <Widget>[
      _texto(v.resumoFormaPagamento),
      if (v.valorPago > 0 && v.valorPago != v.valorTotal)
        _texto('Valor pago: ${_moeda.format(v.valorPago)}', apagado: true),
      if (v.troco > 0) _texto('Troco: ${_moeda.format(v.troco)}', apagado: true),
      if (v.valorParcelaCartao != null)
        _texto('${v.parcelasCartao}x de ${_moeda.format(v.valorParcelaCartao!)}', apagado: true),
    ];
    final entrega = <Widget>[
      if (v.retirada) ...[
        _texto('Retirada na loja'),
        if (v.codigoRetiradaExibicao != null) _texto('Código: ${v.codigoRetiradaExibicao}', apagado: true),
      ] else ...[
        _texto([
          switch (v.modalidade) { 'agendada' => 'Agendada', 'economica' => 'Econômica', _ => 'Expressa' },
          if (v.entregaSelecionada.isNotEmpty) 'zona ${v.entregaSelecionada}',
        ].join(' · ')),
        if (v.cliente.enderecoCompleto.isNotEmpty) _texto(v.cliente.enderecoExibicao, apagado: true),
        if (v.freteGratisIfood) _texto('Frete grátis (iFood)', apagado: true),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text('#${v.numeroSequencial ?? '-'} · ${v.cliente.nome}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 8),
                        CategoriaClienteBadge(categoria: v.cliente.categoriaCliente),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        rotuloCanalVenda(v.canalVenda),
                        DateFormat("dd/MM 'às' HH:mm").format(v.dataVenda),
                        if (v.ehMarketplace && v.numeroExibicaoMarketplace != null) 'iFood #${v.numeroExibicaoMarketplace}',
                      ].join(' · '),
                      style: TextStyle(fontSize: 13, color: cores.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<VoidCallback>(
                tooltip: 'Mais ações',
                icon: const Icon(Icons.more_vert),
                onSelected: (acao) => acao(),
                itemBuilder: (_) => [
                  PopupMenuItem<VoidCallback>(
                    value: () => _abrirCompleta(v),
                    child: const ListTile(
                      leading: Icon(Icons.open_in_full),
                      title: Text('Abrir venda completa'),
                      subtitle: Text('Cancelar, estornar, editar itens, corrigir pagamento, cliente'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (selo != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: selo.cor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(selo.texto, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selo.cor)),
                ),
              OutlinedButton(onPressed: () => _abrirRecibo(v), child: const Text('Recibo · R')),
              if (mensagem != null)
                OutlinedButton.icon(
                  onPressed: () => enviarMensagemStatusWhatsApp(context, v, mensagem),
                  icon: Icon(Icons.message, size: 16, color: _tom(Colors.green)),
                  label: const Text('WhatsApp · W'),
                ),
              FilledButton(onPressed: () => _abrirCompleta(v), child: const Text('Abrir completa · Enter')),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: cores.outlineVariant.withValues(alpha: 0.7)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                      child: Text('ITENS (${v.itens.length})',
                          style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 0.5,
                              fontWeight: FontWeight.w700,
                              color: cores.onSurfaceVariant)),
                    ),
                    const Divider(height: 1),
                    for (final item in v.itens)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                width: 36,
                                height: 36,
                                color: cores.surfaceContainerHighest,
                                child: item.produto.imagemUrl.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: item.produto.imagemUrlExibicao,
                                        fit: BoxFit.cover,
                                        memCacheWidth: 96,
                                        errorWidget: (_, __, ___) =>
                                            Icon(Icons.inventory_2_outlined, size: 16, color: cores.onSurfaceVariant),
                                      )
                                    : Icon(Icons.inventory_2_outlined, size: 16, color: cores.onSurfaceVariant),
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 30,
                              child: Text('${item.quantidade}×',
                                  style: TextStyle(fontWeight: FontWeight.w800, color: cores.primary)),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.produto.nome, style: const TextStyle(fontSize: 13, height: 1.3)),
                                  if (item.quantidade > 1)
                                    Text('${_moeda.format(item.precoUnitario)} cada',
                                        style: TextStyle(fontSize: 12, color: cores.onSurfaceVariant)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(_moeda.format(item.precoTotal),
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
                      child: Column(
                        children: [
                          linhaTotal('Subtotal', _moeda.format(v.subtotal)),
                          if (v.desconto > 0)
                            linhaTotal(v.cupomCodigo != null ? 'Cupom ${v.cupomCodigo}' : 'Desconto',
                                '− ${_moeda.format(v.desconto)}'),
                          if (v.saldoUsado > 0) linhaTotal('Saldo usado', '− ${_moeda.format(v.saldoUsado)}'),
                          if (v.petcashUsado > 0) linhaTotal('PetCash usado', '− ${_moeda.format(v.petcashUsado)}'),
                          if (v.temEntrega && !v.retirada)
                            linhaTotal('Entrega', v.freteGratisIfood ? 'Grátis' : _moeda.format(v.valorEntrega)),
                          if ((v.jurosParcelamento ?? 0) > 0)
                            linhaTotal('Juros do parcelamento', _moeda.format(v.jurosParcelamento!)),
                          if ((v.taxaServicoCliente ?? 0) > 0)
                            linhaTotal('Taxa de serviço iFood', _moeda.format(v.taxaServicoCliente!)),
                          linhaTotal('Total', _moeda.format(v.valorTotal), forte: true),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _cartao(cores, 'Pagamento', pagamento),
              const SizedBox(height: 12),
              _cartao(cores, v.retirada ? 'Retirada' : 'Entrega', entrega),
              if (v.observacao.isNotEmpty) ...[
                const SizedBox(height: 12),
                _cartao(cores, 'Observação do cliente', [_texto('"${v.observacao}"')]),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
