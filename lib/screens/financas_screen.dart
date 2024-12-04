import 'package:flutter/material.dart';

class FinancasScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Finanças'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: ListView(
          children: [
            // Card de Contas a Pagar
            _buildCard(
              context,
              'Contas a Pagar',
              Icons.payment,
                  () {
                // Ação ao clicar em Contas a Pagar
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => ContasAPagarScreen()),
                );
              },
            ),

            // Card de Fluxo de Caixa
            _buildCard(
              context,
              'Fluxo de Caixa',
              Icons.attach_money,
                  () {
                // Ação ao clicar em Fluxo de Caixa
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => FluxoCaixaScreen()),
                );
              },
            ),

            // Card de Entradas
            _buildCard(
              context,
              'Entradas',
              Icons.arrow_downward,
                  () {
                // Ação ao clicar em Entradas
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => EntradasScreen()),
                );
              },
            ),

            // Card de Saídas
            _buildCard(
              context,
              'Saídas',
              Icons.arrow_upward,
                  () {
                // Ação ao clicar em Saídas
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => SaidasScreen()),
                );
              },
            ),

            // Card de Fornecedores
            _buildCard(
              context,
              'Fornecedores',
              Icons.business,
                  () {
                // Ação ao clicar em Fornecedores
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => FornecedoresScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // Função para construir um card
  Widget _buildCard(BuildContext context, String title, IconData icon, Function() onTap) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      elevation: 5,
      child: ListTile(
        contentPadding: EdgeInsets.all(16),
        leading: Icon(icon, size: 40, color: Colors.blue),
        title: Text(
          title,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        trailing: Icon(Icons.arrow_forward_ios, color: Colors.blue),
        onTap: onTap,
      ),
    );
  }
}

// Tela de Contas a Pagar
class ContasAPagarScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Contas a Pagar'),
      ),
      body: Center(child: Text('Listagem das contas a pagar')),
    );
  }
}

// Tela de Fluxo de Caixa
class FluxoCaixaScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Fluxo de Caixa'),
      ),
      body: Center(child: Text('Fluxo de caixa')),
    );
  }
}

// Tela de Entradas
class EntradasScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Entradas'),
      ),
      body: Center(child: Text('Listagem das entradas')),
    );
  }
}

// Tela de Saídas
class SaidasScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Saídas'),
      ),
      body: Center(child: Text('Listagem das saídas')),
    );
  }
}

// Tela de Fornecedores
class FornecedoresScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Fornecedores'),
      ),
      body: Center(child: Text('Listagem de fornecedores')),
    );
  }
}
