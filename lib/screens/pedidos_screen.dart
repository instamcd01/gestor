import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/pedido_provider.dart';

class PedidosScreen extends StatefulWidget {
  final List<Map<String, dynamic>> pedidosConcluidos;

  PedidosScreen({required this.pedidosConcluidos});

  @override
  _PedidosScreenState createState() => _PedidosScreenState();
}

class _PedidosScreenState extends State<PedidosScreen> {
  String _searchQuery = '';
  String _filtroStatus = 'Todos';
  String _filtroVendedor = 'Todos';

  List<Map<String, dynamic>> get _pedidosFiltrados {
    return widget.pedidosConcluidos
        .where((pedido) {
      if (_filtroStatus != 'Todos' && pedido['status'] != _filtroStatus) {
        return false;
      }
      if (_filtroVendedor != 'Todos' &&
          pedido['vendedor'] != _filtroVendedor) {
        return false;
      }
      if (_searchQuery.isNotEmpty &&
          !pedido.values
              .join(' ')
              .toLowerCase()
              .contains(_searchQuery.toLowerCase())) {
        return false;
      }
      return true;
    })
        .toList();
  }

  double get _totalPedidos {
    return _pedidosFiltrados.fold(
        0.0, (sum, pedido) => sum + (pedido['valor'] ?? 0.0));
  }

  @override
  Widget build(BuildContext context) {
    final pedidos = Provider.of<PedidoProvider>(context).pedidos;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Pedidos'),
        actions: [
          IconButton(
            icon: Icon(Icons.file_download),
            onPressed: () {
              Navigator.pushNamed(context, '/exportarRelatorios');
            },
          ),
          IconButton(
            icon: Icon(Icons.filter_alt),
            onPressed: () {
              Navigator.pushNamed(context, '/filtros');
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Campo de pesquisa
            TextField(
              decoration: InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Pesquisar (item, cliente, valor, código)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
              ),
              onChanged: (query) {
                setState(() {
                  _searchQuery = query;
                });
              },
            ),
            SizedBox(height: 16),
            // Botões de filtro
            Row(
              children: [
                Expanded(
                  child: DropdownButton<String>(
                    value: _filtroStatus,
                    onChanged: (newValue) {
                      setState(() {
                        _filtroStatus = newValue!;
                      });
                    },
                    items: ['Todos', 'Concluído', 'Pendente']
                        .map((status) => DropdownMenuItem(
                      child: Text(status),
                      value: status,
                    ))
                        .toList(),
                    isExpanded: true,
                    hint: Text('Status'),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: DropdownButton<String>(
                    value: _filtroVendedor,
                    onChanged: (newValue) {
                      setState(() {
                        _filtroVendedor = newValue!;
                      });
                    },
                    items: ['Todos', 'Loja A', 'Loja B']
                        .map((vendedor) => DropdownMenuItem(
                      child: Text(vendedor),
                      value: vendedor,
                    ))
                        .toList(),
                    isExpanded: true,
                    hint: Text('Vendedor'),
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            // Lista de pedidos filtrados
            Expanded(
              child: _pedidosFiltrados.isEmpty
                  ? Center(
                child: Text(
                  'Nenhum pedido encontrado',
                  style: TextStyle(fontSize: 16),
                ),
              )
                  : ListView.builder(
                itemCount: pedidos.length,
                itemBuilder: (context, index) {
                  final pedido = pedidos[index];
                  return ListTile(
                    title: Text('Pedido ${pedido.codigo} - ${pedido.cliente}'),
                    subtitle: Text('Valor: R\$ ${pedido.valor.toStringAsFixed(2)}'),
                    trailing: Text(pedido.status),
                  );
                },
              ),
            ),
            // Totais no rodapé
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total de Pedidos:',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${_pedidosFiltrados.length} pedidos - R\$ ${_totalPedidos.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
