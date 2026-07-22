import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/venda.dart';
import '../providers/historico_vendas_provider.dart';
import 'venda_detalhes_screen.dart';

/// Fila de pedidos em andamento (pendente/em preparo/saiu para entrega),
/// de qualquer canal de venda (loja física com entrega, WhatsApp, iFood,
/// site). Vendas de balcão sem entrega não passam por aqui — já nascem
/// como entregues, ver `VendaRepository.registrar`.
class FilaPedidosScreen extends StatefulWidget {
  const FilaPedidosScreen({super.key});

  @override
  State<FilaPedidosScreen> createState() => _FilaPedidosScreenState();
}

class _FilaPedidosScreenState extends State<FilaPedidosScreen> {
  String? _filtroStatus; // null = todos

  @override
  void initState() {
    super.initState();
    Provider.of<HistoricoVendasProvider>(context, listen: false).carregarVendas();
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
      default:
        return Colors.grey;
    }
  }

  Future<void> _avancarStatus(Venda venda) async {
    final proximo = venda.proximoStatus;
    if (proximo == null || venda.idVenda == null) return;

    try {
      await Provider.of<HistoricoVendasProvider>(context, listen: false)
          .avancarStatusPedido(venda.idVenda!, proximo);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pedido marcado como "${StatusPedido.rotulo(proximo)}".')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível atualizar o pedido: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HistoricoVendasProvider>();
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final agora = DateTime.now();

    var pedidos = provider.pedidosAtivos;
    if (_filtroStatus != null) {
      pedidos = pedidos.where((v) => v.status == _filtroStatus).toList();
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
                    label: const Text('Todos'),
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
                ],
              ),
            ),
          ),
          if (provider.carregando) const LinearProgressIndicator(),
          Expanded(
            child: pedidos.isEmpty
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
                            _filtroStatus == null
                                ? 'Nenhum pedido em andamento.'
                                : 'Nenhum pedido nesse status.',
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

                        return Card(
                          margin: const EdgeInsets.only(bottom: 10),
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
                                    children: [
                                      Icon(_iconeCanal(venda.canalVenda), color: Theme.of(context).colorScheme.onSurfaceVariant),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(venda.cliente.nome,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                            Text(
                                              '${venda.itens.length} itens • ${currencyFormat.format(venda.valorTotal)} • $tempoDecorrido',
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
