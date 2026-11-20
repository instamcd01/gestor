import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/entrada.dart';
import '../models/pedido_compra.dart';
import '../providers/auth_provider.dart';
import '../providers/pedido_compra_provider.dart';
import '../repositories/entrada_repository.dart';
import '../repositories/pedido_compra_repository.dart';
import '../repositories/produto_fornecedor_repository.dart';
import '../utils/formatadores_input.dart';
import '../utils/produto_validators.dart';

class _ItemRecebimento {
  final ItemPedidoCompra origem;
  final TextEditingController quantidadeController;
  final TextEditingController custoController;

  _ItemRecebimento(this.origem)
      : quantidadeController = TextEditingController(
          text: (origem.quantidadeConfirmada ?? origem.quantidadePedida).toString(),
        ),
        custoController = TextEditingController(text: ProdutoValidators.formatarMoeda(origem.custoUnitario));

  void dispose() {
    quantidadeController.dispose();
    custoController.dispose();
  }
}

/// Passo final do ciclo de compra: registra fisicamente o que chegou como
/// uma `Entrada` de estoque de verdade (mesmo pipeline de "Importar Nota
/// Fiscal" — soma no estoque via trigger `aplicar_entrada_estoque`), já
/// pré-preenchida com a quantidade confirmada na conferência do espelho.
/// O usuário ainda pode ajustar pra bater com o que foi contado/veio na
/// nota fiscal real, que pode divergir de novo do que foi confirmado.
class ConfirmarRecebimentoScreen extends StatefulWidget {
  final PedidoCompra pedido;

  const ConfirmarRecebimentoScreen({super.key, required this.pedido});

  @override
  State<ConfirmarRecebimentoScreen> createState() => _ConfirmarRecebimentoScreenState();
}

class _ConfirmarRecebimentoScreenState extends State<ConfirmarRecebimentoScreen> {
  late final List<_ItemRecebimento> _itens;
  late final TextEditingController _nfeNumeroController;
  late final TextEditingController _nfeSerieController;
  /// Frete pago no pedido (marketplace) — opcional; dividido entre os itens
  /// proporcional ao valor de cada um e somado no custo da entrada.
  final _freteController = TextEditingController();
  bool _salvando = false;

  double get _frete => ProdutoValidators.parseNumero(_freteController.text) ?? 0;

  double _qtd(_ItemRecebimento i) => ProdutoValidators.parseNumero(i.quantidadeController.text) ?? 0;
  double _custoBase(_ItemRecebimento i) => ProdutoValidators.parseNumero(i.custoController.text) ?? 0;

  /// Custo unitário com a parte do frete daquele item (rateio pelo valor).
  double _custoComFrete(_ItemRecebimento i) {
    final base = _custoBase(i);
    final q = _qtd(i);
    if (_frete <= 0 || q <= 0) return base;
    final totalBase = _itens.fold<double>(0, (s, x) => s + _qtd(x) * _custoBase(x));
    if (totalBase <= 0) return base;
    final parteDoFrete = _frete * (q * base) / totalBase;
    return base + parteDoFrete / q;
  }

  @override
  void initState() {
    super.initState();
    _itens = widget.pedido.itens
        .where((i) => (i.quantidadeConfirmada ?? i.quantidadePedida) > 0)
        .map((i) => _ItemRecebimento(i))
        .toList();
    _nfeNumeroController = TextEditingController();
    _nfeSerieController = TextEditingController();
  }

  @override
  void dispose() {
    for (final item in _itens) {
      item.dispose();
    }
    _nfeNumeroController.dispose();
    _nfeSerieController.dispose();
    _freteController.dispose();
    super.dispose();
  }

  Future<void> _confirmar() async {
    setState(() => _salvando = true);
    try {
      final authProvider = context.read<AuthProvider>();
      final empresaId = authProvider.empresaId!;

      final itensEntrada = _itens.map((i) {
        final quantidade = _qtd(i);
        // Custo do estoque = preço + parte do frete (custo real do produto).
        final custo = double.parse(_custoComFrete(i).toStringAsFixed(4));
        return ItemEntrada(
          produtoId: i.origem.produtoSubstitutoId ?? i.origem.produtoId,
          eanNfe: '',
          descricaoNfe: i.origem.produtoSubstitutoNome ?? i.origem.produtoNome,
          quantidade: quantidade,
          custoUnitario: custo,
          valorTotal: quantidade * custo,
        );
      }).toList();

      final entrada = Entrada(
        fornecedor: widget.pedido.fornecedor,
        nfeNumero: _nfeNumeroController.text.trim().isEmpty ? null : _nfeNumeroController.text.trim(),
        nfeSerie: _nfeSerieController.text.trim().isEmpty ? null : _nfeSerieController.text.trim(),
        observacoes: 'Recebimento do pedido de compra #${widget.pedido.numeroSequencial ?? ''}'
            '${_frete > 0 ? ' · frete R\$${_frete.toStringAsFixed(2)} dividido no custo dos itens' : ''}',
        itens: itensEntrada,
      );

      await EntradaRepository().criar(
        entrada: entrada,
        empresaId: empresaId,
        fornecedorId: widget.pedido.fornecedor.id,
        pedidoCompraId: widget.pedido.id,
        criadoPor: authProvider.usuarioAtual?.id,
      );

      // Mesmo efeito colateral que "Importar Nota Fiscal" já tem (achado
      // real: recebimento manual gravava a entrada/estoque certinho, mas
      // nunca atualizava o custo do vínculo produto-fornecedor nem
      // "quantidade_recebida" no pedido — os dois caminhos de dar entrada
      // devem se comportar igual).
      final fornecedorId = widget.pedido.fornecedor.id;
      final pedidoRepo = PedidoCompraRepository();
      for (final item in _itens) {
        final quantidade = ProdutoValidators.parseNumero(item.quantidadeController.text) ?? 0;
        // O vínculo guarda o preço SEM frete: na próxima compra o frete pode
        // ser grátis, e é esse preço que a Sugestão de Compra usa.
        final custo = _custoBase(item);
        final produtoId = item.origem.produtoSubstitutoId ?? item.origem.produtoId;

        if (fornecedorId != null && custo > 0) {
          await ProdutoFornecedorRepository().vincularDeEntrada(
            produtoId: produtoId,
            fornecedorId: fornecedorId,
            empresaId: empresaId,
            custoUnitario: custo,
          );
        }
        if (item.origem.id != null) {
          await pedidoRepo.atualizarItem(item.origem.copyWith(quantidadeRecebida: quantidade.round()));
        }
      }

      if (mounted) {
        await context.read<PedidoCompraProvider>().marcarComoRecebido(widget.pedido.id!);
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao registrar recebimento: $e')));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirmar Recebimento')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Isso dá entrada real no estoque, igual a importar uma NF-e — ajuste as quantidades/custos se o que chegou for diferente do confirmado.',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nfeNumeroController,
                  decoration: const InputDecoration(labelText: 'Nº da NF-e (opcional)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _nfeSerieController,
                  decoration: const InputDecoration(labelText: 'Série (opcional)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _freteController,
            decoration: const InputDecoration(
              labelText: 'Frete do pedido (R\$, opcional)',
              helperText: 'Deixe em branco se o frete foi grátis. Ele é dividido entre os itens e entra no custo.',
              helperMaxLines: 2,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [MoedaInputFormatter()],
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 16),
          for (final item in _itens)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.origem.produtoSubstitutoNome ?? item.origem.produtoNome),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: item.quantidadeController,
                            decoration: const InputDecoration(labelText: 'Quantidade recebida', isDense: true),
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: item.custoController,
                            decoration: const InputDecoration(labelText: 'Custo unitário (R\$)', isDense: true),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            inputFormatters: [MoedaInputFormatter()],
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                    if (_frete > 0 && _qtd(item) > 0)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Com o frete: R\$${_custoComFrete(item).toStringAsFixed(2)} por unidade',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.primary),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _salvando ? null : _confirmar,
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
            child: _salvando
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Confirmar recebimento e dar entrada no estoque'),
          ),
        ],
      ),
    );
  }
}
