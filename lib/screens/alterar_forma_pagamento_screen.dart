import 'package:flutter/material.dart';
import 'package:flutter_icons_null_safety/flutter_icons_null_safety.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/venda.dart';
import '../providers/auth_provider.dart';
import '../providers/historico_vendas_provider.dart';
import '../utils/cliente_validators.dart';
import '../utils/formatadores_input.dart';
import 'opcoes_pagamento_screen.dart' show metodosPagamentoDisponiveis;

class _OpcaoParcela {
  final int parcelas;
  final double taxa;
  final double valorParcela;

  _OpcaoParcela({required this.parcelas, required this.taxa, required this.valorParcela});
}

/// Troca a forma de pagamento (e parcelas) de uma venda de balcão já
/// registrada — casos reais: cliente combinou débito mas na entrega quer
/// pagar Pix, ou pediu crédito à vista e mudou de ideia pra parcelar. Não é
/// tela de nova venda: não mexe em carrinho/itens/estoque, só reflete o
/// pagamento de verdade recebido. Cálculo de juros e a trava pra pedido já
/// entregue (só dono) ficam no banco (`alterar_forma_pagamento_pedido`) —
/// aqui é só a prévia.
class AlterarFormaPagamentoScreen extends StatefulWidget {
  final Venda venda;

  const AlterarFormaPagamentoScreen({super.key, required this.venda});

  @override
  State<AlterarFormaPagamentoScreen> createState() => _AlterarFormaPagamentoScreenState();
}

class _AlterarFormaPagamentoScreenState extends State<AlterarFormaPagamentoScreen> {
  static const _iconesPorMetodo = <String, IconData>{
    'Dinheiro': Icons.money,
    'Cartão de Débito': FlutterIcons.credit_card_outline_mco,
    'Cartão de Crédito': FlutterIcons.credit_card_mdi,
    'Pix': Icons.pix,
    'Link de Pagamento': Icons.link,
    'Outros': Icons.more_horiz,
  };

  bool _carregandoConfig = true;
  bool _salvando = false;
  List<String> _metodosAtivos = List.from(metodosPagamentoDisponiveis);
  Map<String, dynamic> _taxasParcelamento = {};
  double _valorMinimoParcela = 5;

  late String _metodoSelecionado;
  late int _parcelaEscolhida;
  final _valorRecebidoController = TextEditingController();
  double _troco = 0;
  double _valorFaltando = 0;

  @override
  void initState() {
    super.initState();
    _metodoSelecionado = widget.venda.metodoPagamento;
    _parcelaEscolhida = widget.venda.parcelasCartao ?? 1;
    _carregarConfig();
  }

  @override
  void dispose() {
    _valorRecebidoController.dispose();
    super.dispose();
  }

  Future<void> _carregarConfig() async {
    try {
      final empresaId = context.read<AuthProvider>().empresaId;
      if (empresaId == null) return;
      final data = await supabase
          .from('empresas')
          .select('metodos_pagamento_ativos, taxas_parcelamento, valor_minimo_parcela')
          .eq('id', empresaId)
          .maybeSingle();
      if (!mounted) return;
      final metodos = (data?['metodos_pagamento_ativos'] as List?)?.map((m) => m.toString()).toList();
      setState(() {
        if (metodos != null && metodos.isNotEmpty) _metodosAtivos = metodos;
        _taxasParcelamento = (data?['taxas_parcelamento'] as Map<String, dynamic>?) ?? {};
        _valorMinimoParcela = (data?['valor_minimo_parcela'] as num?)?.toDouble() ?? 5;
      });
    } catch (_) {
      // Sem config (ou erro de rede) — segue só com 1x, mesmo critério
      // gracioso de pagamento_credito_screen.dart.
    } finally {
      if (mounted) setState(() => _carregandoConfig = false);
    }
  }

  List<Map<String, dynamic>> get _opcoesMetodo => _metodosAtivos
      .where((metodo) => _iconesPorMetodo.containsKey(metodo))
      .map((metodo) => {'metodo': metodo, 'icone': _iconesPorMetodo[metodo]!})
      .toList();

  /// Valor "de origem" da venda (produtos - desconto + entrega), sem
  /// qualquer juros que já estivesse embutido no valorTotal antigo — mesma
  /// base que o banco recalcula do zero em `alterar_forma_pagamento_pedido`.
  double get _valorBase {
    final v = widget.venda.subtotal - widget.venda.desconto + widget.venda.valorEntrega;
    return v < 0 ? 0.0 : v;
  }

  List<_OpcaoParcela> get _opcoesParcelamento {
    final opcoes = <_OpcaoParcela>[];
    for (final entry in _taxasParcelamento.entries) {
      final parcelas = int.tryParse(entry.key);
      final taxa = (entry.value as num?)?.toDouble();
      if (parcelas == null || taxa == null || parcelas < 1) continue;
      final valorComJuros = _valorBase * (1 + taxa / 100);
      final valorParcela = valorComJuros / parcelas;
      if (parcelas > 1 && valorParcela < _valorMinimoParcela) continue;
      opcoes.add(_OpcaoParcela(parcelas: parcelas, taxa: taxa, valorParcela: valorParcela));
    }
    opcoes.sort((a, b) => a.parcelas.compareTo(b.parcelas));
    return opcoes;
  }

  double get _valorFinal {
    if (_metodoSelecionado == 'Cartão de Crédito' && _parcelaEscolhida > 1) {
      final opcao = _opcoesParcelamento.where((o) => o.parcelas == _parcelaEscolhida).toList();
      if (opcao.isNotEmpty) return opcao.first.valorParcela * opcao.first.parcelas;
    }
    return _valorBase;
  }

  double get _jurosCalculado => _valorFinal - _valorBase;

  void _selecionarMetodo(String metodo) {
    setState(() {
      _metodoSelecionado = metodo;
      if (metodo != 'Cartão de Crédito') _parcelaEscolhida = 1;
    });
  }

  void _calcularTrocoOuFalta() {
    final valorRecebido = ClienteValidators.parseNumero(_valorRecebidoController.text) ?? 0.0;
    setState(() {
      if (valorRecebido >= _valorFinal) {
        _troco = valorRecebido - _valorFinal;
        _valorFaltando = 0.0;
      } else {
        _troco = 0.0;
        _valorFaltando = _valorFinal - valorRecebido;
      }
    });
  }

  Future<void> _confirmar() async {
    final ehDinheiro = _metodoSelecionado == 'Dinheiro';
    final valorRecebido = ClienteValidators.parseNumero(_valorRecebidoController.text) ?? 0.0;
    if (ehDinheiro && (_valorFaltando > 0 || valorRecebido <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o valor recebido em dinheiro.')),
      );
      return;
    }

    setState(() => _salvando = true);
    try {
      await context.read<HistoricoVendasProvider>().alterarFormaPagamento(
            widget.venda.idVenda!,
            _metodoSelecionado,
            parcelas: _metodoSelecionado == 'Cartão de Crédito' && _parcelaEscolhida > 1 ? _parcelaEscolhida : null,
            valorPago: ehDinheiro ? valorRecebido : null,
            troco: ehDinheiro ? _troco : null,
          );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final mensagem = e is PostgrestException ? e.message : e.toString();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagem)));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Alterar Forma de Pagamento')),
      body: _carregandoConfig
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Cliente: ${widget.venda.cliente.nome}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Combinado antes: ${widget.venda.metodoPagamento}'
                    '${widget.venda.parcelasCartao != null ? ' (${widget.venda.parcelasCartao}x)' : ''}',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                      childAspectRatio: 0.9,
                    ),
                    itemCount: _opcoesMetodo.length,
                    itemBuilder: (context, index) {
                      final metodo = _opcoesMetodo[index]['metodo'] as String;
                      final icone = _opcoesMetodo[index]['icone'] as IconData;
                      final selecionado = _metodoSelecionado == metodo;

                      return Material(
                        color: selecionado ? colorScheme.primary.withValues(alpha: 0.1) : colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _selecionarMetodo(metodo),
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
                  if (_metodoSelecionado == 'Cartão de Crédito' && _opcoesParcelamento.length > 1) ...[
                    const SizedBox(height: 20),
                    Text(
                      'Parcelamento',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    ..._opcoesParcelamento.map((opcao) {
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
                  ],
                  if (_metodoSelecionado == 'Dinheiro') ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _valorRecebidoController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [MoedaInputFormatter()],
                            decoration: const InputDecoration(labelText: 'Valor Recebido', prefixText: 'R\$ '),
                            onChanged: (_) => _calcularTrocoOuFalta(),
                          ),
                        ),
                        const SizedBox(width: 10),
                        OutlinedButton(
                          onPressed: () {
                            _valorRecebidoController.text = ClienteValidators.formatarMoeda(_valorFinal);
                            _calcularTrocoOuFalta();
                          },
                          child: const Text('Valor exato'),
                        ),
                      ],
                    ),
                    if (_troco > 0 || _valorFaltando > 0) ...[
                      const SizedBox(height: 12),
                      Text(
                        _troco > 0
                            ? 'Troco: R\$ ${_troco.toStringAsFixed(2)}'
                            : 'Falta: R\$ ${_valorFaltando.toStringAsFixed(2)}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: _troco > 0 ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ],
                  const SizedBox(height: 20),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          if (_jurosCalculado > 0)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Juros do parcelamento', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                                  Text('+R\$ ${_jurosCalculado.toStringAsFixed(2)}'),
                                ],
                              ),
                            ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Novo total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              Text(
                                'R\$ ${_valorFinal.toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                            ],
                          ),
                        ],
                      ),
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
            onPressed: _salvando ? null : _confirmar,
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
            child: _salvando
                ? const SizedBox(
                    width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Salvar'),
          ),
        ),
      ),
    );
  }
}
