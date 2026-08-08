import 'package:flutter/material.dart';

import '../widgets/menu_secao.dart';
import 'dashboard_marketplace_screen.dart';
import 'despesas_screen.dart';
import 'entradas_screen.dart';
import 'fluxo_caixa_screen.dart';
import 'fornecedores_screen.dart';
import 'metricas_despesas_screen.dart';
import 'pedido_compra_lista_screen.dart';
import 'sugestao_compra_screen.dart';

class FinancasScreen extends StatelessWidget {
  const FinancasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Finanças')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          MenuSecao(
            titulo: 'Movimentações',
            itens: [
              MenuItem('Fluxo de Caixa', Icons.account_balance_outlined, const FluxoCaixaScreen()),
              MenuItem('Entradas', Icons.arrow_downward, const EntradasScreen()),
              MenuItem('Saídas', Icons.arrow_upward, const DespesasScreen(apenasPendentes: false)),
              MenuItem('Financeiro por Marketplace', Icons.storefront_outlined, const DashboardMarketplaceScreen()),
            ],
          ),
          const SizedBox(height: 20),
          MenuSecao(
            titulo: 'Gestão',
            itens: [
              MenuItem('Contas a Pagar', Icons.payment_outlined, const DespesasScreen(apenasPendentes: true)),
              MenuItem('Métricas de Contas a Pagar', Icons.bar_chart_outlined, const MetricasDespesasScreen()),
              MenuItem('Fornecedores', Icons.business_outlined, const FornecedoresScreen()),
            ],
          ),
          const SizedBox(height: 20),
          MenuSecao(
            titulo: 'Compras a Fornecedor',
            itens: [
              MenuItem('Sugestão de Compra', Icons.auto_awesome_outlined, const SugestaoCompraScreen()),
              MenuItem('Pedidos de Compra', Icons.shopping_cart_outlined, const PedidoCompraListaScreen()),
            ],
          ),
        ],
      ),
    );
  }
}
