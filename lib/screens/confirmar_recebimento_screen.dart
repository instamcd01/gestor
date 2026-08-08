import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/entrada.dart';
import '../models/pedido_compra.dart';
import '../providers/auth_provider.dart';
import '../providers/pedido_compra_provider.dart';
import '../repositories/entrada_repository.dart';
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
  bool _salvando = false;

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
    super.dispose();
  }

  Future<void> _confirmar() async {
    setState(() => _salvando = true);
    try {
      final authProvider = context.read<AuthProvider>();
      final empresaId = authProvider.empresaId!;

      final itensEntrada = _itens.map((i) {
        final quantidade = ProdutoValidators.parseNumero(i.quantidadeController.text) ?? 0;
        final custo = ProdutoValidators.parseNumero(i.custoController.text) ?? 0;
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
        observacoes: 'Recebimento do pedido de compra #${widget.pedido.numeroSequencial ?? ''}',
        itens: itensEntrada,
      );

      await EntradaRepository().criar(
        entrada: entrada,
        empresaId: empresaId,
        fornecedorId: widget.pedido.fornecedor.id,
        pedidoCompraId: widget.pedido.id,
        criadoPor: authProvider.usuarioAtual?.id,
      );

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
                          ),
                        ),
                      ],
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
