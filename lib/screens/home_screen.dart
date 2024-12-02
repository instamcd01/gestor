import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/cliente_provider.dart';
import 'vendas_screen.dart';
import 'produtos_screen.dart';
import 'historico_vendas_screen.dart';

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Controlador para o Drawer
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final clientes = Provider.of<ClientProvider>(context).clientes;

    return Scaffold(
      key: _scaffoldKey, // Adiciona a chave para controlar o Drawer
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: Text(
          'PetShop',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.menu),
          onPressed: () {
            // Abre o painel lateral quando o ícone de menu for clicado
            _scaffoldKey.currentState?.openDrawer();
          },
        ),
      ),
      drawer: _buildCustomDrawer(context),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            // Espaço para a logo
            Container(
              margin: EdgeInsets.only(bottom: 32),
              child: Image.asset(
                'assets/logo.png', // Insira o caminho da logo
                height: 120,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Método para criar o Drawer customizado
  Widget _buildCustomDrawer(BuildContext context) {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.7, // 70% da largura
      child: Container(
        color: Colors.blue[100], // Cor de fundo para o painel
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            // Cabeçalho do painel
            DrawerHeader(
              decoration: BoxDecoration(
                color: Colors.blue,
              ),
              child: Row(
                children: [
                  Icon(Icons.pets, size: 40, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'PetShop',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            // Itens do menu
            ListTile(
              leading: Icon(Icons.shopping_cart_outlined),
              title: Text('Vender', style: TextStyle(fontSize: 18)),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => VendasScreen()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.pets),
              title: Text('Produtos', style: TextStyle(fontSize: 18)),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ProdutosScreen()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.history),
              title: Text('Histórico', style: TextStyle(fontSize: 18)),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => HistoricoVendasScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
