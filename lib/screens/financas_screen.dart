import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/despesa.dart';
import '../providers/despesa_provider.dart';
import '../widgets/menu_secao.dart';
import 'custos_operacao_screen.dart';
import 'dashboard_marketplace_screen.dart';
import 'despesas_screen.dart';
import 'entradas_screen.dart';
import 'fluxo_caixa_screen.dart';
import 'fornecedores_screen.dart';
import 'metricas_despesas_screen.dart';
import 'pedido_compra_lista_screen.dart';
import 'sugestao_compra_screen.dart';

class FinancasScreen extends StatefulWidget {
  const FinancasScreen({super.key});

  @override
  State<FinancasScreen> createState() => _FinancasScreenState();
}

class _FinancasScreenState extends State<FinancasScreen> {
  @override
  void initState() {
    super.initState();
    // Resumo de contas a pagar lê do mesmo provider da tela de despesas.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<DespesaProvider>().carregar();
    });
  }

  void _abrir(Widget tela) => Navigator.push(context, MaterialPageRoute(builder: (_) => tela));

  Future<void> _lancarDespesa() async {
    final salvou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const DespesaFormScreen(jaPagaPorPadrao: true)),
    );
    if (salvou == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Despesa lançada')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Finanças')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _botaoLancarDespesa(context),
          _resumoContasAPagar(context),
          const SizedBox(height: 20),
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
              MenuItem('Custos da Operação', Icons.insights_outlined, const CustosOperacaoScreen()),
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

  /// Mesmo formato do botão "Vender" do Início, em tom de saída de dinheiro
  /// pra não confundir as duas ações.
  Widget _botaoLancarDespesa(BuildContext context) {
    final fundo = Colors.deepOrange.shade700;
    const texto = Colors.white;
    return Material(
      color: fundo,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: _lancarDespesa,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: texto.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: const Icon(Icons.receipt_long, color: texto, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Lançar despesa',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(color: texto, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Registrar um gasto da loja',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: texto.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios, color: texto, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  /// Só aparece quando tem algo pedindo atenção — sem conta atrasada nem
  /// vencendo nos próximos 7 dias, não ocupa espaço.
  Widget _resumoContasAPagar(BuildContext context) {
    final despesas = context.watch<DespesaProvider>().despesas;
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final limiteSemana = hoje.add(const Duration(days: 7));

    final atrasadas = despesas.where((d) => d.atrasada).length;
    final venceSemana = despesas
        .where((d) => d.status == StatusDespesa.pendente && !d.atrasada && !d.dataVencimento.isAfter(limiteSemana))
        .length;
    if (atrasadas == 0 && venceSemana == 0) return const SizedBox.shrink();

    final partes = [
      if (atrasadas > 0) '$atrasadas atrasada${atrasadas > 1 ? 's' : ''}',
      if (venceSemana > 0) '$venceSemana vence${venceSemana > 1 ? 'm' : ''} em até 7 dias',
    ];
    final cor = atrasadas > 0 ? Colors.red : Colors.orange;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          onTap: () => _abrir(DespesasScreen(filtroInicial: atrasadas > 0 ? 'Atrasadas' : 'Pendentes')),
          leading: Icon(Icons.warning_amber_rounded, color: cor),
          title: const Text('Contas a pagar', style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(partes.join(' • ')),
          trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        ),
      ),
    );
  }
}
