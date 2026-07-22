import 'package:flutter/material.dart';
import 'package:flutter_icons_null_safety/flutter_icons_null_safety.dart';
import 'package:gestor/screens/pagamento_link_screen.dart';
import 'package:gestor/screens/pagamento_outros_screen.dart';
import 'package:gestor/screens/pagamento_pix_screen.dart';
import 'package:provider/provider.dart';

import '../config/supabase_config.dart';
import '../models/cliente.dart';
import '../providers/auth_provider.dart';
import '../utils/cliente_validators.dart';
import '../utils/formatadores_input.dart';
import '../widgets/itens_compra_card.dart';
import '../widgets/resumo_pagamento_card.dart';
import 'adicionar_cliente_screen.dart';
import 'opcoes_pagamento_screen.dart';
import 'pagamento_credito_screen.dart';
import 'pagamento_debito_screen.dart';
import 'pagamento_dinheiro_screen.dart';
import 'desconto_screen.dart';

class PagamentoScreen extends StatefulWidget {
  final double valorTotal;
  final String idVenda;
  final Cliente cliente;
  final List<Map<String, dynamic>> carrinho;
  final double desconto;
  final double valorEntrega;
  final String entregaSelecionada;

  PagamentoScreen({
    required this.valorTotal,
    required this.idVenda,
    required this.carrinho,
    required this.cliente,
    required this.desconto,
    required this.valorEntrega,
    required this.entregaSelecionada,
  });

  @override
  _PagamentoScreenState createState() => _PagamentoScreenState();
}

class _PagamentoScreenState extends State<PagamentoScreen> {
  String metodoPagamentoSelecionado = '';
  final TextEditingController _saldoController = TextEditingController();

  // Base fixa da venda — nunca reatribuída depois de calculada, pra não
  // acumular erro. Tudo que muda (desconto, saldo) é aplicado em cima
  // dela sempre a partir do zero, no getter `valorTotal`.
  late final double _subtotal;
  double desconto = 0.0;
  double saldoUsado = 0.0;

  // Cliente da venda em andamento — mutável porque "Cadastrar Novo Cliente"
  // durante o checkout deve passar a usar o cliente recém-criado, não o
  // original recebido no construtor.
  late Cliente _cliente;

  List<String> _metodosAtivos = List.from(metodosPagamentoDisponiveis);

  @override
  void initState() {
    super.initState();
    _subtotal = widget.carrinho.fold<double>(
      0.0,
      (soma, item) => soma + ((item['precoTotalItem'] as num?)?.toDouble() ?? 0.0),
    );
    desconto = widget.desconto;
    _cliente = widget.cliente;
    _carregarMetodosAtivos();
  }

  Future<void> _carregarMetodosAtivos() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;
    try {
      final data = await supabase
          .from('empresas')
          .select('metodos_pagamento_ativos')
          .eq('id', empresaId)
          .single();
      final metodos = (data['metodos_pagamento_ativos'] as List?)?.map((m) => m.toString()).toList();
      if (metodos != null && metodos.isNotEmpty && mounted) {
        setState(() => _metodosAtivos = metodos);
      }
    } catch (e) {
      debugPrint('Erro ao carregar métodos de pagamento ativos: $e');
    }
  }

  static const _iconesPorMetodo = <String, IconData>{
    'Dinheiro': Icons.money,
    'Cartão de Débito': FlutterIcons.credit_card_outline_mco,
    'Cartão de Crédito': FlutterIcons.credit_card_mdi,
    'Pix': Icons.pix,
    'Link de Pagamento': Icons.link,
    'Outros': Icons.more_horiz,
  };

  List<Map<String, dynamic>> get _opcoesPagamentoFiltradas => _metodosAtivos
      .where((metodo) => _iconesPorMetodo.containsKey(metodo))
      .map((metodo) => {'metodo': metodo, 'icone': _iconesPorMetodo[metodo]!})
      .toList();

  @override
  void dispose() {
    _saldoController.dispose();
    super.dispose();
  }

  /// Valor a pagar antes de aplicar o saldo do cliente — usado como teto
  /// pra quanto de saldo pode ser usado.
  double get _valorAntesDoSaldo {
    final v = _subtotal - desconto + widget.valorEntrega;
    return v < 0 ? 0.0 : v;
  }

  double get valorTotal {
    final v = _valorAntesDoSaldo - saldoUsado;
    return v < 0 ? 0.0 : v;
  }

  void aplicarSaldo(double valor) {
    final saldoDisponivel = _cliente.saldo;

    if (valor <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um valor de saldo válido.')),
      );
      return;
    }
    if (valor > saldoDisponivel) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saldo insuficiente.')),
      );
      return;
    }
    if (valor > _valorAntesDoSaldo) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saldo não pode ser maior que o valor a pagar.')),
      );
      return;
    }

    setState(() => saldoUsado = valor);
  }

  void limparSaldo() {
    setState(() {
      saldoUsado = 0.0;
      _saldoController.clear();
    });
  }

  void selecionarMetodoPagamento(String metodo) {
    setState(() => metodoPagamentoSelecionado = metodo);
  }

  void aplicarDesconto() async {
    final baseSemDesconto = _subtotal + widget.valorEntrega;
    final novoValorComDesconto = await Navigator.push<double>(
      context,
      MaterialPageRoute(
        builder: (context) => DescontoScreen(valorTotal: baseSemDesconto),
      ),
    );

    if (novoValorComDesconto != null) {
      setState(() {
        desconto = (baseSemDesconto - novoValorComDesconto).clamp(0, baseSemDesconto);
        // O saldo já aplicado não pode passar a exceder o novo valor devido.
        if (saldoUsado > _valorAntesDoSaldo) {
          saldoUsado = _valorAntesDoSaldo;
        }
      });
    }
  }

  void limparDesconto() {
    setState(() {
      desconto = 0.0;
      if (saldoUsado > _valorAntesDoSaldo) {
        saldoUsado = _valorAntesDoSaldo;
      }
    });
  }

  Future<void> cadastrarNovoCliente() async {
    final novoCliente = await Navigator.push<Cliente>(
      context,
      MaterialPageRoute(
        builder: (context) => AdicionarClienteScreen(),
      ),
    );
    if (novoCliente != null) {
      setState(() => _cliente = novoCliente);
    }
  }

  void navegarParaTelaPagamento() {
    final total = double.parse(valorTotal.toStringAsFixed(2));

    if (metodoPagamentoSelecionado == 'Dinheiro') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PagamentoDinheiroScreen(
            valorTotal: total,
            carrinho: widget.carrinho,
            metodoPagamento: metodoPagamentoSelecionado,
            cliente: _cliente,
            desconto: desconto,
            valorEntrega: widget.valorEntrega,
            entregaSelecionada: widget.entregaSelecionada,
            saldoUsado: saldoUsado,
          ),
        ),
      );
    } else if (metodoPagamentoSelecionado == 'Cartão de Débito') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PagamentoCartaoDebitoScreen(
            valorTotal: total,
            carrinho: widget.carrinho,
            metodoPagamento: metodoPagamentoSelecionado,
            cliente: _cliente,
            desconto: desconto,
            valorEntrega: widget.valorEntrega,
            entregaSelecionada: widget.entregaSelecionada,
            saldoUsado: saldoUsado,
          ),
        ),
      );
    } else if (metodoPagamentoSelecionado == 'Cartão de Crédito') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PagamentoCartaoCreditoScreen(
            valorTotal: total,
            carrinho: widget.carrinho,
            metodoPagamento: metodoPagamentoSelecionado,
            cliente: _cliente,
            desconto: desconto,
            valorEntrega: widget.valorEntrega,
            entregaSelecionada: widget.entregaSelecionada,
            saldoUsado: saldoUsado,
          ),
        ),
      );
    } else if (metodoPagamentoSelecionado == 'Pix') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PagamentoPixScreen(
            valorTotal: total,
            carrinho: widget.carrinho,
            metodoPagamento: metodoPagamentoSelecionado,
            cliente: _cliente,
            desconto: desconto,
            valorEntrega: widget.valorEntrega,
            entregaSelecionada: widget.entregaSelecionada,
            saldoUsado: saldoUsado,
          ),
        ),
      );
    } else if (metodoPagamentoSelecionado == 'Link de Pagamento') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PagamentoLinkScreen(
            valorTotal: total,
            carrinho: widget.carrinho,
            metodoPagamento: metodoPagamentoSelecionado,
            cliente: _cliente,
            desconto: desconto,
            valorEntrega: widget.valorEntrega,
            entregaSelecionada: widget.entregaSelecionada,
            saldoUsado: saldoUsado,
          ),
        ),
      );
    } else if (metodoPagamentoSelecionado == 'Outros') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PagamentoOutrosScreen(
            valorTotal: total,
            carrinho: widget.carrinho,
            cliente: _cliente,
            desconto: desconto,
            valorEntrega: widget.valorEntrega,
            entregaSelecionada: widget.entregaSelecionada,
            saldoUsado: saldoUsado,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cliente = _cliente;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Pagamento'),
        actions: [
          IconButton(
            icon: Icon(Icons.person_add),
            onPressed: cadastrarNovoCliente,
            tooltip: 'Cadastrar Novo Cliente',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: CircleAvatar(child: Text(cliente.nome.isNotEmpty ? cliente.nome[0].toUpperCase() : '?')),
                title: Text(cliente.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  cliente.enderecoCompleto.isNotEmpty ? cliente.enderecoCompleto : cliente.celular,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: cliente.saldo > 0
                    ? Text(
                        'Saldo\nR\$ ${cliente.saldo.toStringAsFixed(2)}',
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 16),

            ItensCompraCard(carrinho: widget.carrinho),
            const SizedBox(height: 16),

            ResumoPagamentoCard(
              subtotal: _subtotal,
              desconto: desconto,
              valorEntrega: widget.valorEntrega,
              saldoUsado: saldoUsado,
              valorTotal: valorTotal,
            ),
            const SizedBox(height: 12),

            if (desconto == 0)
              OutlinedButton.icon(
                onPressed: aplicarDesconto,
                icon: Icon(Icons.percent),
                label: Text('Aplicar desconto'),
                style: OutlinedButton.styleFrom(minimumSize: Size(double.infinity, 44)),
              )
            else
              OutlinedButton.icon(
                onPressed: limparDesconto,
                icon: Icon(Icons.close),
                label: Text('Remover desconto'),
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(double.infinity, 44),
                  foregroundColor: Colors.red.shade700,
                  side: BorderSide(color: Colors.red.shade200),
                ),
              ),

            // ✅ Usar saldo do cliente — só aparece se o cliente tiver saldo
            if (cliente.saldo > 0) ...[
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Usar saldo do cliente',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _saldoController,
                              keyboardType: TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [MoedaInputFormatter()],
                              decoration: InputDecoration(
                                labelText: 'Valor do saldo a usar',
                                prefixText: 'R\$ ',
                              ),
                            ),
                          ),
                          SizedBox(width: 10),
                          ElevatedButton(
                            onPressed: () {
                              final valor = ClienteValidators.parseNumero(_saldoController.text) ?? 0.0;
                              aplicarSaldo(valor);
                            },
                            child: Text('Aplicar'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () => aplicarSaldo(cliente.saldo),
                              child: Text('Usar todo o saldo'),
                            ),
                          ),
                          if (saldoUsado > 0)
                            TextButton(
                              onPressed: limparSaldo,
                              style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                              child: Text('Remover'),
                            ),
                        ],
                      ),
                      if (saldoUsado > 0)
                        Text(
                          'Saldo aplicado: R\$ ${saldoUsado.toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w500),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),

            Text(
              'Selecione o método de pagamento',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            GridView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 0.9,
              ),
              itemCount: _opcoesPagamentoFiltradas.length,
              itemBuilder: (context, index) {
                final opcoesPagamento = _opcoesPagamentoFiltradas;
                String metodo = opcoesPagamento[index]['metodo']!;
                IconData icone = opcoesPagamento[index]['icone']!;
                final selecionado = metodoPagamentoSelecionado == metodo;

                return Material(
                  color: selecionado ? colorScheme.primary.withValues(alpha: 0.1) : colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => selecionarMetodoPagamento(metodo),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: selecionado ? colorScheme.primary : colorScheme.outlineVariant,
                          width: selecionado ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icone, size: 32, color: colorScheme.primary),
                          const SizedBox(height: 6),
                          Text(
                            metodo,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: selecionado ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
          ),
          child: ElevatedButton(
            onPressed: metodoPagamentoSelecionado.isEmpty ? null : navegarParaTelaPagamento,
            style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 52)),
            child: Text('Avançar — R\$ ${valorTotal.toStringAsFixed(2)}'),
          ),
        ),
      ),
    );
  }
}
