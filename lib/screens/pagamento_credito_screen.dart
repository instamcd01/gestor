// pagamento_cartao_credito_screen.dart
import 'package:flutter/material.dart';
import 'package:gestor/models/cliente.dart';
import 'package:provider/provider.dart';
import '../config/supabase_config.dart';
import '../models/zona_entrega.dart';
import '../providers/auth_provider.dart';
import '../utils/agendamento_utils.dart';
import '../widgets/itens_compra_card.dart';
import '../widgets/resumo_pagamento_card.dart';
import 'conclusao_venda_screen.dart';

class PagamentoCartaoCreditoScreen extends StatefulWidget {
  final double valorTotal;
  final List<Map<String, dynamic>> carrinho;
  final String? idCliente;
  final String metodoPagamento;
  final Cliente cliente;
  final double desconto;
  final String? cupomId;
  final double valorEntrega;
  final String entregaSelecionada;
  final double saldoUsado;
  final ZonaEntrega? zonaEntrega;
  final JanelaHorarioAgendamento? agendamento;

  PagamentoCartaoCreditoScreen({
    required this.valorTotal,
    required this.carrinho,
    this.idCliente,
    required this.metodoPagamento,
    required this.cliente,
    required this.desconto,
    this.cupomId,
    required this.valorEntrega,
    required this.entregaSelecionada,
    required this.saldoUsado,
    this.zonaEntrega,
    this.agendamento,
  });

  @override
  State<PagamentoCartaoCreditoScreen> createState() => _PagamentoCartaoCreditoScreenState();
}

class _OpcaoParcela {
  final int parcelas;
  final double taxa;
  final double valorParcela;

  _OpcaoParcela({required this.parcelas, required this.taxa, required this.valorParcela});
}

class _PagamentoCartaoCreditoScreenState extends State<PagamentoCartaoCreditoScreen> {
  bool _carregandoConfig = true;
  Map<String, dynamic>? _taxasParcelamento;
  double _valorMinimoParcela = 5;
  int _parcelaEscolhida = 1;

  @override
  void initState() {
    super.initState();
    _carregarConfigParcelamento();
  }

  Future<void> _carregarConfigParcelamento() async {
    try {
      final empresaId = context.read<AuthProvider>().empresaId;
      if (empresaId == null) return;
      final data = await supabase
          .from('empresas')
          .select('taxas_parcelamento, valor_minimo_parcela')
          .eq('id', empresaId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _taxasParcelamento = (data?['taxas_parcelamento'] as Map<String, dynamic>?) ?? {};
          _valorMinimoParcela = (data?['valor_minimo_parcela'] as num?)?.toDouble() ?? 5;
        });
      }
    } catch (_) {
      // Sem config (ou erro de rede) — segue só com a opção à vista, mesmo
      // fallback gracioso que o resto do DistanciaService/parcelamento
      // usa: nunca trava a venda por causa de um dado auxiliar.
    } finally {
      if (mounted) setState(() => _carregandoConfig = false);
    }
  }

  /// Mesma fórmula usada no checkout do site (pagamento-form.tsx) — juro
  /// sobre o valor já líquido de desconto/saldo, nunca sobre o subtotal
  /// bruto. `widget.valorTotal` aqui já chega assim (calculado em
  /// PagamentoScreen).
  List<_OpcaoParcela> get _opcoesParcelamento {
    final taxas = _taxasParcelamento;
    if (taxas == null || taxas.isEmpty) return [];

    final opcoes = <_OpcaoParcela>[];
    for (final entry in taxas.entries) {
      final parcelas = int.tryParse(entry.key);
      final taxa = (entry.value as num?)?.toDouble();
      if (parcelas == null || taxa == null || parcelas < 1) continue;
      final valorComJuros = widget.valorTotal * (1 + taxa / 100);
      final valorParcela = valorComJuros / parcelas;
      // 1x sempre entra (preço à vista) — 2x em diante só se a parcela não
      // ficar pequena demais.
      if (parcelas > 1 && valorParcela < _valorMinimoParcela) continue;
      opcoes.add(_OpcaoParcela(parcelas: parcelas, taxa: taxa, valorParcela: valorParcela));
    }
    opcoes.sort((a, b) => a.parcelas.compareTo(b.parcelas));
    return opcoes;
  }

  double get _valorFinalComJuros {
    final opcao = _opcoesParcelamento.where((o) => o.parcelas == _parcelaEscolhida).toList();
    if (opcao.isEmpty) return widget.valorTotal;
    return opcao.first.valorParcela * opcao.first.parcelas;
  }

  double get _jurosCalculado => _valorFinalComJuros - widget.valorTotal;

  @override
  Widget build(BuildContext context) {
    final subtotal = ResumoPagamentoCard.calcularSubtotal(widget.carrinho);
    final colorScheme = Theme.of(context).colorScheme;
    final opcoes = _opcoesParcelamento;

    return Scaffold(
      appBar: AppBar(
        title: Text('Cartão de Crédito'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Icon(Icons.credit_card, size: 64, color: colorScheme.primary),
            const SizedBox(height: 8),
            Text(
              'Cliente: ${widget.cliente.nome}',
              textAlign: TextAlign.center,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            ItensCompraCard(carrinho: widget.carrinho),
            const SizedBox(height: 16),
            ResumoPagamentoCard(
              subtotal: subtotal,
              desconto: widget.desconto,
              valorEntrega: widget.valorEntrega,
              saldoUsado: widget.saldoUsado,
              valorTotal: _valorFinalComJuros,
            ),
            const SizedBox(height: 16),
            if (_carregandoConfig)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (opcoes.length > 1) ...[
              Text(
                'Parcelamento',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ...opcoes.map((opcao) {
                final selecionado = _parcelaEscolhida == opcao.parcelas;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => setState(() => _parcelaEscolhida = opcao.parcelas),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: selecionado ? colorScheme.primary.withValues(alpha: 0.1) : null,
                        border: Border.all(
                          color: selecionado ? colorScheme.primary : colorScheme.outlineVariant,
                          width: selecionado ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Radio<int>(
                                value: opcao.parcelas,
                                groupValue: _parcelaEscolhida,
                                onChanged: (v) => setState(() => _parcelaEscolhida = v!),
                              ),
                              Text('${opcao.parcelas}x de R\$ ${opcao.valorParcela.toStringAsFixed(2)}'),
                            ],
                          ),
                          Text(
                            opcao.taxa > 0 ? 'com juros' : 'sem juros',
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 8),
            ] else
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'Pagamento via cartão de crédito será processado no valor exato.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                ),
              ),
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
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ConclusaoVendaScreen(
                    valorTotal: _valorFinalComJuros,
                    carrinho: widget.carrinho,
                    idCliente: widget.idCliente,
                    metodoPagamento: widget.metodoPagamento,
                    cliente: widget.cliente,
                    desconto: widget.desconto,
                    cupomId: widget.cupomId,
                    valorEntrega: widget.valorEntrega,
                    entregaSelecionada: widget.entregaSelecionada,
                    saldoUsado: widget.saldoUsado,
                    zonaEntrega: widget.zonaEntrega,
                    agendamento: widget.agendamento,
                    parcelasCartao: _parcelaEscolhida > 1 ? _parcelaEscolhida : null,
                    jurosParcelamento: _parcelaEscolhida > 1 ? _jurosCalculado : null,
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 52)),
            child: Text('Concluir Pagamento'),
          ),
        ),
      ),
    );
  }
}
