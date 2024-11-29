import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/vendas_provider.dart';

class HistoricoVendasScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final vendasProvider = Provider.of<VendasProvider>(context);
    return Scaffold(
      appBar: AppBar(title: Text('Histórico de Vendas')),
      body: ListView.builder(
        itemCount: vendasProvider.vendas.length,
        itemBuilder: (ctx, i) {
          return ListTile(
            title: Text('Venda: ${vendasProvider.vendas[i]['produto']}'),
            subtitle: Text('Data: ${vendasProvider.vendas[i]['data']}'),
          );
        },
      ),
    );
  }
}
