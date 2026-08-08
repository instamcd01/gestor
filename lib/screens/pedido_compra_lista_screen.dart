import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/pedido_compra.dart';
import '../providers/pedido_compra_provider.dart';
import '../widgets/estado_erro_lista.dart';
import 'pedido_compra_detalhe_screen.dart';
import 'sugestao_compra_screen.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _data = DateFormat('dd/MM/yyyy');

/// Histórico de pedidos de compra a fornecedor — ponto de entrada pra
/// acompanhar o ciclo rascunho → enviado → confirmado → recebido de cada
/// pedido montado na Sugestão de Compra.
class PedidoCompraListaScreen extends StatefulWidget {
  const PedidoCompraListaScreen({super.key});

  @override
  State<PedidoCompraListaScreen> createState() => _PedidoCompraListaScreenState();
}

class _PedidoCompraListaScreenState extends State<PedidoCompraListaScreen> {
  StatusPedidoCompra? _filtro;

  @override
  void initState() {
    super.initState();
    context.read<PedidoCompraProvider>().carregar();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PedidoCompraProvider>();
    final colorScheme = Theme.of(context).colorScheme;
    final pedidos = _filtro == null ? provider.pedidos : provider.pedidos.where((p) => p.status == _filtro).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pedidos de Compra'),
        actions: [
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
                _ChipFiltro(label: 'Todos', selecionado: _filtro == null, onTap: () => setState(() => _filtro = null)),
                for (final status in StatusPedidoCompra.values)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: _ChipFiltro(
                      label: status.label,
                      selecionado: _filtro == status,
                      onTap: () => setState(() => _filtro = status),
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
                      Text('Nenhum pedido de compra ainda', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 4),
                      Text(
                        'Toque no ícone acima pra ver a sugestão automática de compra.',
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
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: pedidos.length,
                  itemBuilder: (context, index) {
                    final pedido = pedidos[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        title: Text('${pedido.fornecedor.nome} — #${pedido.numeroSequencial ?? '—'}'),
                        subtitle: Text(
                          [
                            if (pedido.createdAt != null) _data.format(pedido.createdAt!),
                            _moeda.format(pedido.valorTotal),
                            '${pedido.itens.length} itens',
                          ].join(' • '),
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
                  },
                ),
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
}

class _ChipFiltro extends StatelessWidget {
  final String label;
  final bool selecionado;
  final VoidCallback onTap;

  const _ChipFiltro({required this.label, required this.selecionado, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(label: Text(label), selected: selecionado, onSelected: (_) => onTap());
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
