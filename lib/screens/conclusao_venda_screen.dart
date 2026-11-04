import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/cliente.dart';
import '../models/produto.dart';
import '../models/venda.dart';
import '../models/zona_entrega.dart';
import '../providers/carrinho_provider.dart';
import '../providers/produto_provider.dart';
import '../providers/historico_vendas_provider.dart';
import '../utils/agendamento_utils.dart';
import 'recibo_screen.dart';

/// Mensagem pronta pra tela. PostgrestException.message já vem limpa — a
/// função `registrar_pedido_completo` lista os produtos exatos que ficaram
/// sem estoque nela; e.toString() mostraria o wrapper inteiro da exceção.
String mensagemErroRegistroVenda(Object e) => e is PostgrestException ? e.message : e.toString();

/// Registra a venda montada no checkout — a MESMA regra pra conclusão do
/// celular (`ConclusaoVendaScreen`) e pro painel do Vender no PC. Monta o
/// `Venda`, grava, recarrega os produtos (o estoque é baixado no banco pelo
/// trigger trg_baixar_estoque) e esvazia o carrinho.
Future<Venda> registrarVendaDoCheckout(
  BuildContext context, {
  required List<Map<String, dynamic>> carrinho,
  required Cliente cliente,
  required String metodoPagamento,
  required double valorTotal,
  double? valorPago,
  double? troco,
  required double desconto,
  String? cupomId,
  required double valorEntrega,
  required String entregaSelecionada,
  required double saldoUsado,
  Map<String, double>? pagamentosDetalhados,
  ZonaEntrega? zonaEntrega,
  JanelaHorarioAgendamento? agendamento,
  int? parcelasCartao,
  double? jurosParcelamento,
}) async {
  final historicoProvider = Provider.of<HistoricoVendasProvider>(context, listen: false);
  final produtoProvider = Provider.of<ProdutoProvider>(context, listen: false);
  final carrinhoProvider = Provider.of<CarrinhoProvider>(context, listen: false);

  final itensVenda = carrinho.map((item) {
    final produto = item['produto'] as Produto;
    final quantidade = item['quantidade'] as int;
    final precoUnitario = (item['precoUnitario'] ?? produto.preco) as double;
    return ItemVenda(
      produto: produto,
      quantidade: quantidade,
      precoUnitario: precoUnitario,
      grupoKitId: item['grupoKitId'] as String?,
    );
  }).toList();

  final subtotal = itensVenda.fold<double>(0, (soma, i) => soma + i.precoTotal);
  final custoTotal = itensVenda.fold<double>(0, (soma, i) => soma + i.custoTotal);
  final lucroTotal = itensVenda.fold<double>(0, (soma, i) => soma + i.lucroTotal);
  final totalItens = itensVenda.fold<int>(0, (soma, i) => soma + i.quantidade);
  final dataVenda = DateTime.now();

  // Previsão automática: zona escolhida no checkout + faixa de minutos
  // configurada nela, ancorada no exato momento do pedido — só quando
  // a zona tem faixa configurada (não é obrigatório). Sobrescrita pela
  // janela explícita quando o vendedor agendou (tela de Entrega).
  final previsaoInicio = agendamento?.inicio ??
      (zonaEntrega?.estimativaMinMin != null ? dataVenda.add(Duration(minutes: zonaEntrega!.estimativaMinMin!)) : null);
  final previsaoFim = agendamento?.fim ??
      (zonaEntrega?.estimativaMinMax != null ? dataVenda.add(Duration(minutes: zonaEntrega!.estimativaMinMax!)) : null);

  final venda = Venda(
    cliente: cliente,
    dataVenda: dataVenda,
    subtotal: subtotal,
    desconto: desconto,
    cupomId: cupomId,
    saldoUsado: saldoUsado,
    valorEntrega: valorEntrega,
    entregaSelecionada: entregaSelecionada,
    valorTotal: valorTotal,
    valorPago: valorPago ?? valorTotal,
    troco: troco ?? 0.0,
    metodoPagamento: metodoPagamento,
    pagamentosDetalhados: pagamentosDetalhados,
    totalItens: totalItens,
    custoTotal: custoTotal,
    lucroTotal: lucroTotal,
    itens: itensVenda,
    previsaoEntregaInicio: previsaoInicio,
    previsaoEntregaFim: previsaoFim,
    agendadoManualmente: agendamento != null,
    parcelasCartao: parcelasCartao,
    jurosParcelamento: jurosParcelamento,
  );

  final vendaRegistrada = await historicoProvider.registrarVenda(venda);
  await produtoProvider.carregarProdutos();
  // Limpa o carrinho — sem isso, um item que ficou sem estoque nessa venda
  // continuava no carrinho global e reaparecia na próxima venda, levando ao
  // mesmo erro de estoque negativo na tentativa seguinte.
  carrinhoProvider.limparCarrinho();
  return vendaRegistrada;
}

class ConclusaoVendaScreen extends StatefulWidget {
  final double valorTotal;
  final List<Map<String, dynamic>> carrinho; // Cada item: {produto, quantidade, precoUnitario, precoTotalItem}
  final String? idCliente;
  final String metodoPagamento;
  final Cliente cliente;
  final double? valorPago;
  final double? troco;
  final double desconto;
  final String? cupomId;
  final double valorEntrega;
  final String entregaSelecionada;
  final double saldoUsado;
  final Map<String, double>? pagamentosDetalhados;
  final ZonaEntrega? zonaEntrega;
  final JanelaHorarioAgendamento? agendamento;
  final int? parcelasCartao;
  final double? jurosParcelamento;

  ConclusaoVendaScreen({
    required this.valorTotal,
    required this.carrinho,
    this.idCliente,
    required this.metodoPagamento,
    required this.cliente,
    this.valorPago,
    this.troco,
    required this.desconto,
    this.cupomId,
    required this.valorEntrega,
    required this.entregaSelecionada,
    required this.saldoUsado,
    this.pagamentosDetalhados,
    this.zonaEntrega,
    this.agendamento,
    this.parcelasCartao,
    this.jurosParcelamento,
  });

  @override
  _ConclusaoVendaScreenState createState() => _ConclusaoVendaScreenState();
}

class _ConclusaoVendaScreenState extends State<ConclusaoVendaScreen> {
  bool _isRegistrado = false;
  String? _erro;
  Venda? _vendaRegistrada;

  @override
  void initState() {
    super.initState();
    _registrarVenda();
  }

  Future<void> _registrarVenda() async {
    setState(() => _erro = null);

    try {
      final vendaRegistrada = await registrarVendaDoCheckout(
        context,
        carrinho: widget.carrinho,
        cliente: widget.cliente,
        metodoPagamento: widget.metodoPagamento,
        valorTotal: widget.valorTotal,
        valorPago: widget.valorPago,
        troco: widget.troco,
        desconto: widget.desconto,
        cupomId: widget.cupomId,
        valorEntrega: widget.valorEntrega,
        entregaSelecionada: widget.entregaSelecionada,
        saldoUsado: widget.saldoUsado,
        pagamentosDetalhados: widget.pagamentosDetalhados,
        zonaEntrega: widget.zonaEntrega,
        agendamento: widget.agendamento,
        parcelasCartao: widget.parcelasCartao,
        jurosParcelamento: widget.jurosParcelamento,
      );

      if (!mounted) return;
      setState(() {
        _isRegistrado = true;
        _vendaRegistrada = vendaRegistrada;
      });

      // Abre o recibo automaticamente — o vendedor decide ali se quer
      // enviar pro cliente ou só voltar (o botão "Nova Venda" continua
      // por baixo, na tela de confirmação).
      if (mounted) {
        Navigator.push(context, MaterialPageRoute(builder: (_) => ReciboScreen(venda: vendaRegistrada)));
      }
    } catch (e) {
      debugPrint('Erro ao registrar venda: $e');
      if (mounted) setState(() => _erro = mensagemErroRegistroVenda(e));
    }
  }

  bool get _erroDeEstoque => _erro?.toLowerCase().contains('estoque') ?? false;

  @override
  Widget build(BuildContext context) {
    if (_erro != null) {
      // Erro de estoque não é transitório — "tentar de novo" com o mesmo
      // carrinho falha sempre da mesma forma. Precisa voltar e ajustar (ou
      // remover) o item que ficou sem estoque. A própria mensagem (`_erro`)
      // já lista quais produtos, vinda direto do banco.
      return Scaffold(
        appBar: AppBar(title: const Text('Erro ao Registrar Venda')),
        body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 100),
              const SizedBox(height: 20),
              const Text(
                'Não foi possível registrar a venda.',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(_erro!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 30),
              if (!_erroDeEstoque) ...[
                ElevatedButton(
                  onPressed: _registrarVenda,
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                  child: const Text('Tentar novamente'),
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton(
                onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
                style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 50)),
                child: Text(_erroDeEstoque ? 'Voltar e ajustar o carrinho' : 'Cancelar e voltar ao início'),
              ),
            ],
          ),
        ),
      );
    }

    if (!_isRegistrado) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final colorScheme = Theme.of(context).colorScheme;
    final temDetalhes = widget.desconto > 0 ||
        widget.saldoUsado > 0 ||
        (widget.pagamentosDetalhados?.isNotEmpty ?? false) ||
        widget.metodoPagamento.toLowerCase() == 'dinheiro';

    return Scaffold(
      appBar: AppBar(title: Text('Venda Concluída'), automaticallyImplyLeading: false),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 88),
              const SizedBox(height: 16),
              Text(
                'Venda concluída com sucesso!',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                widget.metodoPagamento,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Text(
                        'R\$ ${widget.valorTotal.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                      ),
                      if (temDetalhes) ...[
                        const Divider(height: 24),
                        if (widget.desconto > 0)
                          _linha(context, 'Desconto aplicado', '- R\$ ${widget.desconto.toStringAsFixed(2)}'),
                        if (widget.saldoUsado > 0)
                          _linha(context, 'Saldo do cliente', '- R\$ ${widget.saldoUsado.toStringAsFixed(2)}'),
                        if (widget.metodoPagamento.toLowerCase() == 'dinheiro') ...[
                          _linha(
                            context,
                            'Valor pago',
                            'R\$ ${widget.valorPago?.toStringAsFixed(2) ?? widget.valorTotal.toStringAsFixed(2)}',
                          ),
                          _linha(context, 'Troco', 'R\$ ${widget.troco?.toStringAsFixed(2) ?? "0.00"}'),
                        ],
                        if (widget.pagamentosDetalhados != null && widget.pagamentosDetalhados!.isNotEmpty)
                          ...widget.pagamentosDetalhados!.entries
                              .map((e) => _linha(context, e.key, 'R\$ ${e.value.toStringAsFixed(2)}')),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ReciboScreen(venda: _vendaRegistrada!)),
                ),
                icon: const Icon(Icons.receipt_long),
                label: const Text('Ver Recibo'),
                style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                child: const Text('Nova Venda'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _linha(BuildContext context, String rotulo, String valor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(rotulo, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          Text(valor, style: const TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
