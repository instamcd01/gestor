import 'package:flutter/material.dart';

class EstatisticasScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Estatísticas'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            // Filtro de data
            _buildDateFilter(context),

            // Resumo das estatísticas
            Expanded(
              child: ListView(
                children: [
                  _buildStatCard(
                    context,
                    'Faturamento',
                    '\$5000',
                        () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => FaturamentoDetailScreen()),
                      );
                    },
                  ),
                  _buildStatCard(
                    context,
                    'Número de Vendas',
                    '120',
                        () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => VendasDetailScreen()),
                      );
                    },
                  ),
                  _buildStatCard(
                    context,
                    'Ticket Médio',
                    '\$41.67',
                        () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => TicketMedioDetailScreen()),
                      );
                    },
                  ),
                  _buildStatCard(
                    context,
                    'Lucro',
                    '\$1500',
                        () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => LucroDetailScreen()),
                      );
                    },
                  ),
                  _buildStatCard(
                    context,
                    'Taxa de Venda',
                    '5%',
                        () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => TaxaVendaDetailScreen()),
                      );
                    },
                  ),
                  _buildStatCard(
                    context,
                    'Taxa de Entrega',
                    '3%',
                        () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => TaxaEntregaDetailScreen()),
                      );
                    },
                  ),
                  _buildStatCard(
                    context,
                    'Meios de Pagamento',
                    'Visa (40%), PayPal (30%), Cash (30%)',
                        () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => MeiosPagamentoDetailScreen()),
                      );
                    },
                  ),
                  _buildStatCard(
                    context,
                    'Ranking dos Produtos',
                    'Produto A - \$2000',
                        () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => RankingProdutosDetailScreen()),
                      );
                    },
                  ),
                  _buildStatCard(
                    context,
                    'Ranking dos Clientes',
                    'Cliente X - \$1000',
                        () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => RankingClientesDetailScreen()),
                      );
                    },
                  ),
                  _buildStatCard(
                    context,
                    'Vendas por Usuário',
                    'Usuário 1 - 50 vendas',
                        () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => VendasUsuarioDetailScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Função para criar o filtro de data
  Widget _buildDateFilter(BuildContext context) {
    return Container(
      margin: EdgeInsets.all(16),
      padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Filtrar por Data', style: TextStyle(fontSize: 16)),
          IconButton(
            icon: Icon(Icons.calendar_today),
            onPressed: () {
              // Lógica para selecionar a data
            },
          ),
        ],
      ),
    );
  }

  // Função para criar um card de estatísticas
  Widget _buildStatCard(BuildContext context, String title, String value, Function() onTap) {
    return Card(
      margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      elevation: 5,
      child: ListTile(
        contentPadding: EdgeInsets.all(16),
        leading: Icon(Icons.bar_chart, size: 40, color: Colors.blue),
        title: Text(
          title,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        subtitle: Text(value, style: TextStyle(fontSize: 16)),
        trailing: Icon(Icons.arrow_forward_ios, color: Colors.blue),
        onTap: onTap,
      ),
    );
  }
}

// Tela de Detalhes - Exemplo de tela de Faturamento
class FaturamentoDetailScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Detalhes de Faturamento')),
      body: Center(child: Text('Exibição detalhada do Faturamento')),
    );
  }
}

// Outras telas de detalhes
class VendasDetailScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Detalhes de Vendas')),
      body: Center(child: Text('Exibição detalhada de Vendas')),
    );
  }
}

class TicketMedioDetailScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Detalhes do Ticket Médio')),
      body: Center(child: Text('Exibição detalhada do Ticket Médio')),
    );
  }
}

class LucroDetailScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Detalhes do Lucro')),
      body: Center(child: Text('Exibição detalhada do Lucro')),
    );
  }
}

class TaxaVendaDetailScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Detalhes da Taxa de Venda')),
      body: Center(child: Text('Exibição detalhada da Taxa de Venda')),
    );
  }
}

class TaxaEntregaDetailScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Detalhes da Taxa de Entrega')),
      body: Center(child: Text('Exibição detalhada da Taxa de Entrega')),
    );
  }
}

class MeiosPagamentoDetailScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Detalhes dos Meios de Pagamento')),
      body: Center(child: Text('Exibição detalhada dos Meios de Pagamento')),
    );
  }
}

class RankingProdutosDetailScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Detalhes do Ranking dos Produtos')),
      body: Center(child: Text('Exibição detalhada do Ranking dos Produtos')),
    );
  }
}

class RankingClientesDetailScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Detalhes do Ranking dos Clientes')),
      body: Center(child: Text('Exibição detalhada do Ranking dos Clientes')),
    );
  }
}

class VendasUsuarioDetailScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Detalhes das Vendas por Usuário')),
      body: Center(child: Text('Exibição detalhada das Vendas por Usuário')),
    );
  }
}
