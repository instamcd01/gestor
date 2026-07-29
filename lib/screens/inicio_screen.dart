import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/venda.dart';
import '../providers/auth_provider.dart';
import '../providers/despesa_provider.dart';
import '../providers/historico_vendas_provider.dart';
import '../providers/produto_provider.dart';
import '../widgets/metric_card.dart';
import 'fila_pedidos_screen.dart';
import 'fluxo_caixa_screen.dart';
import 'produtos_screen.dart';
import 'vendas_screen.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

/// Painel inicial do app — pensado como um dashboard (métricas + atalho pra
/// vender), não mais uma grade de botões duplicando a navegação que já existe
/// na sidebar/drawer. Reaproveita os providers já carregados em outras telas
/// (vendas, produtos, despesas), sem nenhuma query nova.
///
/// `mostrarAppBar` existe porque este mesmo conteúdo é usado de duas formas:
/// como destino próprio (com seu Scaffold+AppBar, layout Sidebar) e embutido
/// direto no Scaffold do DrawerHomeShell (que já tem AppBar+Drawer própria).
class InicioScreen extends StatefulWidget {
  final bool mostrarAppBar;

  const InicioScreen({super.key, this.mostrarAppBar = true});

  @override
  State<InicioScreen> createState() => _InicioScreenState();
}

class _InicioScreenState extends State<InicioScreen> {
  @override
  void initState() {
    super.initState();
    Provider.of<HistoricoVendasProvider>(context, listen: false).carregarVendas();
    Provider.of<ProdutoProvider>(context, listen: false).carregarProdutos();
    Provider.of<DespesaProvider>(context, listen: false).carregar();
  }

  Future<void> _recarregarTudo() async {
    await Future.wait([
      context.read<HistoricoVendasProvider>().carregarVendas(),
      context.read<ProdutoProvider>().carregarProdutos(),
      context.read<DespesaProvider>().carregar(),
    ]);
  }

  bool _mesmoDia(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  void _abrir(Widget tela) => Navigator.push(context, MaterialPageRoute(builder: (_) => tela));

  @override
  Widget build(BuildContext context) {
    // Center + maxWidth: em telas largas (desktop, sidebar sempre visível) o
    // conteúdo não deve esticar até a borda — sobra muito espaço em branco e
    // as seções ficam "coladas" no canto esquerdo. Em telas estreitas o
    // ConstrainedBox nunca chega a limitar nada (maxWidth > largura real).
    final auth = context.watch<AuthProvider>();
    final corpo = RefreshIndicator(
      onRefresh: _recarregarTudo,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _cabecalho(context),
                const SizedBox(height: 20),
                _botaoVender(context),
                const SizedBox(height: 28),
                _secaoVendas(context),
                // Resumo agregado de estoque (contagem de produtos/estoque
                // baixo/zerado) é gestão de catálogo, não faz muito sentido
                // pro vendedor no painel inicial — ele já vê o estoque de
                // cada produto individualmente ao vender.
                if (!auth.isVendedor) ...[
                  const SizedBox(height: 28),
                  _secaoEstoque(context),
                ],
                const SizedBox(height: 28),
                _secaoPedidos(context),
                if (auth.podeVerFinancas) ...[
                  const SizedBox(height: 28),
                  _secaoFinancas(context),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    if (!widget.mostrarAppBar) return corpo;

    return Scaffold(
      appBar: AppBar(title: const Text('Início')),
      body: corpo,
    );
  }

  Widget _cabecalho(BuildContext context) {
    final hora = DateTime.now().hour;
    final saudacao = hora < 12 ? 'Bom dia' : (hora < 18 ? 'Boa tarde' : 'Boa noite');
    return Text(
      saudacao,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
    );
  }

  Widget _botaoVender(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.primary,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _abrir(VendasScreen()),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration:
                    BoxDecoration(color: colorScheme.onPrimary.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(Icons.point_of_sale, color: colorScheme.onPrimary, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vender',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(color: colorScheme.onPrimary, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Iniciar uma nova venda',
                      style: Theme.of(context)
                          .textTheme
                          .bodyMedium
                          ?.copyWith(color: colorScheme.onPrimary.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios, color: colorScheme.onPrimary, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tituloSecao(BuildContext context, String titulo, {VoidCallback? onVerTudo}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(titulo, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
        if (onVerTudo != null)
          TextButton(onPressed: onVerTudo, child: const Text('Ver tudo')),
      ],
    );
  }

  Widget _secaoVendas(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    // Vendedor vê só as próprias vendas aqui também — mesma regra já
    // aplicada no Histórico e em "Meu Desempenho".
    final todasVendas = context.watch<HistoricoVendasProvider>().vendas;
    final vendas = (auth.isVendedor
            ? todasVendas.where((v) => v.vendedorId == auth.usuarioAtual?.id)
            : todasVendas)
        .where((v) => v.finalizada)
        .toList();
    final hoje = DateTime.now();
    final ontem = hoje.subtract(const Duration(days: 1));

    final vendasHoje = vendas.where((v) => _mesmoDia(v.dataVenda, hoje)).toList();
    final vendasOntem = vendas.where((v) => _mesmoDia(v.dataVenda, ontem)).toList();
    final vendasMes = vendas.where((v) => v.dataVenda.year == hoje.year && v.dataVenda.month == hoje.month).toList();

    double somar(List<Venda> lista) => lista.fold(0.0, (soma, v) => soma + v.valorTotal);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tituloSecao(context, 'Vendas'),
        const SizedBox(height: 12),
        MetricGrid(
          cartoes: [
            MetricCard(
              icone: Icons.today,
              titulo: 'Hoje',
              valor: _moeda.format(somar(vendasHoje)),
              subtitulo: '${vendasHoje.length} venda(s)',
            ),
            MetricCard(
              icone: Icons.history_toggle_off,
              titulo: 'Ontem',
              valor: _moeda.format(somar(vendasOntem)),
              subtitulo: '${vendasOntem.length} venda(s)',
            ),
            MetricCard(
              icone: Icons.calendar_month,
              titulo: 'Este mês',
              valor: _moeda.format(somar(vendasMes)),
              subtitulo: '${vendasMes.length} venda(s)',
            ),
          ],
        ),
      ],
    );
  }

  Widget _secaoEstoque(BuildContext context) {
    final produtos = context.watch<ProdutoProvider>().produtos.where((p) => p.ativo).toList();
    final baixo = produtos.where((p) => p.estoqueMinimo > 0 && p.estoqueAtual > 0 && p.estoqueAtual <= p.estoqueMinimo)
        .length;
    final zerado = produtos.where((p) => p.estoqueAtual <= 0).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tituloSecao(context, 'Estoque', onVerTudo: () => _abrir(ProdutosScreen())),
        const SizedBox(height: 12),
        MetricGrid(
          cartoes: [
            MetricCard(
              icone: Icons.inventory_2_outlined,
              titulo: 'Produtos ativos',
              valor: '${produtos.length}',
              onTap: () => _abrir(ProdutosScreen()),
            ),
            MetricCard(
              icone: Icons.warning_amber_outlined,
              titulo: 'Estoque baixo',
              valor: '$baixo',
              corIcone: baixo > 0 ? Colors.orange : null,
              onTap: () => _abrir(ProdutosScreen()),
            ),
            MetricCard(
              icone: Icons.remove_shopping_cart_outlined,
              titulo: 'Sem estoque',
              valor: '$zerado',
              corIcone: zerado > 0 ? Colors.red : null,
              onTap: () => _abrir(ProdutosScreen()),
            ),
          ],
        ),
      ],
    );
  }

  Widget _secaoPedidos(BuildContext context) {
    final vendas = context.watch<HistoricoVendasProvider>().vendas;
    final pendente = vendas.where((v) => v.status == StatusPedido.pendente).length;
    final preparando = vendas.where((v) => v.status == StatusPedido.preparando).length;
    final saiuEntrega = vendas.where((v) => v.status == StatusPedido.saiuParaEntrega).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tituloSecao(context, 'Pedidos', onVerTudo: () => _abrir(const FilaPedidosScreen())),
        const SizedBox(height: 12),
        MetricGrid(
          cartoes: [
            MetricCard(
              icone: Icons.hourglass_empty,
              titulo: 'Pendentes',
              valor: '$pendente',
              corIcone: pendente > 0 ? Colors.orange : null,
              onTap: () => _abrir(const FilaPedidosScreen()),
            ),
            MetricCard(
              icone: Icons.soup_kitchen_outlined,
              titulo: 'Em preparo',
              valor: '$preparando',
              corIcone: Colors.blue,
              onTap: () => _abrir(const FilaPedidosScreen()),
            ),
            MetricCard(
              icone: Icons.delivery_dining_outlined,
              titulo: 'Saiu p/ entrega',
              valor: '$saiuEntrega',
              corIcone: Colors.purple,
              onTap: () => _abrir(const FilaPedidosScreen()),
            ),
          ],
        ),
      ],
    );
  }

  Widget _secaoFinancas(BuildContext context) {
    final hoje = DateTime.now();
    final vendasMes = context
        .watch<HistoricoVendasProvider>()
        .vendas
        .where((v) => v.finalizada && v.dataVenda.year == hoje.year && v.dataVenda.month == hoje.month);
    final despesasPagasMes = context.watch<DespesaProvider>().despesas.where(
          (d) =>
              d.paga &&
              d.dataPagamento != null &&
              d.dataPagamento!.year == hoje.year &&
              d.dataPagamento!.month == hoje.month,
        );

    final receita = vendasMes.fold(0.0, (soma, v) => soma + v.valorTotal);
    final despesas = despesasPagasMes.fold(0.0, (soma, d) => soma + d.valor);
    final saldo = receita - despesas;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tituloSecao(context, 'Finanças', onVerTudo: () => _abrir(const FluxoCaixaScreen())),
        const SizedBox(height: 12),
        MetricGrid(
          cartoes: [
            MetricCard(
              icone: Icons.trending_up,
              titulo: 'Receita do mês',
              valor: _moeda.format(receita),
              corIcone: Colors.green,
              onTap: () => _abrir(const FluxoCaixaScreen()),
            ),
            MetricCard(
              icone: Icons.trending_down,
              titulo: 'Despesas do mês',
              valor: _moeda.format(despesas),
              corIcone: Colors.red,
              onTap: () => _abrir(const FluxoCaixaScreen()),
            ),
            MetricCard(
              icone: Icons.account_balance_wallet_outlined,
              titulo: 'Saldo do mês',
              valor: _moeda.format(saldo),
              corIcone: saldo >= 0 ? Colors.green : Colors.red,
              onTap: () => _abrir(const FluxoCaixaScreen()),
            ),
          ],
        ),
      ],
    );
  }
}
