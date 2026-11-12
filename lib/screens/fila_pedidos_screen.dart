import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../widgets/faixa_rolavel.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/venda.dart';
import '../providers/branding_provider.dart';
import '../providers/historico_vendas_provider.dart';
import '../repositories/venda_repository.dart';
import '../utils/busca_utils.dart';
import '../utils/canal_venda_utils.dart';
import '../utils/mensagem_status_dialog.dart';
import '../utils/mensagens_status_pedido.dart';
import '../widgets/categoria_cliente_badge.dart';
import '../widgets/estado_erro_lista.dart';
import '../utils/app_destinos.dart';
import 'alterar_forma_pagamento_screen.dart';
import 'separacao_pedido_screen.dart';
import 'venda_detalhes_screen.dart';

/// Urgência do pedido em relação à previsão de entrega calculada pela
/// LOJA (zona escolhida no checkout + faixa de minutos configurada nela —
/// ver `ConfiguracaoEntregaScreen`). `atencao` dispara quando falta só o
/// tempo real de rota (Google Maps) até o prazo da zona acabar — a partir
/// daí, despachar agora é o que garante chegar dentro do prazo.
enum _Urgencia { neutro, atencao, atrasado }

/// Fila de pedidos do dia, de qualquer canal de venda (loja física com
/// entrega, WhatsApp, iFood, site). Por padrão mostra só os em andamento
/// (pendente/em preparo/saiu para entrega) — Concluídos/Cancelados são
/// filtros à parte, escondidos por padrão pra não confundir com o que
/// ainda precisa de ação, e só trazem pedidos de hoje (não é histórico
/// completo, esse já existe em Histórico de Vendas). Vendas de balcão sem
/// entrega não entram na fila em andamento — já nascem como entregues,
/// ver `VendaRepository.registrar`.
class FilaPedidosScreen extends StatefulWidget {
  const FilaPedidosScreen({super.key});

  @override
  State<FilaPedidosScreen> createState() => _FilaPedidosScreenState();
}

class _FilaPedidosScreenState extends State<FilaPedidosScreen> {
  String? _filtroStatus; // null = todos
  String? _filtroModalidade; // null = todas — ver `Venda.modalidade`
  Timer? _timerUrgencia;

  // Layout largo (PC): fila à esquerda + pedido aberto à direita.
  static const larguraPc = 1200.0;
  String? _selecionadoId;
  String _busca = '';
  final _buscaController = TextEditingController();
  final _filaFoco = FocusNode();
  final _chaveSelecionado = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Só o que a Fila mostra (em andamento + hoje) — pedido novo e mudança
      // de status depois disso chegam sozinhos pelo tempo real do provider.
      if (!mounted) return;
      context.read<HistoricoVendasProvider>().atualizarFila();
      // O pedido pode ter chegado antes desta tela existir.
      _abrirPedidoPedido();
    });
    pedidoParaAbrir.addListener(_abrirPedidoPedido);
    // Os selos de urgência dependem só da hora atual (não de dado novo do
    // servidor) — atualiza sozinho pra não precisar puxar pra atualizar só
    // pra ver um pedido virar "atrasado".
    _timerUrgencia = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    pedidoParaAbrir.removeListener(_abrirPedidoPedido);
    _timerUrgencia?.cancel();
    _filaFoco.dispose();
    _buscaController.dispose();
    super.dispose();
  }

  /// Início/fim da janela agendada, seja ela do iFood (agendado +
  /// entregaPrevista*) ou escolhida manualmente — pelo cliente no site ou
  /// pelo vendedor no app (agendadoManualmente + previsaoEntrega*, mesmas
  /// colunas que pra pedido imediato guardam a previsão calculada pela
  /// loja — ver comentário no model Venda).
  DateTime? _agendadoInicio(Venda venda) {
    if (venda.agendado) return venda.entregaPrevistaInicio;
    if (venda.agendadoManualmente) return venda.previsaoEntregaInicio;
    return null;
  }

  DateTime? _agendadoFim(Venda venda) {
    if (venda.agendado) return venda.entregaPrevistaFim;
    if (venda.agendadoManualmente) return venda.previsaoEntregaFim;
    return null;
  }

  _Urgencia _urgenciaPedido(Venda venda, DateTime agora) {
    // Pedido concluído/cancelado não tem mais "atraso" — já acabou. Pedido
    // agendado (iFood ou escolhido manualmente) também não — a janela é
    // escolhida, não uma promessa de "o quanto antes" que possa "atrasar".
    if (!venda.emAndamento || venda.agendado || venda.agendadoManualmente || !venda.temEntrega) {
      return _Urgencia.neutro;
    }
    final fim = venda.previsaoEntregaFim;
    if (fim == null) return _Urgencia.neutro;
    if (venda.atrasadoEm(agora)) return _Urgencia.atrasado;

    // "Atenção" quando o tempo que falta até o prazo da zona é só o
    // suficiente pra rodar a rota real até esse cliente (Google Maps,
    // calculado no checkout) — a partir daí, sair agora é o que garante
    // chegar dentro do prazo.
    final tempoRealMin = venda.cliente.estimativaEntrega;
    if (tempoRealMin != null) {
      final restante = fim.difference(agora);
      if (restante <= Duration(minutes: tempoRealMin)) return _Urgencia.atencao;
    }
    return _Urgencia.neutro;
  }

  /// Sinal independente da urgência acima: o prazo que a própria iFood
  /// prometeu ao cliente dela já estourou — pode estar tudo bem pela
  /// margem interna da loja e mesmo assim já pesar na avaliação/SLA da
  /// plataforma.
  bool _prazoIfoodEstourado(Venda venda, DateTime agora) {
    if (!venda.emAndamento) return false;
    // Retirada imediata: o iFood manda takeoutDateTime = hora do pedido
    // (visto em 10/11, pedido 2840), não um prazo — o selo acendia na hora.
    if (venda.retirada && !venda.agendado) return false;
    final prazo = venda.entregaPrevistaFim;
    return venda.ehMarketplace && prazo != null && agora.isAfter(prazo);
  }

  /// Qual pedido do cliente é este (1º, 2º...), igual o painel do iFood.
  /// `total_pedidos` conta só os ENTREGUES da pessoa (cadastros vinculados
  /// somados), então pedido ainda em andamento é o próximo (+1). Pedido que
  /// veio pela API do iFood usa a contagem da própria plataforma
  /// (ordersCountOnMerchant, histórico do cliente na loja inteira); pedido
  /// de marketplace sem essa contagem (relatório, 99Food) fica sem número.
  int? _ordemPedidoCliente(Venda venda) {
    if (venda.cancelada) return null;
    // ordersCountOnMerchant do iFood conta os pedidos ANTERIORES (veio 0 no
    // 1º pedido da cliente em 11/11), então este é o seguinte (+1).
    if (venda.ehMarketplace || venda.canalVenda == '99food') {
      final anteriores = venda.pedidosClienteNaPlataforma;
      return anteriores == null ? null : anteriores + 1;
    }
    final entregues = venda.cliente.numeroCompras ?? 0;
    return venda.finalizada ? (entregues < 1 ? 1 : entregues) : entregues + 1;
  }

  /// Chip com cor de destaque (fundo na cor primária), diferente do
  /// `_chipInfo` neutro — usado só pro número do pedido na plataforma
  /// (ex: iFood), que o funcionário precisa achar rápido pra falar com o
  /// entregador/cliente ou conferir contra o painel da plataforma.
  Widget _chipDestaque(BuildContext context, IconData icone, String texto) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 12, color: colorScheme.onPrimary),
          const SizedBox(width: 4),
          Text(texto, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: colorScheme.onPrimary)),
        ],
      ),
    );
  }

  Widget _chipInfo(BuildContext context, IconData icone, String texto) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 12, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(texto, style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }

  /// Chips informativos pra decisão de despacho/rota: retirada x entrega,
  /// bairro, zona, faixa de estimativa configurada na zona (min-max —
  /// reconstruída a partir de `previsaoEntregaInicio/Fim`, já que a Venda
  /// não guarda a `ZonaEntrega` em si), distância/tempo real da rota
  /// (Google Maps, calculado no checkout — ver `OpcaoEntregaScreen`) e se
  /// já foi pago ou precisa cobrar na entrega (relevante pra iFood, que
  /// às vezes já paga o pedido pela própria plataforma).
  List<Widget> _chipsInfo(BuildContext context, Venda venda) {
    final chips = <Widget>[];

    if (venda.ehPlataformaDelivery && venda.numeroExibicaoMarketplace != null) {
      chips.add(_chipDestaque(context, Icons.confirmation_number_outlined, '#${venda.numeroExibicaoMarketplace}'));
    }

    // Sinal direto do relatório do iFood (taxa_entrega_paga = 0 com taxa de
    // entrega real existindo) — sem isso o lojista só descobria o frete
    // grátis abrindo o detalhe do pedido.
    if (venda.freteGratisIfood) {
      chips.add(_chipInfo(context, Icons.money_off, 'Frete grátis'));
    }

    if (venda.retirada) {
      chips.add(_chipInfo(context, Icons.storefront, 'Retirada'));
    } else {
      // Chip de modalidade em destaque primeiro — é o dado que o lojista
      // mais precisa pra decidir "entra na rota agora ou pode esperar":
      // Expressa (imediata, zona) x Econômica (dias, config única da loja)
      // x Agendada (janela escolhida, iFood ou manual). Antes só existia
      // "Zona: X-Y min" reconstruído de previsaoEntregaInicio/Fim, que dava
      // número sem sentido (ex: "0-4320 min") pra Econômica, já que ali
      // essas colunas guardam uma data dias no futuro, não uma faixa de
      // minutos — ver `Venda.modalidade`.
      switch (venda.modalidade) {
        case 'agendada':
          chips.add(_chipDestaque(context, Icons.event_outlined, 'Agendada'));
        case 'economica':
          chips.add(_chipDestaque(context, Icons.savings_outlined, 'Econômica'));
        default:
          chips.add(_chipDestaque(context, Icons.bolt_outlined, 'Expressa'));
      }

      final bairro = venda.cliente.bairro;
      if (bairro.isNotEmpty) chips.add(_chipInfo(context, Icons.location_on_outlined, bairro));

      final zona = venda.entregaSelecionada;
      if (zona.isNotEmpty) chips.add(_chipInfo(context, Icons.map_outlined, zona));

      if (venda.modalidade == 'economica') {
        // previsaoEntregaFim aqui guarda a mesma hora-do-dia do pedido (só a
        // DATA já pula dias fechados — ver `finalizar_pedido_site`), então
        // mostrar a hora seria enganoso (mesmo problema já corrigido na
        // página de confirmação do site). Mostra só a data.
        final previsaoFim = venda.previsaoEntregaFim;
        if (previsaoFim != null) {
          chips.add(_chipInfo(context, Icons.schedule_outlined, 'Até ${DateFormat('dd/MM').format(previsaoFim)}'));
        }
      } else if (venda.modalidade == 'expressa') {
        // "Zona: X-Y min" só faz sentido pra pedido imediato — previsaoInicio/
        // Fim aí é "agora + faixa da zona", então a diferença até dataVenda dá
        // a faixa configurada de volta.
        final previsaoInicio = venda.previsaoEntregaInicio;
        final previsaoFim = venda.previsaoEntregaFim;
        if (previsaoInicio != null && previsaoFim != null) {
          final min = previsaoInicio.difference(venda.dataVenda).inMinutes;
          final max = previsaoFim.difference(venda.dataVenda).inMinutes;
          chips.add(_chipInfo(context, Icons.schedule_outlined, 'Zona: $min-$max min'));
        }
      }

      final distancia = venda.cliente.rangeDistancia;
      final estimativa = venda.cliente.estimativaEntrega;
      if (distancia != null && estimativa != null) {
        chips.add(_chipInfo(context, Icons.route_outlined, '${distancia.toStringAsFixed(1)}km • $estimativa min rota'));
      }
    }

    if (venda.ehPlataformaDelivery) {
      chips.add(_chipInfo(
        context,
        venda.pagoPeloMarketplace ? Icons.check_circle_outline : Icons.payments_outlined,
        venda.pagoPeloMarketplace ? 'Pago' : 'Cobrar na entrega',
      ));
    } else if (venda.aguardandoPagamento) {
      chips.add(_chipInfo(context, Icons.hourglass_empty, 'Aguardando confirmação do pagamento'));
    } else if (venda.pagoOnline) {
      chips.add(_chipInfo(context, Icons.check_circle_outline, 'Pago online — não cobrar'));
    }

    if (venda.troco > 0) {
      final pagaraCom = venda.valorPago > venda.valorTotal ? ' (pagará com R\$ ${venda.valorPago.toStringAsFixed(2)})' : '';
      chips.add(_chipInfo(context, Icons.money_outlined, 'Troco: R\$ ${venda.troco.toStringAsFixed(2)}$pagaraCom'));
    }

    if (venda.cupomCodigo != null && venda.desconto > 0) {
      chips.add(_chipInfo(context, Icons.local_offer_outlined, 'Cupom ${venda.cupomCodigo}'));
    }

    // Cartão parcelado na entrega/retirada (não é Mercado Pago) — vendedor
    // precisa saber quantas parcelas configurar na maquininha antes de
    // passar o cartão do cliente.
    if (venda.valorParcelaCartao != null) {
      chips.add(_chipInfo(
        context,
        Icons.credit_card,
        '${venda.parcelasCartao}x de R\$ ${venda.valorParcelaCartao!.toStringAsFixed(2)}',
      ));
    }

    return chips;
  }

  Widget _selo(String texto, Color cor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        texto,
        style: TextStyle(color: cor, fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );
  }

  Color _corUrgencia(_Urgencia urgencia) {
    switch (urgencia) {
      case _Urgencia.atrasado:
        return Colors.red;
      case _Urgencia.atencao:
        return Colors.orange;
      case _Urgencia.neutro:
        return Colors.transparent;
    }
  }

  Color _corStatus(String status) {
    switch (status) {
      case StatusPedido.aguardandoPagamento:
        return Colors.amber;
      case StatusPedido.pendente:
        return Colors.orange;
      case StatusPedido.preparando:
        return Colors.blue;
      case StatusPedido.pronto:
        return Colors.teal;
      case StatusPedido.saiuParaEntrega:
        return Colors.purple;
      case StatusPedido.entregue:
        return Colors.green;
      case StatusPedido.cancelado:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  bool _mesmoDia(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _avancarStatus(Venda venda) async {
    final proximo = venda.proximoStatus;
    if (proximo == null || venda.idVenda == null) return;

    try {
      await Provider.of<HistoricoVendasProvider>(context, listen: false)
          .avancarStatusPedido(venda.idVenda!, proximo);
      // Sem SnackBar de sucesso — o próprio card já muda de cor/texto na
      // hora, avisar de novo só atrapalhava (principalmente marcando vários
      // pedidos em sequência).
    } catch (e) {
      if (!mounted) return;
      final mensagem = e is PostgrestException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível atualizar o pedido: $mensagem')),
      );
    }
  }

  /// Pedido clicado no Início: tira os filtros que poderiam escondê-lo e abre.
  void _abrirPedidoPedido() {
    final id = pedidoParaAbrir.value;
    if (id == null || !mounted) return;
    pedidoParaAbrir.value = null;
    _filtroStatus = null;
    _filtroModalidade = null;
    _busca = '';
    _buscaController.clear();
    _selecionarId(id);
  }

  void _selecionar(Venda venda) => _selecionarId(venda.idVenda);

  void _selecionarId(String? id) {
    _filaFoco.requestFocus();
    setState(() => _selecionadoId = id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _chaveSelecionado.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd);
      final ctx2 = _chaveSelecionado.currentContext;
      if (ctx2 != null) Scrollable.ensureVisible(ctx2, alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart);
    });
  }

  /// ↑ ↓ trocam de pedido, Enter avança o status, W abre o WhatsApp e Esc
  /// fecha — só com o foco na fila, pra não brigar com os campos do painel.
  KeyEventResult _teclaNaFila(KeyEvent evento, List<Venda> pedidos) {
    if (evento is! KeyDownEvent && evento is! KeyRepeatEvent) return KeyEventResult.ignored;
    final tecla = evento.logicalKey;
    final atual = pedidos.indexWhere((v) => v.idVenda == _selecionadoId);
    final selecionado = atual < 0 ? null : pedidos[atual];
    if (tecla == LogicalKeyboardKey.escape && selecionado != null) {
      setState(() => _selecionadoId = null);
      return KeyEventResult.handled;
    }
    if ((tecla == LogicalKeyboardKey.enter || tecla == LogicalKeyboardKey.numpadEnter) &&
        evento is KeyDownEvent &&
        selecionado != null &&
        selecionado.proximoStatus != null) {
      _avancarStatus(selecionado);
      return KeyEventResult.handled;
    }
    if (tecla == LogicalKeyboardKey.keyW && evento is KeyDownEvent && selecionado != null && !selecionado.ehMarketplace) {
      final mensagem = mensagemPadraoStatus(selecionado, selecionado.status,
          nomeLoja: context.read<BrandingProvider>().nomeEmpresa);
      if (mensagem != null) enviarMensagemStatusWhatsApp(context, selecionado, mensagem);
      return KeyEventResult.handled;
    }
    if (tecla == LogicalKeyboardKey.keyS && evento is KeyDownEvent && selecionado != null && _podeSeparar(selecionado)) {
      _abrirSeparacao(selecionado);
      return KeyEventResult.handled;
    }
    final passo = tecla == LogicalKeyboardKey.arrowDown
        ? 1
        : tecla == LogicalKeyboardKey.arrowUp
            ? -1
            : 0;
    if (passo == 0 || pedidos.isEmpty) return KeyEventResult.ignored;
    final novo = atual < 0 ? 0 : (atual + passo).clamp(0, pedidos.length - 1);
    _selecionar(pedidos[novo]);
    return KeyEventResult.handled;
  }

  Widget _comPainel({required bool largo, required List<Venda> pedidos, required Widget lista}) {
    if (!largo) return lista;
    final colorScheme = Theme.of(context).colorScheme;
    final selecionado = _selecionadoId == null ? null : pedidos.where((v) => v.idVenda == _selecionadoId).firstOrNull;
    return LayoutBuilder(builder: (context, limites) {
    // Janela perto do mínimo do PC: fila um pouco mais estreita pra sobrar
    // espaço pro pedido aberto.
    final larguraFila = (limites.maxWidth * 0.36).clamp(340.0, 440.0).toDouble();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: larguraFila,
          child: Focus(
            focusNode: _filaFoco,
            onKeyEvent: (_, evento) => _teclaNaFila(evento, pedidos),
            child: lista,
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: selecionado == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.touch_app_outlined, size: 40, color: colorScheme.onSurfaceVariant),
                      const SizedBox(height: 12),
                      const Text('Clique num pedido pra abrir aqui'),
                      const SizedBox(height: 6),
                      Text('↑ ↓ trocam de pedido · Enter avança o status',
                          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                    ],
                  ),
                )
              // Desenhado pro PC; ações delicadas abrem a tela completa de
              // sempre (ver `_painelPc`). Muda sozinho com o tempo real.
              : _painelPc(selecionado),
        ),
      ],
    );
    });
  }

  bool _podeSeparar(Venda venda) =>
      venda.ehPlataformaDelivery && venda.marketplacePedidoId != null && !venda.cancelada && !venda.finalizada;

  void _abrirSeparacao(Venda venda) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => SeparacaoPedidoScreen(venda: venda)));
  }

  Widget? _linhaAgendado(Venda venda) {
    final inicio = _agendadoInicio(venda);
    final fim = _agendadoFim(venda);
    if (!(venda.agendado || venda.agendadoManualmente) || inicio == null || fim == null) return null;
    final cor = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.event_outlined, size: 14, color: cor),
        const SizedBox(width: 4),
        Text(
          'Agendado: ${DateFormat('dd/MM HH:mm').format(inicio)} - ${DateFormat('HH:mm').format(fim)}',
          style: TextStyle(fontSize: 12, color: cor),
        ),
      ],
    );
  }

  String _rotuloModalidade(Venda venda) {
    if (venda.retirada) return 'Retirada';
    return switch (venda.modalidade) {
      'agendada' => 'Agendada',
      'economica' => 'Econômica',
      _ => 'Expressa',
    };
  }

  /// Mesmos casos do selo de pagamento do cartão do celular (`_chipsInfo`).
  ({String texto, bool pago})? _pagamentoCurto(Venda venda) {
    if (venda.ehPlataformaDelivery) {
      return venda.pagoPeloMarketplace ? (texto: 'Pago', pago: true) : (texto: 'Cobrar na entrega', pago: false);
    }
    if (venda.aguardandoPagamento) return (texto: 'Aguardando pagamento', pago: false);
    if (venda.pagoOnline) return (texto: 'Pago online', pago: true);
    return null;
  }

  String _tempoDesde(DateTime data) {
    final minutos = DateTime.now().difference(data).inMinutes;
    return minutos < 60 ? 'há $minutos min' : 'há ${(minutos / 60).floor()}h${minutos % 60}min';
  }

  void _abrirCompleto(Venda venda) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => VendaDetalhesScreen(venda: venda)));
  }

  /// Linha da fila no PC: o que serve pra decidir qual pedido atender. O
  /// resto (zona, rota, troco, cupom, parcelas) fica nos cartões do painel.
  Widget _linhaPc({
    required Venda venda,
    required bool selecionado,
    required String tempoDecorrido,
    required _Urgencia urgencia,
    required bool ifoodEstourado,
    required Color corUrgencia,
    required NumberFormat currencyFormat,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final apagado = colorScheme.onSurfaceVariant;
    final corBarra = selecionado
        ? colorScheme.primary
        : urgencia != _Urgencia.neutro
            ? corUrgencia
            : ifoodEstourado
                ? Colors.red.shade900
                : Colors.transparent;
    final ordem = _ordemPedidoCliente(venda);
    final partes = [
      rotuloCanalVenda(venda.canalVenda),
      _rotuloModalidade(venda),
      if (!venda.retirada && venda.cliente.bairro.isNotEmpty) venda.cliente.bairro,
      tempoDecorrido,
    ];
    final pagamento = _pagamentoCurto(venda);
    final agendado = _linhaAgendado(venda);

    return Material(
      key: selecionado ? _chaveSelecionado : null,
      color: selecionado ? colorScheme.primary.withValues(alpha: 0.12) : Colors.transparent,
      child: InkWell(
        onTap: () => _selecionar(venda),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: corBarra, width: 3),
              bottom: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
            ),
          ),
          padding: const EdgeInsets.fromLTRB(13, 12, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('#${venda.numeroSequencial ?? '-'}',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: apagado)),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(venda.cliente.nome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                  ),
                  const SizedBox(width: 6),
                  CategoriaClienteBadge(categoria: venda.cliente.categoriaCliente),
                  if (venda.cliente.recebePush) ...[
                    const SizedBox(width: 4),
                    Tooltip(
                      message: 'Recebe notificação do pedido no celular',
                      child: Icon(Icons.notifications_active, size: 14, color: colorScheme.primary),
                    ),
                  ],
                  const Spacer(),
                  const SizedBox(width: 8),
                  _pilulaStatus(venda.status),
                ],
              ),
              const SizedBox(height: 4),
              Text.rich(
                TextSpan(
                  text: partes.join(' · '),
                  children: [
                    if (ordem != null)
                      TextSpan(
                        text: ' · $ordemº pedido',
                        style: ordem == 1 ? TextStyle(color: colorScheme.primary, fontWeight: FontWeight.w700) : null,
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12.5, color: apagado),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Text('${venda.itens.length} itens · ${currencyFormat.format(venda.valorTotal)}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  if (venda.ehPlataformaDelivery && venda.numeroExibicaoMarketplace != null) ...[
                    Text('${venda.nomePlataforma} #${venda.numeroExibicaoMarketplace}', style: TextStyle(fontSize: 11.5, color: apagado)),
                    const SizedBox(width: 10),
                  ],
                  if (pagamento != null)
                    Text(
                      pagamento.texto,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: pagamento.pago ? _tom(Colors.green) : _tom(Colors.amber),
                      ),
                    ),
                  if (venda.observacao.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Tooltip(
                      message: 'Observação: "${venda.observacao}"',
                      child: Icon(Icons.sticky_note_2_outlined, size: 16, color: _tom(Colors.amber)),
                    ),
                  ],
                ],
              ),
              if (agendado != null) ...[
                const SizedBox(height: 4),
                agendado,
              ],
              if (urgencia != _Urgencia.neutro || ifoodEstourado) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    if (urgencia == _Urgencia.atrasado) _selo('Atrasado', Colors.red),
                    if (urgencia == _Urgencia.atencao) _selo('Atenção', Colors.orange),
                    if (ifoodEstourado) _selo('Prazo iFood estourado', Colors.red.shade900),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Tom legível no tema claro e no escuro (os .shade300 fixos só serviam
  /// no escuro: no claro ficavam apagados demais).
  Color _tom(MaterialColor cor) => AppTheme.tomAdaptavel(cor, Theme.of(context).brightness);

  Widget _pilulaStatus(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: _corStatus(status).withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        StatusPedido.rotulo(status),
        style: TextStyle(color: _corStatus(status), fontWeight: FontWeight.w700, fontSize: 11.5),
      ),
    );
  }

  /// Cartão padrão do painel do PC (título em caixa alta + conteúdo).
  Widget _cartaoPc({required String titulo, Widget? acao, required List<Widget> filhos, Color? fundo, Color? borda, Color? corTitulo}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: fundo,
        border: Border.all(color: borda ?? colorScheme.outlineVariant.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(titulo.toUpperCase(),
                  style: TextStyle(
                      fontSize: 11.5,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w700,
                      color: corTitulo ?? colorScheme.onSurfaceVariant)),
              const Spacer(),
              if (acao != null) acao,
            ],
          ),
          const SizedBox(height: 8),
          ...filhos,
        ],
      ),
    );
  }

  Widget _textoCartao(String texto, {bool apagado = false, FontStyle? estilo}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        texto,
        style: TextStyle(
          fontSize: 13.5,
          height: 1.35,
          fontStyle: estilo,
          color: apagado ? Theme.of(context).colorScheme.onSurfaceVariant : null,
        ),
      ),
    );
  }

  Widget _barraEtapas(Venda venda) {
    final colorScheme = Theme.of(context).colorScheme;
    final etapas = [
      StatusPedido.pendente,
      StatusPedido.preparando,
      StatusPedido.pronto,
      if (venda.temEntrega) StatusPedido.saiuParaEntrega,
      StatusPedido.entregue,
    ];
    final atual = etapas.indexOf(venda.status);
    if (atual < 0) {
      // Cancelado, aguardando pagamento/conciliação: fora do fluxo normal.
      return Align(alignment: Alignment.centerLeft, child: _pilulaStatus(venda.status));
    }
    final concluido = venda.status == StatusPedido.entregue;
    // Estreito: só a etapa atual mostra o nome (as outras, número ou ✓ com
    // o nome ao parar o mouse) — os 5 nomes juntos estouravam a linha.
    return LayoutBuilder(builder: (context, limites) {
    final estreito = limites.maxWidth < 620;
    return Row(
      children: [
        for (var i = 0; i < etapas.length; i++) ...[
          Builder(builder: (_) {
            final feita = i < atual || concluido;
            final agora = i == atual && !concluido;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Tooltip(
                  message: StatusPedido.rotulo(etapas[i]),
                  child: Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: feita
                        ? Colors.green.withValues(alpha: 0.22)
                        : agora
                            ? colorScheme.primary
                            : Colors.transparent,
                    border: feita || agora ? null : Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: feita
                      ? Icon(Icons.check, size: 14, color: _tom(Colors.green))
                      : Text('${i + 1}',
                          style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: agora ? colorScheme.onPrimary : colorScheme.onSurfaceVariant)),
                ),
                ),
                if (!estreito || agora) ...[
                  const SizedBox(width: 7),
                  Text(
                    StatusPedido.rotulo(etapas[i]),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: agora ? FontWeight.w700 : FontWeight.w400,
                      color: agora
                          ? colorScheme.onSurface
                          : feita
                              ? _tom(Colors.green)
                              : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            );
          }),
          if (i < etapas.length - 1)
            Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                color: i < atual || concluido ? Colors.green.withValues(alpha: 0.35) : colorScheme.outlineVariant,
              ),
            ),
        ],
      ],
    );
    });
  }

  /// Pedido aberto no PC, no desenho do mockup: cada dado aparece uma vez.
  /// Ações delicadas (cancelar, estornar, editar itens, financeiro, recibo)
  /// abrem a tela completa de sempre — mesmas regras, nada duplicado.
  Widget _painelPc(Venda venda) {
    final colorScheme = Theme.of(context).colorScheme;
    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final mensagemStatus = venda.ehMarketplace
        ? null
        : mensagemPadraoStatus(venda, venda.status, nomeLoja: context.read<BrandingProvider>().nomeEmpresa);
    final ordem = _ordemPedidoCliente(venda);

    final subtitulo = [
      rotuloCanalVenda(venda.canalVenda),
      'feito às ${DateFormat('HH:mm').format(venda.dataVenda)} (${_tempoDesde(venda.dataVenda)})',
      if (venda.ehPlataformaDelivery && venda.numeroExibicaoMarketplace != null) '${venda.nomePlataforma} #${venda.numeroExibicaoMarketplace}',
    ].join(' · ');

    final acoes = <Widget>[
      if (_podeSeparar(venda))
        OutlinedButton.icon(
          onPressed: () => _abrirSeparacao(venda),
          icon: const Icon(Icons.checklist, size: 18),
          label: Text(venda.separacaoStatus == null ? 'Separar pedido  ·  S' : 'Ver separação  ·  S'),
        ),
      if (venda.status == StatusPedido.saiuParaEntrega && venda.formaPagamentoEditavel)
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => AlterarFormaPagamentoScreen(venda: venda)),
          ),
          icon: const Icon(Icons.payments_outlined, size: 18),
          label: const Text('Forma de pagamento'),
        ),
      if (venda.proximoStatus != null)
        FilledButton.icon(
          onPressed: () => _avancarStatus(venda),
          icon: const Icon(Icons.arrow_forward, size: 18),
          label: Text('Marcar: ${StatusPedido.rotulo(venda.proximoStatus!)}  ·  Enter'),
        ),
    ];

    // --- Entrega ---
    final entrega = <Widget>[];
    if (venda.retirada) {
      entrega.add(_textoCartao('Retirada na loja'));
      if (venda.codigoRetiradaExibicao != null) {
        entrega.add(_textoCartao('Código de retirada: ${venda.codigoRetiradaExibicao}', apagado: true));
      }
    } else {
      // 99Food: handover_code também na entrega (conferir com o entregador/cliente).
      if (venda.canalVenda == '99food' && (venda.codigoRetiradaExibicao ?? '').isNotEmpty) {
        entrega.add(_textoCartao('Código de entrega (99Food): ${venda.codigoRetiradaExibicao}'));
      }
      final linhaModalidade = [
        _rotuloModalidade(venda),
        if (venda.entregaSelecionada.isNotEmpty) 'zona ${venda.entregaSelecionada}',
      ].join(' · ');
      entrega.add(_textoCartao(linhaModalidade));
      if (venda.modalidade == 'economica' && venda.previsaoEntregaFim != null) {
        entrega.add(_textoCartao('Até ${DateFormat('dd/MM').format(venda.previsaoEntregaFim!)}', apagado: true));
      } else if (venda.modalidade == 'expressa' && venda.previsaoEntregaInicio != null && venda.previsaoEntregaFim != null) {
        final min = venda.previsaoEntregaInicio!.difference(venda.dataVenda).inMinutes;
        final max = venda.previsaoEntregaFim!.difference(venda.dataVenda).inMinutes;
        entrega.add(_textoCartao('Prazo da zona: $min-$max min', apagado: true));
      }
      final agendado = _linhaAgendado(venda);
      if (agendado != null) entrega.add(Padding(padding: const EdgeInsets.only(bottom: 4), child: agendado));
      if (venda.cliente.enderecoCompleto.isNotEmpty) entrega.add(_textoCartao(venda.cliente.enderecoExibicao));
      final distancia = venda.cliente.rangeDistancia;
      final estimativa = venda.cliente.estimativaEntrega;
      if (distancia != null && estimativa != null) {
        entrega.add(_textoCartao('${distancia.toStringAsFixed(1)} km · $estimativa min de rota', apagado: true));
      }
      if (venda.freteGratisIfood) entrega.add(_textoCartao('Frete grátis (iFood)', apagado: true));
    }

    // --- Pagamento ---
    final pagamento = <Widget>[
      _textoCartao(venda.resumoFormaPagamento),
      if (venda.valorPago > 0 && venda.valorPago != venda.valorTotal)
        _textoCartao('Valor pago: ${moeda.format(venda.valorPago)}', apagado: true),
    ];
    if (venda.aguardandoPagamento) {
      pagamento.add(_textoCartao('Aguardando confirmação do pagamento', apagado: true));
    }
    if (venda.troco > 0) {
      final pagaraCom = venda.valorPago > venda.valorTotal ? ' (pagará com ${moeda.format(venda.valorPago)})' : '';
      pagamento.add(_textoCartao('Troco: ${moeda.format(venda.troco)}$pagaraCom'));
    }
    if (venda.valorParcelaCartao != null) {
      pagamento.add(_textoCartao('${venda.parcelasCartao}x de ${moeda.format(venda.valorParcelaCartao!)} na maquininha'));
    }
    // Bandeira do cartão e CPF/CNPJ na nota: o iFood exige mostrar os dois
    // (critérios de homologação do Order).
    if ((venda.bandeiraCartao ?? '').isNotEmpty) {
      pagamento.add(_textoCartao('Bandeira: ${venda.bandeiraCartao}'));
    }
    if (venda.canalVenda == 'ifood') {
      if (venda.cliente.cnpj.isNotEmpty) {
        pagamento.add(_textoCartao('CNPJ informado no iFood: ${venda.cliente.cnpj}'));
      } else if (venda.cliente.cpf.isNotEmpty) {
        pagamento.add(_textoCartao('CPF informado no iFood: ${venda.cliente.cpf}'));
      }
    }

    Widget linhaTotal(String rotulo, String valor, {bool forte = false}) => Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            children: [
              Text(rotulo,
                  style: TextStyle(
                      fontSize: forte ? 16 : 13,
                      fontWeight: forte ? FontWeight.w700 : FontWeight.w400,
                      color: forte ? null : colorScheme.onSurfaceVariant)),
              const Spacer(),
              Text(valor,
                  style: TextStyle(
                      fontSize: forte ? 16 : 13,
                      fontWeight: forte ? FontWeight.w700 : FontWeight.w500,
                      color: forte ? null : colorScheme.onSurfaceVariant)),
            ],
          ),
        );

    final itensCartao = Container(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(
              children: [
                Text('ITENS (${venda.itens.length})',
                    style: TextStyle(
                        fontSize: 11.5,
                        letterSpacing: 0.6,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurfaceVariant)),
                const Spacer(),
                if (venda.podeEditarItens)
                  TextButton(onPressed: () => _abrirCompleto(venda), child: const Text('Editar itens')),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              itemCount: venda.itens.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
              itemBuilder: (_, i) {
                final item = venda.itens[i];
                final produto = item.produto;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          width: 42,
                          height: 42,
                          color: colorScheme.surfaceContainerHighest,
                          child: produto.imagemUrl.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: produto.imagemUrlExibicao,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 96,
                                  errorWidget: (_, __, ___) =>
                                      Icon(Icons.inventory_2_outlined, size: 18, color: colorScheme.onSurfaceVariant),
                                )
                              : Icon(Icons.inventory_2_outlined, size: 18, color: colorScheme.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 40,
                        child: Text('${item.quantidade}×',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: colorScheme.primary)),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(produto.nome, style: const TextStyle(fontSize: 14, height: 1.3)),
                            if (item.quantidade > 1)
                              Text('${moeda.format(item.precoUnitario)} cada',
                                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                            if ((item.observacaoCliente ?? '').isNotEmpty)
                              Text('"${item.observacaoCliente}"',
                                  style: TextStyle(
                                      fontSize: 12, fontStyle: FontStyle.italic, color: _tom(Colors.amber))),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(moeda.format(item.precoTotal), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ],
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                linhaTotal('Subtotal', moeda.format(venda.subtotal)),
                if (venda.desconto > 0)
                  linhaTotal(
                      venda.cupomCodigo != null
                          ? 'Cupom ${venda.cupomCodigo}${venda.cupomRegra != null ? ' (${venda.cupomRegra})' : ''}'
                          : venda.campanhaMarketplace != null
                              ? 'Desconto (${venda.campanhaMarketplace})'
                              : venda.canalVenda == 'loja_fisica'
                                  ? 'Desconto manual'
                                  : 'Desconto',
                      '− ${moeda.format(venda.desconto)}'),
                if (venda.desconto > 0 && venda.ehPlataformaDelivery)
                  for (final (rotulo, valor) in [
                    ('Custeado pela ${venda.nomePlataforma}', venda.promocaoReembolsadaIfood),
                    ('Custeado pela loja', venda.custoPromocaoPropriaIfood),
                    ('Custeado por patrocinador externo', venda.custoPromocaoExterna),
                    ('Custeado pela rede de lojas', venda.custoPromocaoRede),
                  ])
                    if ((valor ?? 0) > 0)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 12, top: 2),
                          child: Text('$rotulo: ${moeda.format(valor)}',
                              style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                        ),
                      ),
                if (venda.saldoUsado > 0) linhaTotal('Saldo usado', '− ${moeda.format(venda.saldoUsado)}'),
                if (venda.petcashUsado > 0) linhaTotal('PetCash usado', '− ${moeda.format(venda.petcashUsado)}'),
                if (venda.temEntrega)
                  linhaTotal('Entrega', venda.freteGratisIfood ? 'Grátis' : moeda.format(venda.valorEntrega)),
                if ((venda.jurosParcelamento ?? 0) > 0)
                  linhaTotal('Juros do parcelamento (${venda.parcelasCartao}x)', moeda.format(venda.jurosParcelamento!)),
                if ((venda.taxaServicoCliente ?? 0) > 0)
                  linhaTotal('Taxa de serviço ${venda.nomePlataforma} (fica com o ${venda.nomePlataforma})', moeda.format(venda.taxaServicoCliente!)),
                const SizedBox(height: 2),
                linhaTotal('Total', moeda.format(venda.valorTotal), forte: true),
              ],
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 18, 12, 0),
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
                          child: Text('#${venda.numeroSequencial ?? '-'} · ${venda.cliente.nome}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 8),
                        CategoriaClienteBadge(categoria: venda.cliente.categoriaCliente),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        text: subtitulo,
                        children: [
                          if (ordem != null)
                            TextSpan(
                              text: ' · $ordemº pedido',
                              style: TextStyle(
                                  color: ordem == 1 ? colorScheme.primary : null, fontWeight: FontWeight.w700),
                            ),
                        ],
                      ),
                      style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (mensagemStatus != null) ...[
                OutlinedButton.icon(
                  onPressed: () => enviarMensagemStatusWhatsApp(context, venda, mensagemStatus),
                  icon: const Icon(Icons.message, size: 18, color: Colors.green),
                  label: const Text('WhatsApp  ·  W'),
                ),
                const SizedBox(width: 4),
              ],
              PopupMenuButton<VoidCallback>(
                tooltip: 'Mais ações',
                icon: const Icon(Icons.more_vert),
                onSelected: (acao) => acao(),
                itemBuilder: (_) => [
                  PopupMenuItem<VoidCallback>(
                    value: () => _abrirCompleto(venda),
                    child: const ListTile(
                      leading: Icon(Icons.open_in_full),
                      title: Text('Abrir pedido completo'),
                      subtitle: Text('Cancelar, estornar, editar itens, cliente, financeiro e recibo'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _barraEtapas(venda),
                if (acoes.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(alignment: WrapAlignment.end, spacing: 10, runSpacing: 8, children: acoes),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            child: LayoutBuilder(builder: (context, limites) {
            final cartoes = <Widget>[
                      _cartaoPc(titulo: venda.retirada ? 'Retirada' : 'Entrega', filhos: entrega),
                      const SizedBox(height: 12),
                      _cartaoPc(titulo: 'Pagamento', filhos: pagamento),
                      if (venda.observacao.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _cartaoPc(
                          titulo: 'Observação do cliente',
                          fundo: Colors.amber.withValues(alpha: 0.08),
                          borda: Colors.amber.withValues(alpha: 0.45),
                          corTitulo: _tom(Colors.amber),
                          filhos: [_textoCartao('"${venda.observacao}"', estilo: FontStyle.italic)],
                        ),
                      ],
                      const SizedBox(height: 12),
                      _cartaoPc(
                        titulo: 'Histórico',
                        filhos: [_HistoricoPedidoPc(key: ValueKey('${venda.idVenda}|${venda.status}'), venda: venda)],
                      ),
            ];
            // Estreito: itens em cima e os cartões embaixo, tudo rolando
            // junto — lado a lado, o nome do item quebrava a cada palavra.
            if (limites.maxWidth < 640) {
              final alturaItens = (110 + venda.itens.length * 64.0 + venda.desconto.sign * 24).clamp(200.0, 460.0).toDouble();
              return ListView(
                children: [
                  SizedBox(height: alturaItens, child: itensCartao),
                  const SizedBox(height: 12),
                  ...cartoes,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: itensCartao),
                const SizedBox(width: 16),
                Expanded(flex: 2, child: ListView(children: cartoes)),
              ],
            );
            }),
          ),
        ),
      ],
    );
  }

  /// Filtros no PC: status em abas numa linha só (como no desenho) e a
  /// modalidade num seletor compacto à direita. Mesmos filtros do celular.
  Widget _abasPc(List<({String rotulo, String? valor})> abas) {
    final tema = Theme.of(context);
    final cores = tema.colorScheme;
    const modalidades = <(String?, String, IconData)>[
      (null, 'Todas modalidades', Icons.local_shipping_outlined),
      ('expressa', 'Expressa', Icons.bolt_outlined),
      ('economica', 'Econômica', Icons.savings_outlined),
      ('agendada', 'Agendada', Icons.event_outlined),
      ('retirada', 'Retirada', Icons.storefront),
    ];
    final modalidadeAtual = modalidades.firstWhere((m) => m.$1 == _filtroModalidade);
    return Container(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cores.outlineVariant))),
      padding: const EdgeInsets.only(left: 8, right: 12),
      child: Row(
        children: [
          // Rola com a roda do mouse: numa janela estreita as últimas abas
          // (Concluídos, Cancelados, Aguardando pagamento) ficavam escondidas.
          Expanded(
            child: FaixaRolavel(
              espacoBarra: 4,
              child: Row(
                children: [
                  for (final aba in abas)
                    InkWell(
                      onTap: () => setState(() => _filtroStatus = aba.valor),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(
                              width: 3,
                              color: _filtroStatus == aba.valor ? cores.primary : Colors.transparent,
                            ),
                          ),
                        ),
                        child: Text(
                          aba.rotulo,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: _filtroStatus == aba.valor ? FontWeight.w600 : FontWeight.w400,
                            color: _filtroStatus == aba.valor ? cores.primary : cores.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Menu do Flutter trata valor null como "cancelou"; por isso
          // "Todas" usa '' e vira null aqui.
          PopupMenuButton<String>(
            tooltip: 'Filtrar por modalidade',
            initialValue: _filtroModalidade ?? '',
            onSelected: (v) => setState(() => _filtroModalidade = v.isEmpty ? null : v),
            itemBuilder: (_) => [
              for (final m in modalidades)
                PopupMenuItem<String>(
                  value: m.$1 ?? '',
                  child: Row(children: [Icon(m.$3, size: 18), const SizedBox(width: 10), Text(m.$2)]),
                ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _filtroModalidade == null ? cores.outlineVariant : cores.primary),
                color: _filtroModalidade == null ? null : cores.primaryContainer,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(modalidadeAtual.$3, size: 18),
                  const SizedBox(width: 8),
                  Text(modalidadeAtual.$2, style: const TextStyle(fontSize: 14)),
                  const Icon(Icons.arrow_drop_down, size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HistoricoVendasProvider>();
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final agora = DateTime.now();

    // "Em andamento" (padrão) e os status individuais dele usam
    // `pedidosAtivos` (ordem FIFO — mais antigo primeiro, faz sentido pra
    // atender por ordem de chegada). Concluídos/Cancelados são consultados
    // à parte, só do dia — isso aqui é a fila operacional de hoje, não um
    // histórico (esse já existe em Histórico de Vendas).
    List<Venda> pedidos;
    if (_filtroStatus == StatusPedido.entregue || _filtroStatus == StatusPedido.cancelado) {
      pedidos = provider.vendas
          .where((v) => v.status == _filtroStatus && _mesmoDia(v.dataVenda, agora))
          .toList();
    } else if (_filtroStatus == StatusPedido.aguardandoPagamento) {
      // Sem restrição de "hoje": diferente de Concluídos/Cancelados (estado
      // final, só interessa o dia), um pedido preso aguardando pagamento
      // continua precisando de atenção do lojista até ser resolvido, não
      // importa há quanto tempo foi feito.
      pedidos = provider.vendas.where((v) => v.status == StatusPedido.aguardandoPagamento).toList();
    } else if (_filtroStatus != null) {
      pedidos = provider.pedidosAtivos.where((v) => v.status == _filtroStatus).toList();
    } else {
      pedidos = provider.pedidosAtivos;
    }
    // Filtro por modalidade de entrega — independente do filtro de status,
    // ajuda o lojista a separar "precisa entrar em rota agora" (expressa/
    // retirada) de "pode esperar" (econômica) ou "tem hora marcada"
    // (agendada) na hora de planejar as entregas do dia.
    if (_filtroModalidade != null) {
      pedidos = pedidos.where((v) => v.modalidade == _filtroModalidade).toList();
    }

    final largo = MediaQuery.sizeOf(context).width >= larguraPc;
    if (largo && _busca.trim().isNotEmpty) {
      final termo = normalizarBusca(_busca.trim().replaceAll('#', ''));
      pedidos = pedidos
          .where((v) =>
              '${v.numeroSequencial ?? ''}'.contains(termo) ||
              (v.numeroExibicaoMarketplace ?? '').toLowerCase().contains(termo) ||
              contemTodasPalavras(v.cliente.nome, _busca.trim()))
          .toList();
    }
    int contarAtivos(String? status) =>
        status == null ? provider.pedidosAtivos.length : provider.pedidosAtivos.where((v) => v.status == status).length;
    int contarHoje(String status) =>
        provider.vendas.where((v) => v.status == status && _mesmoDia(v.dataVenda, agora)).length;
    final aguardandoPagamento = provider.vendas.where((v) => v.status == StatusPedido.aguardandoPagamento).length;
    final abasStatus = <({String rotulo, String? valor})>[
      (rotulo: 'Em andamento · ${contarAtivos(null)}', valor: null),
      for (final status in StatusPedido.emAndamento)
        (rotulo: '${StatusPedido.rotulo(status)} · ${contarAtivos(status)}', valor: status),
      (rotulo: 'Concluídos hoje · ${contarHoje(StatusPedido.entregue)}', valor: StatusPedido.entregue),
      (rotulo: 'Cancelados hoje · ${contarHoje(StatusPedido.cancelado)}', valor: StatusPedido.cancelado),
      (
        rotulo: 'Aguardando pagamento${aguardandoPagamento > 0 ? ' · $aguardandoPagamento' : ''}',
        valor: StatusPedido.aguardandoPagamento
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fila de Pedidos'),
        actions: [
          if (largo)
            SizedBox(
              width: 260,
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Buscar nº ou cliente nesta lista',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  suffixIcon: _busca.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpar busca',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () {
                            _buscaController.clear();
                            setState(() => _busca = '');
                          },
                        ),
                ),
                controller: _buscaController,
                onChanged: (v) => setState(() => _busca = v),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => provider.atualizarFila(),
          ),
        ],
      ),
      body: Column(
        children: [
          if (largo) _abasPc(abasStatus),
          if (!largo) Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text('Em andamento · ${contarAtivos(null)}'),
                    selected: _filtroStatus == null,
                    onSelected: (_) => setState(() => _filtroStatus = null),
                  ),
                  const SizedBox(width: 8),
                  ...StatusPedido.emAndamento.map((status) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text('${StatusPedido.rotulo(status)} · ${contarAtivos(status)}'),
                          selected: _filtroStatus == status,
                          onSelected: (_) => setState(() => _filtroStatus = status),
                        ),
                      )),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('Concluídos hoje · ${contarHoje(StatusPedido.entregue)}'),
                      selected: _filtroStatus == StatusPedido.entregue,
                      onSelected: (_) => setState(() => _filtroStatus = StatusPedido.entregue),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('Cancelados hoje · ${contarHoje(StatusPedido.cancelado)}'),
                      selected: _filtroStatus == StatusPedido.cancelado,
                      onSelected: (_) => setState(() => _filtroStatus = StatusPedido.cancelado),
                    ),
                  ),
                  ChoiceChip(
                    label: Text('Aguardando pagamento${aguardandoPagamento > 0 ? ' · $aguardandoPagamento' : ''}'),
                    selected: _filtroStatus == StatusPedido.aguardandoPagamento,
                    onSelected: (_) => setState(() => _filtroStatus = StatusPedido.aguardandoPagamento),
                  ),
                ],
              ),
            ),
          ),
          if (!largo) Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('Todas modalidades'),
                    selected: _filtroModalidade == null,
                    onSelected: (_) => setState(() => _filtroModalidade = null),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    avatar: const Icon(Icons.bolt_outlined, size: 16),
                    label: const Text('Expressa'),
                    selected: _filtroModalidade == 'expressa',
                    onSelected: (_) => setState(() => _filtroModalidade = 'expressa'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    avatar: const Icon(Icons.savings_outlined, size: 16),
                    label: const Text('Econômica'),
                    selected: _filtroModalidade == 'economica',
                    onSelected: (_) => setState(() => _filtroModalidade = 'economica'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    avatar: const Icon(Icons.event_outlined, size: 16),
                    label: const Text('Agendada'),
                    selected: _filtroModalidade == 'agendada',
                    onSelected: (_) => setState(() => _filtroModalidade = 'agendada'),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    avatar: const Icon(Icons.storefront, size: 16),
                    label: const Text('Retirada'),
                    selected: _filtroModalidade == 'retirada',
                    onSelected: (_) => setState(() => _filtroModalidade = 'retirada'),
                  ),
                ],
              ),
            ),
          ),
          if (provider.carregando || provider.atualizandoFila) const LinearProgressIndicator(),
          Expanded(
            child: _comPainel(
              largo: largo,
              pedidos: pedidos,
              lista: provider.erro != null && pedidos.isEmpty
                ? EstadoErroLista(mensagem: provider.erro!, onTentarNovamente: provider.atualizarFila)
                : pedidos.isEmpty
                ? RefreshIndicator(
                    onRefresh: provider.atualizarFila,
                    child: ListView(
                      children: [
                        const SizedBox(height: 80),
                        Center(
                          child: Icon(
                            Icons.receipt_long_outlined,
                            size: 56,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: Text(
                            _filtroModalidade != null
                                ? 'Nenhum pedido nessa modalidade.'
                                : switch (_filtroStatus) {
                                    null => 'Nenhum pedido em andamento.',
                                    StatusPedido.entregue => 'Nenhum pedido concluído hoje ainda.',
                                    StatusPedido.cancelado => 'Nenhum pedido cancelado hoje.',
                                    StatusPedido.aguardandoPagamento => 'Nenhum pedido aguardando pagamento.',
                                    _ => 'Nenhum pedido nesse status.',
                                  },
                            style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: provider.atualizarFila,
                    child: ListView.builder(
                      padding: largo ? EdgeInsets.zero : const EdgeInsets.all(12),
                      itemCount: pedidos.length,
                      itemBuilder: (context, index) {
                        final venda = pedidos[index];
                        final minutos = agora.difference(venda.dataVenda).inMinutes;
                        final tempoDecorrido = minutos < 60
                            ? 'há $minutos min'
                            : 'há ${(minutos / 60).floor()}h${minutos % 60}min';
                        final urgencia = _urgenciaPedido(venda, agora);
                        final ifoodEstourado = _prazoIfoodEstourado(venda, agora);
                        final corUrgencia = _corUrgencia(urgencia);
                        final chipsInfo = _chipsInfo(context, venda);

                        if (largo) {
                          return _linhaPc(
                            venda: venda,
                            selecionado: venda.idVenda == _selecionadoId,
                            tempoDecorrido: tempoDecorrido,
                            urgencia: urgencia,
                            ifoodEstourado: ifoodEstourado,
                            corUrgencia: corUrgencia,
                            currencyFormat: currencyFormat,
                          );
                        }
                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: urgencia == _Urgencia.neutro
                                ? BorderSide.none
                                : BorderSide(color: corUrgencia, width: 1.5),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InkWell(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (_) => VendaDetalhesScreen(venda: venda)),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(iconeCanalVenda(venda.canalVenda), color: Theme.of(context).colorScheme.onSurfaceVariant),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(venda.cliente.nome,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                                ),
                                                const SizedBox(width: 6),
                                                CategoriaClienteBadge(categoria: venda.cliente.categoriaCliente),
                                                // Aviso de status chega sozinho no celular dele — não
                                                // precisa mandar texto pelo WhatsApp (pedido do usuário 09/10).
                                                if (venda.cliente.recebePush) ...[
                                                  const SizedBox(width: 4),
                                                  Tooltip(
                                                    message: 'Recebe notificação do pedido no celular',
                                                    child: Icon(Icons.notifications_active,
                                                        size: 16, color: Theme.of(context).colorScheme.primary),
                                                  ),
                                                ],
                                              ],
                                            ),
                                            Text.rich(
                                              TextSpan(
                                                text: '#${venda.numeroSequencial ?? '-'} • ${rotuloCanalVenda(venda.canalVenda)} • $tempoDecorrido',
                                                children: [
                                                  if (_ordemPedidoCliente(venda) case final ordem?)
                                                    TextSpan(
                                                      text: ' • $ordemº pedido',
                                                      style: ordem == 1
                                                          ? TextStyle(
                                                              color: Theme.of(context).colorScheme.primary,
                                                              fontWeight: FontWeight.bold,
                                                            )
                                                          : null,
                                                    ),
                                                ],
                                              ),
                                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                                            ),
                                            Text(
                                              '${venda.itens.length} itens • ${currencyFormat.format(venda.valorTotal)}',
                                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: _corStatus(venda.status).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          StatusPedido.rotulo(venda.status),
                                          style: TextStyle(
                                            color: _corStatus(venda.status),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (chipsInfo.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Wrap(spacing: 6, runSpacing: 4, children: chipsInfo),
                                  ),
                                if ((venda.agendado || venda.agendadoManualmente) &&
                                    _agendadoInicio(venda) != null &&
                                    _agendadoFim(venda) != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Row(
                                      children: [
                                        Icon(Icons.event_outlined,
                                            size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Agendado: ${DateFormat('dd/MM HH:mm').format(_agendadoInicio(venda)!)}'
                                          ' - ${DateFormat('HH:mm').format(_agendadoFim(venda)!)}',
                                          style: TextStyle(
                                              fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                  ),
                                if (venda.observacao.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      '"${venda.observacao}"',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                if (urgencia != _Urgencia.neutro || ifoodEstourado) ...[
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      if (urgencia == _Urgencia.atrasado) _selo('Atrasado', Colors.red),
                                      if (urgencia == _Urgencia.atencao) _selo('Atenção', Colors.orange),
                                      if (ifoodEstourado) _selo('Prazo iFood estourado', Colors.red.shade900),
                                    ],
                                  ),
                                ],
                                // WhatsApp com a mensagem padrão do status atual (ver
                                // `mensagens_status_pedido.dart`) no canto esquerdo, e
                                // as ações do pedido no direito — mesmo diálogo de
                                // revisar/editar antes de enviar já usado na AppBar de
                                // `venda_detalhes_screen.dart`. `null` pra status sem
                                // mensagem definida ou pedido de marketplace (telefone
                                // mascarado pela iFood não recebe WhatsApp).
                                Builder(builder: (context) {
                                  final mensagemStatus =
                                      venda.ehPlataformaDelivery ? null : mensagemPadraoStatus(venda, venda.status, nomeLoja: context.read<BrandingProvider>().nomeEmpresa);
                                  // Só aparece "Forma de pagamento" a partir de "saiu
                                  // para entrega" — é o momento real em que o cliente
                                  // pode mudar de ideia na porta (combinou débito, quer
                                  // pagar Pix; ou quer parcelar um crédito que tinha
                                  // sido à vista). Vale pra qualquer canal cobrado na
                                  // entrega (loja física, WhatsApp, site, iFood/99Food
                                  // ainda não coletado) — só some quando já foi pago de
                                  // verdade por gateway ou pelo marketplace
                                  // (`formaPagamentoEditavel`).
                                  final botoesDireita = <Widget>[
                                    if (venda.status == StatusPedido.saiuParaEntrega && venda.formaPagamentoEditavel)
                                      OutlinedButton.icon(
                                        onPressed: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => AlterarFormaPagamentoScreen(venda: venda),
                                          ),
                                        ),
                                        icon: const Icon(Icons.payments_outlined, size: 18),
                                        label: const Text('Forma de pagamento'),
                                      ),
                                    if (venda.proximoStatus != null)
                                      ElevatedButton(
                                        onPressed: () => _avancarStatus(venda),
                                        child: Text('Marcar: ${StatusPedido.rotulo(venda.proximoStatus!)}'),
                                      ),
                                  ];

                                  if (mensagemStatus == null && botoesDireita.isEmpty) return const SizedBox.shrink();

                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Row(
                                      children: [
                                        if (mensagemStatus != null)
                                          IconButton(
                                            icon: const Icon(Icons.message, color: Colors.green),
                                            tooltip: 'Enviar mensagem por WhatsApp',
                                            onPressed: () =>
                                                enviarMensagemStatusWhatsApp(context, venda, mensagemStatus),
                                          ),
                                        const Spacer(),
                                        if (botoesDireita.isNotEmpty)
                                          Flexible(
                                            child: Wrap(
                                              alignment: WrapAlignment.end,
                                              spacing: 8,
                                              runSpacing: 8,
                                              children: botoesDireita,
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
            ),
          ),
          if (largo) ...[
            const Divider(height: 1),
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.centerLeft,
              child: Text(
                '↑ ↓ trocar de pedido     ·     Enter avançar status     ·     S separar     ·     W WhatsApp     ·     Esc fechar',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Histórico de status do pedido aberto no PC (mesma consulta da aba
/// Histórico da tela completa). A chave inclui o status, então recarrega
/// sozinho quando o pedido avança.
class _HistoricoPedidoPc extends StatefulWidget {
  final Venda venda;

  const _HistoricoPedidoPc({super.key, required this.venda});

  @override
  State<_HistoricoPedidoPc> createState() => _HistoricoPedidoPcState();
}

class _HistoricoPedidoPcState extends State<_HistoricoPedidoPc> {
  late final Future<List<EventoStatusPedido>> _eventos = widget.venda.idVenda == null
      ? Future.value(const <EventoStatusPedido>[])
      : VendaRepository().historicoStatus(widget.venda.idVenda!);

  @override
  Widget build(BuildContext context) {
    final apagado = Theme.of(context).colorScheme.onSurfaceVariant;
    final hoje = DateTime.now();
    return FutureBuilder<List<EventoStatusPedido>>(
      future: _eventos,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LinearProgressIndicator(minHeight: 2);
        }
        if (snapshot.hasError) {
          return Text('Não foi possível carregar o histórico.', style: TextStyle(fontSize: 13, color: apagado));
        }
        final eventos = snapshot.data ?? const [];
        if (eventos.isEmpty) return Text('Sem histórico.', style: TextStyle(fontSize: 13, color: apagado));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final e in eventos)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '${DateFormat(e.dataHora.year == hoje.year && e.dataHora.month == hoje.month && e.dataHora.day == hoje.day ? 'HH:mm' : 'dd/MM HH:mm').format(e.dataHora.toLocal())} · ${StatusPedido.rotulo(e.status)}',
                  style: TextStyle(fontSize: 13, color: apagado),
                ),
              ),
          ],
        );
      },
    );
  }
}
