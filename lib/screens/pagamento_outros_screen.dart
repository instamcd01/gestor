import 'package:flutter/material.dart';
import '../models/cliente.dart';
import '../models/zona_entrega.dart';
import '../theme/app_theme.dart';
import '../utils/agendamento_utils.dart';
import '../utils/cliente_validators.dart';
import '../utils/formatadores_input.dart';
import '../widgets/itens_compra_card.dart';
import '../widgets/resumo_pagamento_card.dart';
import 'conclusao_venda_screen.dart';

class PagamentoOutrosScreen extends StatefulWidget {
  final double valorTotal;
  final List<Map<String, dynamic>> carrinho;
  final Cliente cliente;
  final double desconto;
  final String? cupomId;
  final double valorEntrega;
  final String entregaSelecionada;
  final double saldoUsado;
  final ZonaEntrega? zonaEntrega;
  final JanelaHorarioAgendamento? agendamento;

  PagamentoOutrosScreen({
    required this.valorTotal,
    required this.carrinho,
    required this.cliente,
    required this.desconto,
    this.cupomId,
    required this.valorEntrega,
    required this.entregaSelecionada,
    this.saldoUsado = 0.0,
    this.zonaEntrega,
    this.agendamento,
  });

  @override
  _PagamentoOutrosScreenState createState() => _PagamentoOutrosScreenState();
}

class _PagamentoOutrosScreenState extends State<PagamentoOutrosScreen> {
  Map<String, double> pagamentos = {}; // chave: método, valor: quanto pagar
  double totalPago = 0.0;

  final TextEditingController _valorController = TextEditingController();
  String metodoSelecionado = 'Dinheiro';

  final List<String> metodosDisponiveis = [
    'Dinheiro',
    'Cartão de Débito',
    'Cartão de Crédito',
    'Pix',
    'Link de Pagamento',
    'Saldo Cliente',
  ];

  /// Função auxiliar para arredondar valores monetários
  double arredondar(double valor) {
    return double.parse(valor.toStringAsFixed(2));
  }

  double get valorRestante {
    double restante = arredondar(widget.valorTotal - totalPago);
    return restante < 0 ? 0.0 : restante;
  }

  /// Quanto do saldo do cliente ainda pode ser usado — o total do cliente
  /// menos o que já foi aplicado na tela anterior (widget.saldoUsado) e
  /// menos o que já foi lançado como "Saldo Cliente" nesta divisão.
  double get saldoClienteDisponivel {
    final jaUsado = widget.saldoUsado + (pagamentos['Saldo Cliente'] ?? 0.0);
    final disponivel = arredondar(widget.cliente.saldo - jaUsado);
    return disponivel < 0 ? 0.0 : disponivel;
  }

  double get _limiteParaMetodoSelecionado {
    if (metodoSelecionado == 'Saldo Cliente') {
      return saldoClienteDisponivel < valorRestante ? saldoClienteDisponivel : valorRestante;
    }
    return valorRestante;
  }

  void preencherValorRestante() {
    _valorController.text = ClienteValidators.formatarMoeda(_limiteParaMetodoSelecionado);
  }

  void adicionarPagamento() {
    final valor = ClienteValidators.parseNumero(_valorController.text) ?? 0.0;
    if (valor <= 0) return;
    if (metodoSelecionado == 'Saldo Cliente' && valor > saldoClienteDisponivel) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('O cliente só tem R\$ ${saldoClienteDisponivel.toStringAsFixed(2)} de saldo.')),
      );
      return;
    }
    if (valor > valorRestante) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Valor excede o restante a pagar.')),
      );
      return;
    }
    setState(() {
      pagamentos[metodoSelecionado] =
          arredondar((pagamentos[metodoSelecionado] ?? 0.0) + valor);
      totalPago = arredondar(totalPago + valor);
      _valorController.clear();
    });
  }

  void removerPagamento(String metodo) {
    setState(() {
      totalPago = arredondar(totalPago - pagamentos[metodo]!);
      pagamentos.remove(metodo);
    });
  }

  void finalizarPagamento() {
    if (arredondar(totalPago) < arredondar(widget.valorTotal)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Pagamento incompleto.')),
      );
      return;
    }

    // Soma o saldo já aplicado na tela anterior com o que foi lançado aqui
    // como "Saldo Cliente" — os dois são débitos reais no saldo do cliente
    // e precisam ser refletidos juntos em Venda.saldoUsado, senão a parte
    // lançada aqui nunca é debitada de fato no banco.
    final saldoUsadoTotal = arredondar(widget.saldoUsado + (pagamentos['Saldo Cliente'] ?? 0.0));

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ConclusaoVendaScreen(
          valorTotal: arredondar(widget.valorTotal),
          carrinho: widget.carrinho,
          cliente: widget.cliente,
          metodoPagamento: 'Outros', // indicando pagamento dividido
          desconto: widget.desconto,
          cupomId: widget.cupomId,
          valorEntrega: widget.valorEntrega,
          entregaSelecionada: widget.entregaSelecionada,
          saldoUsado: saldoUsadoTotal,
          pagamentosDetalhados: pagamentos,
          zonaEntrega: widget.zonaEntrega,
          agendamento: widget.agendamento,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _valorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final subtotal = ResumoPagamentoCard.calcularSubtotal(widget.carrinho);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text('Pagamento Dividido')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16.0),
              children: [
                Text('Cliente: ${widget.cliente.nome}', style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                ItensCompraCard(carrinho: widget.carrinho),
                const SizedBox(height: 12),
                ResumoPagamentoCard(
                  subtotal: subtotal,
                  desconto: widget.desconto,
                  valorEntrega: widget.valorEntrega,
                  saldoUsado: widget.saldoUsado,
                  valorTotal: widget.valorTotal,
                ),
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  color: valorRestante == 0
                      ? Colors.green.withValues(alpha: 0.1)
                      : colorScheme.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      valorRestante == 0
                          ? 'Valor total coberto ✓'
                          : 'Valor restante a pagar: R\$ ${valorRestante.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: valorRestante == 0
                            ? AppTheme.tomAdaptavel(Colors.green, Theme.of(context).brightness)
                            : colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                DropdownButtonFormField<String>(
                  value: metodoSelecionado,
                  items: metodosDisponiveis
                      .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                      .toList(),
                  onChanged: (valor) => setState(() => metodoSelecionado = valor!),
                  decoration: const InputDecoration(labelText: 'Selecionar método'),
                ),
                if (metodoSelecionado == 'Saldo Cliente')
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      'Saldo disponível do cliente: R\$ ${saldoClienteDisponivel.toStringAsFixed(2)}',
                      style: TextStyle(
                        color: AppTheme.tomAdaptavel(
                          saldoClienteDisponivel > 0 ? Colors.green : Colors.red,
                          Theme.of(context).brightness,
                        ),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _valorController,
                        keyboardType: TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [MoedaInputFormatter()],
                        decoration: const InputDecoration(
                          labelText: 'Valor a pagar',
                          prefixText: 'R\$ ',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(onPressed: adicionarPagamento, child: const Text('Adicionar')),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _limiteParaMetodoSelecionado > 0 ? preencherValorRestante : null,
                    child: Text(
                      metodoSelecionado == 'Saldo Cliente' ? 'Usar valor máximo' : 'Usar valor restante',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pagamentos adicionados',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                if (pagamentos.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'Nenhum pagamento adicionado ainda.',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  )
                else
                  Card(
                    margin: EdgeInsets.zero,
                    child: Column(
                      children: pagamentos.entries.map((e) {
                        return ListTile(
                          dense: true,
                          title: Text(e.key),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'R\$ ${e.value.toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => removerPagamento(e.key),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                border: Border(top: BorderSide(color: colorScheme.outlineVariant)),
              ),
              child: ElevatedButton(
                onPressed: valorRestante == 0 ? finalizarPagamento : null,
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                child: const Text('Finalizar Pagamento'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
