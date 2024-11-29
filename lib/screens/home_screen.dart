import 'package:flutter/material.dart';
import 'package:gestor/screens/vendas_screen.dart';
import 'produtos_screen.dart';
import 'historico_vendas_screen.dart';

class HomeScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('PetShop')),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => VendasScreen()),
              );
            },
            child: Text('Vender'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => ProdutosScreen()),
              );
            },
            child: Text('Produtos'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => HistoricoVendasScreen()),
              );
            },
            child: Text('Histórico'),
          ),
        ],
      ),
    );
  }
}
