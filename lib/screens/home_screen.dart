import 'package:flutter/material.dart';
import 'package:gestor/screens/catalogo_online_screen.dart';
import 'package:gestor/screens/cliente_screen.dart';
import 'package:gestor/screens/configuracoes_screen.dart';
import 'package:gestor/screens/estatisticas_screen.dart';
import 'package:gestor/screens/financas_screen.dart';
import 'package:gestor/screens/pedidos_screen.dart';
import 'package:gestor/screens/usuarios_screen.dart';
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
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final clientes = Provider.of<ClientProvider>(context).clientes;

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.blue,
        title: Text(
          'Delivery Pet',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: Icon(Icons.menu),
          onPressed: () {
            _scaffoldKey.currentState?.openDrawer();
          },
        ),
      ),
      drawer: _buildCustomDrawer(context),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView( // Adicionando scroll para garantir que todo conteúdo seja acessível
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              // Espaço para a logo
              Container(
                margin: EdgeInsets.only(bottom: 32),
                // child: Image.asset(
                //   'assets/logo.png', // Insira o caminho da logo
                //   height: 120,
                // ),
              ),

              // Conteúdo adicional
              Text(
                'Bem-vindo ao seu Gestor!',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 20),
              Text(
                'Gerencie seus produtos, pedidos, e clientes de forma simples e eficiente.',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 40),

              // Botões de navegação rápidos
              GridView.builder(
                shrinkWrap: true, // Para garantir que o GridView não ocupe mais espaço que o necessário
                physics: NeverScrollableScrollPhysics(), // Impede que o GridView tenha seu próprio scroll
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2, // 2 colunas para os botões
                  crossAxisSpacing: 20,
                  mainAxisSpacing: 20,
                  childAspectRatio: 1.2, // Ajuste o aspecto para prevenir overflow
                ),
                itemCount: 10, // O número total de botões
                itemBuilder: (context, index) {
                  List<Map<String, dynamic>> buttonData = [
                    {'title': 'Vender', 'icon': Icons.shopping_cart_outlined, 'screen': VendasScreen()},
                    {'title': 'Pedidos', 'icon': Icons.pets, 'screen': PedidosScreen(pedidosConcluidos: [])},
                    {'title': 'Produtos', 'icon': Icons.local_mall, 'screen': ProdutosScreen()},
                    {'title': 'Histórico', 'icon': Icons.history, 'screen': HistoricoVendasScreen()},
                    {'title': 'Clientes', 'icon': Icons.person, 'screen': ClientesScreen()},
                    {'title': 'Catálogo Online', 'icon': Icons.book_online, 'screen': CatalogoOnlineScreen()},
                    {'title': 'Finanças', 'icon': Icons.money, 'screen': FinancasScreen()},
                    {'title': 'Estatísticas', 'icon': Icons.area_chart, 'screen': EstatisticasScreen()},
                    {'title': 'Usuários', 'icon': Icons.person_pin, 'screen': UsuariosScreen()},
                    {'title': 'Configurações', 'icon': Icons.settings, 'screen': ConfiguracoesScreen()},
                  ];

                  return _buildButton(
                    buttonData[index]['title'],
                    buttonData[index]['icon'],
                    buttonData[index]['screen'],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Método para criar botões de navegação
  Widget _buildButton(String title, IconData icon, Widget screen) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => screen),
        );
      },
      child: Card(
        color: Colors.blue[50],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Container(
          padding: EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 40, color: Colors.blue),
              SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(fontSize: 18, color: Colors.blue, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomDrawer(BuildContext context) {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.7, // 70% da largura
      child: Container(
        color: Colors.blue[100],
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
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
              title: Text('Pedidos', style: TextStyle(fontSize: 18)),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => PedidosScreen(pedidosConcluidos: [],)),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.local_mall),
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
            ListTile(
              leading: Icon(Icons.person),
              title: Text('Clientes', style: TextStyle(fontSize: 18)),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ClientesScreen()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.book_online),
              title: Text('Catálogo Online', style: TextStyle(fontSize: 18)),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => CatalogoOnlineScreen()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.money),
              title: Text('Finanças', style: TextStyle(fontSize: 18)),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => FinancasScreen()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.area_chart),
              title: Text('Estatisticas', style: TextStyle(fontSize: 18)),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => EstatisticasScreen()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.person_pin),
              title: Text('Usuários', style: TextStyle(fontSize: 18)),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => UsuariosScreen()),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.settings),
              title: Text('Configurações', style: TextStyle(fontSize: 18)),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ConfiguracoesScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
