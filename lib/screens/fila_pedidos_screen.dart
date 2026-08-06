import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/venda.dart';
import '../providers/historico_vendas_provider.dart';
import '../widgets/categoria_cliente_badge.dart';
import '../widgets/estado_erro_lista.dart';
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
  Timer? _timerUrgencia;

  @override
  void initState() {
    super.initState();
    Provider.of<HistoricoVendasProvider>(context, listen: false).carregarVendas();
    // Os selos de urgência dependem só da hora atual (não de dado novo do
    // servidor) — atualiza sozinho pra não precisar puxar pra atualizar só
    // pra ver um pedido virar "atrasado".
    _timerUrgencia = Timer.periodic(const Duration(seconds: 60), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timerUrgencia?.cancel();
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
    if (agora.isAfter(fim)) return _Urgencia.atrasado;

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
    final prazo = venda.entregaPrevistaFim;
    return venda.ehMarketplace && prazo != null && agora.isAfter(prazo);
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

    if (venda.ehMarketplace && venda.numeroExibicaoMarketplace != null) {
      chips.add(_chipDestaque(context, Icons.confirmation_number_outlined, '#${venda.numeroExibicaoMarketplace}'));
    }

    if (venda.retirada) {
      chips.add(_chipInfo(context, Icons.storefront, 'Retirada'));
    } else {
      final bairro = venda.cliente.bairro;
      if (bairro.isNotEmpty) chips.add(_chipInfo(context, Icons.location_on_outlined, bairro));

      final zona = venda.entregaSelecionada;
      if (zona.isNotEmpty) chips.add(_chipInfo(context, Icons.map_outlined, zona));

      // Só reconstrói "Zona: X-Y min" pra pedido imediato — previsaoInicio/Fim
      // aí é "agora + faixa da zona", então a diferença até dataVenda dá a
      // faixa configurada de volta. Pedido agendado (iFood ou manual) grava
      // um horário absoluto futuro nas mesmas colunas — calcular a diferença
      // até dataVenda daria um número sem sentido (ex: 523-583 min pra um
      // agendamento de amanhã). Esse caso já tem o bloco "Agendado p/ HH:MM"
      // mais abaixo, não precisa duplicar aqui.
      if (!venda.agendado && !venda.agendadoManualmente) {
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

    if (venda.ehMarketplace) {
      chips.add(_chipInfo(
        context,
        venda.pagoPeloMarketplace ? Icons.check_circle_outline : Icons.payments_outlined,
        venda.pagoPeloMarketplace ? 'Pago' : 'Cobrar na entrega',
      ));
    }

    if (venda.troco > 0) {
      chips.add(_chipInfo(context, Icons.money_outlined, 'Troco: R\$ ${venda.troco.toStringAsFixed(2)}'));
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

  String _rotuloCanal(String canal) {
    switch (canal) {
      case 'whatsapp':
        return 'WhatsApp';
      case 'ifood':
        return 'iFood';
      case 'site':
        return 'Site';
      default:
        return 'Loja Física';
    }
  }

  IconData _iconeCanal(String canal) {
    switch (canal) {
      case 'whatsapp':
        return Icons.chat;
      case 'ifood':
        return Icons.delivery_dining;
      case 'site':
        return Icons.language;
      default:
        return Icons.storefront;
    }
  }

  Color _corStatus(String status) {
    switch (status) {
      case StatusPedido.pendente:
        return Colors.orange;
      case StatusPedido.preparando:
        return Colors.blue;
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
    final List<Venda> pedidos;
    if (_filtroStatus == StatusPedido.entregue || _filtroStatus == StatusPedido.cancelado) {
      pedidos = provider.vendas
          .where((v) => v.status == _filtroStatus && _mesmoDia(v.dataVenda, agora))
          .toList();
    } else if (_filtroStatus != null) {
      pedidos = provider.pedidosAtivos.where((v) => v.status == _filtroStatus).toList();
    } else {
      pedidos = provider.pedidosAtivos;
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fila de Pedidos'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => provider.carregarVendas(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: const Text('Em andamento'),
                    selected: _filtroStatus == null,
                    onSelected: (_) => setState(() => _filtroStatus = null),
                  ),
                  const SizedBox(width: 8),
                  ...StatusPedido.emAndamento.map((status) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(StatusPedido.rotulo(status)),
                          selected: _filtroStatus == status,
                          onSelected: (_) => setState(() => _filtroStatus = status),
                        ),
                      )),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('Concluídos'),
                      selected: _filtroStatus == StatusPedido.entregue,
                      onSelected: (_) => setState(() => _filtroStatus = StatusPedido.entregue),
                    ),
                  ),
                  ChoiceChip(
                    label: const Text('Cancelados'),
                    selected: _filtroStatus == StatusPedido.cancelado,
                    onSelected: (_) => setState(() => _filtroStatus = StatusPedido.cancelado),
                  ),
                ],
              ),
            ),
          ),
          if (provider.carregando) const LinearProgressIndicator(),
          Expanded(
            child: provider.erro != null && pedidos.isEmpty
                ? EstadoErroLista(mensagem: provider.erro!, onTentarNovamente: provider.carregarVendas)
                : pedidos.isEmpty
                ? RefreshIndicator(
                    onRefresh: provider.carregarVendas,
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
                            switch (_filtroStatus) {
                              null => 'Nenhum pedido em andamento.',
                              StatusPedido.entregue => 'Nenhum pedido concluído hoje ainda.',
                              StatusPedido.cancelado => 'Nenhum pedido cancelado hoje.',
                              _ => 'Nenhum pedido nesse status.',
                            },
                            style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: provider.carregarVendas,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(12),
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
                                      Icon(_iconeCanal(venda.canalVenda), color: Theme.of(context).colorScheme.onSurfaceVariant),
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
                                              ],
                                            ),
                                            Text(
                                              '#${venda.numeroSequencial ?? '-'} • ${_rotuloCanal(venda.canalVenda)} • $tempoDecorrido',
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
                                if (venda.proximoStatus != null) ...[
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: ElevatedButton(
                                      onPressed: () => _avancarStatus(venda),
                                      child: Text('Marcar: ${StatusPedido.rotulo(venda.proximoStatus!)}'),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
