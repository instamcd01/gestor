import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
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

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

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

  /// Contas são pagas toda segunda, então o recorte é a semana de
  /// pagamento (até domingo), não "próximos 7 dias". No sábado/domingo já
  /// mostra a semana seguinte — é o que vai ser pago na segunda que vem.
  /// Só aparece quando tem algo pedindo atenção.
  Widget _resumoContasAPagar(BuildContext context) {
    final despesas = context.watch<DespesaProvider>().despesas;
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    var diasAteDomingo = DateTime.sunday - hoje.weekday;
    if (hoje.weekday >= DateTime.saturday) diasAteDomingo += 7;
    final domingo = hoje.add(Duration(days: diasAteDomingo));

    final atrasadas = despesas.where((d) => d.atrasada).toList();
    final venceSemana = despesas
        .where((d) => d.status == StatusDespesa.pendente && !d.atrasada && !d.dataVencimento.isAfter(domingo))
        .toList();
    if (atrasadas.isEmpty && venceSemana.isEmpty) return const SizedBox.shrink();

    double soma(List<Despesa> lista) => lista.fold(0.0, (t, d) => t + d.valor);
    final total = soma(atrasadas) + soma(venceSemana);
    final ateDomingo = 'até dom ${DateFormat('dd/MM').format(domingo)}';

    final partes = [
      if (atrasadas.isNotEmpty)
        '${atrasadas.length} atrasada${atrasadas.length > 1 ? 's' : ''} (${_moeda.format(soma(atrasadas))})',
      if (venceSemana.isNotEmpty)
        '${venceSemana.length} vence${venceSemana.length > 1 ? 'm' : ''} $ateDomingo (${_moeda.format(soma(venceSemana))})',
    ];
    final cor = atrasadas.isNotEmpty ? Colors.red : Colors.orange;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        margin: EdgeInsets.zero,
        child: ListTile(
          onTap: () => _abrir(DespesasScreen(filtroInicial: atrasadas.isNotEmpty ? 'Atrasadas' : 'Pendentes')),
          leading: Icon(Icons.warning_amber_rounded, color: cor),
          title: Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'Contas da semana: '),
              TextSpan(text: _moeda.format(total), style: TextStyle(color: cor, fontWeight: FontWeight.w700)),
            ]),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(partes.join('\n')),
          isThreeLine: partes.length > 1,
          trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        ),
      ),
    );
  }
}
