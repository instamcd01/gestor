import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/pedido_compra.dart';
import '../providers/pedido_compra_provider.dart';
import '../widgets/estado_erro_lista.dart';
import 'novo_pedido_manual_screen.dart';
import 'pedido_compra_detalhe_screen.dart';
import 'sugestao_compra_screen.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _data = DateFormat('dd/MM/yyyy');
final _dataCurta = DateFormat('dd/MM');

enum _Visao { emAberto, recebidos, cancelados, todos }

extension on _Visao {
  String get label => switch (this) {
        _Visao.emAberto => 'Em aberto',
        _Visao.recebidos => 'Recebidos',
        _Visao.cancelados => 'Cancelados',
        _Visao.todos => 'Todos',
      };

  bool inclui(StatusPedidoCompra s) => switch (this) {
        _Visao.emAberto =>
          s == StatusPedidoCompra.rascunho || s == StatusPedidoCompra.enviado || s == StatusPedidoCompra.confirmado,
        _Visao.recebidos => s == StatusPedidoCompra.recebido,
        _Visao.cancelados => s == StatusPedidoCompra.cancelado,
        _Visao.todos => true,
      };
}

/// Pedidos de compra a fornecedor. Abre em "Em aberto", separado pelo que
/// pede ação: os que já foram pro fornecedor e esperam entrega (atrasados
/// no topo) e os rascunhos ainda não enviados. Recebidos/cancelados ficam
/// como histórico nos outros filtros.
class PedidoCompraListaScreen extends StatefulWidget {
  const PedidoCompraListaScreen({super.key});

  @override
  State<PedidoCompraListaScreen> createState() => _PedidoCompraListaScreenState();
}

class _PedidoCompraListaScreenState extends State<PedidoCompraListaScreen> {
  _Visao _visao = _Visao.emAberto;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<PedidoCompraProvider>().carregar();
    });
  }

  DateTime _dataReferencia(PedidoCompra p) =>
      p.dataRecebimento ?? p.dataEnvio ?? p.dataConfirmacao ?? p.createdAt ?? DateTime(2000);

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PedidoCompraProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final todos = provider.pedidos;
    final pedidos = todos.where((p) => _visao.inclui(p.status)).toList()
      ..sort((a, b) => _dataReferencia(b).compareTo(_dataReferencia(a)));
    final qtdEmAberto = todos.where((p) => _Visao.emAberto.inclui(p.status)).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pedidos de Compra'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note_outlined),
            tooltip: 'Novo pedido manual',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NovoPedidoManualScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.auto_awesome_outlined),
            tooltip: 'Sugestão de Compra',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SugestaoCompraScreen())),
          ),
        ],
      ),
      body: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                for (final v in _Visao.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(v == _Visao.emAberto ? '${v.label} ($qtdEmAberto)' : v.label),
                      selected: _visao == v,
                      onSelected: (_) => setState(() => _visao = v),
                    ),
                  ),
              ],
            ),
          ),
          if (provider.carregando)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (provider.erro != null)
            Expanded(child: EstadoErroLista(mensagem: provider.erro!, onTentarNovamente: provider.carregar))
          else if (pedidos.isEmpty)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shopping_cart_outlined, size: 56, color: colorScheme.onSurfaceVariant),
                      const SizedBox(height: 16),
                      Text(
                        _visao == _Visao.emAberto ? 'Nenhum pedido em aberto' : 'Nenhum pedido aqui',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Toque em "Sugestão de Compra" pra montar o próximo pedido.',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: provider.carregar,
                child: _visao == _Visao.emAberto ? _listaEmAberto(pedidos) : _listaSimples(pedidos),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SugestaoCompraScreen())),
        icon: const Icon(Icons.auto_awesome_outlined),
        label: const Text('Sugestão de Compra'),
      ),
    );
  }

  Widget _listaSimples(List<PedidoCompra> pedidos) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
      itemCount: pedidos.length,
      itemBuilder: (context, index) => _CardPedido(pedido: pedidos[index]),
    );
  }

  /// Aguardando entrega primeiro (atrasados no topo, depois quem chega
  /// antes), rascunhos depois (mais recentes primeiro).
  Widget _listaEmAberto(List<PedidoCompra> pedidos) {
    final aguardando = pedidos.where((p) => p.status != StatusPedidoCompra.rascunho).toList()
      ..sort((a, b) {
        final pa = a.dataPrevistaEntrega ?? DateTime(2100);
        final pb = b.dataPrevistaEntrega ?? DateTime(2100);
        return pa.compareTo(pb);
      });
    final rascunhos = pedidos.where((p) => p.status == StatusPedidoCompra.rascunho).toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 88),
      children: [
        if (aguardando.isNotEmpty) ...[
          const _TituloSecao(titulo: 'Aguardando entrega', ajuda: 'Já foram pro fornecedor'),
          for (final p in aguardando) _CardPedido(pedido: p),
        ],
        if (rascunhos.isNotEmpty) ...[
          const _TituloSecao(titulo: 'Rascunhos', ajuda: 'Ainda não enviados ao fornecedor'),
          for (final p in rascunhos) _CardPedido(pedido: p),
        ],
      ],
    );
  }
}

class _TituloSecao extends StatelessWidget {
  final String titulo;
  final String ajuda;

  const _TituloSecao({required this.titulo, required this.ajuda});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(titulo, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Flexible(child: Text(ajuda, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant))),
        ],
      ),
    );
  }
}

class _CardPedido extends StatelessWidget {
  final PedidoCompra pedido;

  const _CardPedido({required this.pedido});

  /// Linha de situação: quando chega / se atrasou / há quanto tempo o
  /// rascunho está parado / quando foi recebido.
  ({String texto, Color? cor})? _situacao(ColorScheme colorScheme) {
    final hoje = DateUtils.dateOnly(DateTime.now());
    switch (pedido.status) {
      case StatusPedidoCompra.enviado:
      case StatusPedidoCompra.confirmado:
        final prevista = pedido.dataPrevistaEntrega;
        final enviado = pedido.dataEnvio ?? pedido.dataConfirmacao;
        if (prevista != null) {
          final dias = DateUtils.dateOnly(prevista.toLocal()).difference(hoje).inDays;
          if (dias < 0) return (texto: 'Atrasado ${-dias} dia${dias < -1 ? 's' : ''}', cor: colorScheme.error);
          if (dias == 0) return (texto: 'Chega hoje', cor: Colors.orange.shade800);
          return (texto: 'Previsto pra ${_dataCurta.format(prevista.toLocal())}', cor: null);
        }
        if (enviado != null) {
          final dias = hoje.difference(DateUtils.dateOnly(enviado.toLocal())).inDays;
          return (texto: 'Enviado há $dias dia${dias == 1 ? '' : 's'}', cor: null);
        }
        return null;
      case StatusPedidoCompra.rascunho:
        final criado = pedido.createdAt;
        if (criado == null) return null;
        final dias = hoje.difference(DateUtils.dateOnly(criado.toLocal())).inDays;
        if (dias >= 7) return (texto: 'Rascunho parado há $dias dias', cor: Colors.orange.shade800);
        return null;
      case StatusPedidoCompra.recebido:
        final recebido = pedido.dataRecebimento;
        return recebido != null ? (texto: 'Recebido em ${_data.format(recebido.toLocal())}', cor: null) : null;
      case StatusPedidoCompra.cancelado:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final situacao = _situacao(colorScheme);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        title: Text('${pedido.fornecedor.nome} — #${pedido.numeroSequencial ?? '—'}'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              [
                if (pedido.createdAt != null) _data.format(pedido.createdAt!.toLocal()),
                _moeda.format(pedido.valorTotalConfirmado ?? pedido.valorTotal),
                '${pedido.itens.length} itens',
              ].join(' • '),
            ),
            if (situacao != null)
              Text(
                situacao.texto,
                style: TextStyle(
                  fontSize: 12.5,
                  color: situacao.cor,
                  fontWeight: situacao.cor != null ? FontWeight.w600 : null,
                ),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _BadgeStatus(status: pedido.status),
            if (pedido.temDivergencia)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Icon(Icons.warning_amber_rounded, size: 16, color: Colors.orange),
              ),
          ],
        ),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => PedidoCompraDetalheScreen(pedidoId: pedido.id!)),
        ),
      ),
    );
  }
}

class _BadgeStatus extends StatelessWidget {
  final StatusPedidoCompra status;

  const _BadgeStatus({required this.status});

  MaterialColor _cor() {
    switch (status) {
      case StatusPedidoCompra.rascunho:
        return Colors.grey;
      case StatusPedidoCompra.enviado:
        return Colors.blue;
      case StatusPedidoCompra.confirmado:
        return Colors.orange;
      case StatusPedidoCompra.recebido:
        return Colors.green;
      case StatusPedidoCompra.cancelado:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cor = _cor();
    // shade900 de texto só tem contraste em fundo claro — no tema escuro
    // (fundo do Card já escuro + alpha 0.15 do badge) o texto ficava
    // escuro sobre escuro, ilegível. Inverte pra shade100 no tema escuro.
    final escuro = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: cor.withValues(alpha: escuro ? 0.3 : 0.15), borderRadius: BorderRadius.circular(12)),
      child: Text(
        status.label,
        style: TextStyle(color: escuro ? cor.shade100 : cor.shade900, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}
