import 'package:flutter/material.dart';

// Tela principal de configurações do app
class ConfiguracoesScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Configurações do App'),
      ),
      body: ListView(
        children: [
          _buildListTile(context, 'Geral', Icons.settings, GeralScreen()),
          _buildListTile(context, 'Dados da Loja', Icons.store, DadosLojaScreen()),
          // _buildListTile(context, 'Catálogo Online', Icons.library_books, CatalogoOnlineScreen()),
          _buildListTile(context, 'Meu Recibo', Icons.receipt, MeuReciboScreen()),
          _buildListTile(context, 'Opções de Pagamento', Icons.payment, OpcoesPagamentoScreen()),
          _buildListTile(context, 'Pedidos e Vendas', Icons.shopping_cart, PedidosVendasScreen()),
          _buildListTile(context, 'Opções de Entrega', Icons.local_shipping, OpcoesEntregaScreen()),
          _buildListTile(context, 'Exportar Relatórios', Icons.file_copy, ExportarRelatoriosScreen()),
          _buildListTile(context, 'Integrar com Plataformas', Icons.integration_instructions, IntegrarPlataformasScreen()),
        ],
      ),
    );
  }

  // Função que cria o item clicável
  ListTile _buildListTile(BuildContext context, String title, IconData icon, Widget destinationScreen) {
    return ListTile(
      leading: Icon(icon, color: Colors.blue),
      title: Text(title),
      onTap: () {
        // Navegação para a tela correspondente
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => destinationScreen),
        );
      },
    );
  }
}

// Tela Geral
class GeralScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Geral')),
      body: Center(child: Text('Configurações gerais do aplicativo')),
    );
  }
}

// Tela Dados da Loja
class DadosLojaScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Dados da Loja')),
      body: Center(child: Text('Configurações dos dados da loja')),
    );
  }
}

// Tela Catálogo Online
// class CatalogoOnlineScreen extends StatelessWidget {
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(title: Text('Catálogo Online')),
//       body: Center(child: Text('Configurações do catálogo online')),
//     );
//   }
// }

// Tela Meu Recibo
class MeuReciboScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Meu Recibo')),
      body: Center(child: Text('Configurações do recibo')),
    );
  }
}

// Tela Opções de Pagamento
class OpcoesPagamentoScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Opções de Pagamento')),
      body: Center(child: Text('Configurações das opções de pagamento')),
    );
  }
}

// Tela Pedidos e Vendas
class PedidosVendasScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Pedidos e Vendas')),
      body: Center(child: Text('Configurações de pedidos e vendas')),
    );
  }
}

// Tela Opções de Entrega
class OpcoesEntregaScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Opções de Entrega')),
      body: Center(child: Text('Configurações das opções de entrega')),
    );
  }
}

// Tela Exportar Relatórios
class ExportarRelatoriosScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Exportar Relatórios')),
      body: Center(child: Text('Configurações para exportar relatórios')),
    );
  }
}

// Tela Integrar com Plataformas
class IntegrarPlataformasScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Integrar com Plataformas')),
      body: Center(child: Text('Configurações para integrar com plataformas')),
    );
  }
}
