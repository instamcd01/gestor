import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/modulo.dart';
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
import 'onde_comprar_screen.dart';
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
              MenuItem('Financeiro por Marketplace', Icons.storefront_outlined, const DashboardMarketplaceScreen(), modulos: Modulos.marketplaces),
            ],
          ),
          const SizedBox(height: 20),
          MenuSecao(
            titulo: 'Gestão',
            itens: [
              MenuItem('Custos da Operação', Icons.insights_outlined, const CustosOperacaoScreen(), modulos: [Modulos.gestaoFinanceira]),
              MenuItem('Contas a Pagar', Icons.payment_outlined, const DespesasScreen(apenasPendentes: true)),
              MenuItem('Métricas de Contas a Pagar', Icons.bar_chart_outlined, const MetricasDespesasScreen(), modulos: [Modulos.gestaoFinanceira]),
              MenuItem('Fornecedores', Icons.business_outlined, const FornecedoresScreen(), modulos: [Modulos.compras]),
            ],
          ),
          const SizedBox(height: 20),
          MenuSecao(
            titulo: 'Compras a Fornecedor',
            itens: [
              MenuItem('Sugestão de Compra', Icons.auto_awesome_outlined, const SugestaoCompraScreen(), modulos: [Modulos.compras]),
              MenuItem('Pedidos de Compra', Icons.shopping_cart_outlined, const PedidoCompraListaScreen(), modulos: [Modulos.compras]),
              MenuItem('Onde Comprar', Icons.travel_explore_outlined, const OndeComprarScreen(), modulos: [Modulos.compras]),
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

  /// Contas são pagas toda segunda, então o recorte é por semana de
  /// pagamento (segunda a domingo), não "próximos 7 dias". No sábado/domingo
  /// a 1ª semana já é a seguinte — é o que vai ser pago na segunda que vem.
  /// Mostra 4 semanas pra planejar o caixa, destacando a 1ª que ainda tem
  /// conta em aberto (a que precisa de dinheiro agora); atrasadas ficam
  /// numa linha própria em vermelho no topo.
  Widget _resumoContasAPagar(BuildContext context) {
    final despesas = context.watch<DespesaProvider>().despesas;
    final colorScheme = Theme.of(context).colorScheme;
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    var diasAteDomingo = DateTime.sunday - hoje.weekday;
    if (hoje.weekday >= DateTime.saturday) diasAteDomingo += 7;
    final primeiroDomingo = hoje.add(Duration(days: diasAteDomingo));
    final dataCurta = DateFormat('dd/MM');

    final atrasadas = despesas.where((d) => d.atrasada).toList();
    double soma(List<Despesa> lista) => lista.fold(0.0, (t, d) => t + d.valor);

    final semanas = [
      for (var i = 0; i < 4; i++)
        () {
          final fim = primeiroDomingo.add(Duration(days: 7 * i));
          // 1ª semana começa hoje (antes de hoje já é atrasada); as outras,
          // na segunda.
          final inicio = i == 0 ? hoje : fim.subtract(const Duration(days: 6));
          bool dentro(Despesa d) => !d.dataVencimento.isBefore(inicio) && !d.dataVencimento.isAfter(fim);
          final pendentes = despesas.where((d) => d.status == StatusDespesa.pendente && !d.atrasada && dentro(d)).toList();
          final pagas = despesas.where((d) => d.paga && dentro(d)).length;
          return (inicio: inicio, fim: fim, pendentes: pendentes, total: soma(pendentes), pagas: pagas);
        }(),
    ];
    final indiceDestaque = semanas.indexWhere((s) => s.pendentes.isNotEmpty);

    String rotulo(int i) {
      final s = semanas[i];
      final segunda = s.fim.subtract(const Duration(days: 6));
      final periodo = '${dataCurta.format(segunda)}–${dataCurta.format(s.fim)}';
      // No fim de semana a 1ª semana já é a seguinte — o nome acompanha.
      final semanasAFrente = i + (hoje.weekday >= DateTime.saturday ? 1 : 0);
      return switch (semanasAFrente) {
        0 => 'Esta semana ($periodo)',
        1 => 'Semana que vem ($periodo)',
        _ => periodo,
      };
    }

    Widget linha({
      required String titulo,
      required String valor,
      String? detalhe,
      bool destaque = false,
      Color? cor,
      VoidCallback? onTap,
    }) {
      final corTexto = cor ?? (destaque ? colorScheme.onPrimaryContainer : null);
      return Material(
        color: destaque ? colorScheme.primaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: destaque ? 10 : 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titulo,
                        style: TextStyle(
                          color: corTexto,
                          fontWeight: destaque || cor != null ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                      if (detalhe != null)
                        Text(
                          detalhe,
                          style: TextStyle(fontSize: 12, color: corTexto ?? colorScheme.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
                Text(
                  valor,
                  style: TextStyle(
                    color: corTexto,
                    fontWeight: destaque || cor != null ? FontWeight.w700 : FontWeight.w500,
                    fontSize: destaque ? 17 : 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 10, bottom: 6),
                child: Text('Contas a pagar', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              ),
              if (atrasadas.isNotEmpty)
                linha(
                  titulo: 'Atrasadas',
                  detalhe: '${atrasadas.length} conta${atrasadas.length > 1 ? 's' : ''}',
                  valor: _moeda.format(soma(atrasadas)),
                  cor: colorScheme.error,
                  onTap: () => _abrir(const DespesasScreen(filtroInicial: 'Atrasadas')),
                ),
              for (var i = 0; i < semanas.length; i++)
                linha(
                  titulo: rotulo(i),
                  detalhe: semanas[i].pendentes.isNotEmpty
                      ? '${semanas[i].pendentes.length} conta${semanas[i].pendentes.length > 1 ? 's' : ''}'
                      : (i == 0 && semanas[i].pagas > 0 ? 'tudo pago' : null),
                  valor: semanas[i].pendentes.isNotEmpty
                      ? _moeda.format(semanas[i].total)
                      : (i == 0 && semanas[i].pagas > 0 ? '✓' : '—'),
                  destaque: i == indiceDestaque,
                  onTap: semanas[i].pendentes.isEmpty
                      ? null
                      : () => _abrir(DespesasScreen(
                            filtroInicial: 'Pendentes',
                            periodoVencimento: DateTimeRange(start: semanas[i].inicio, end: semanas[i].fim),
                          )),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
