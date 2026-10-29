import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/produto.dart';
import '../models/venda.dart';
import '../providers/produto_provider.dart';
import '../repositories/venda_repository.dart';
import '../widgets/aviso_banner.dart';
import '../widgets/busca_produto_sheet.dart';

/// Linha da edição: item que já estava no pedido (com [idItem]) ou produto
/// acrescentado agora (sem). Quantidade 0 = tirar do pedido.
class _LinhaEdicao {
  final String? idItem;
  final Produto produto;
  final double precoUnitario;
  final int quantidadeOriginal;
  int quantidade;

  _LinhaEdicao({
    required this.idItem,
    required this.produto,
    required this.precoUnitario,
    required this.quantidadeOriginal,
    required this.quantidade,
  });

  bool get nova => idItem == null;
  bool get retirada => quantidade == 0;
}

/// Trocar, tirar ou acrescentar item num pedido já recebido (ex: faltou o
/// produto) sem cancelar e refazer — o banco (`editar_itens_pedido`) acerta
/// estoque e total e mantém desconto, frete, PetCash e cupom do pedido.
/// Volta com a [Venda] atualizada, ou null se não salvou.
class EditarPedidoScreen extends StatefulWidget {
  final Venda venda;

  const EditarPedidoScreen({super.key, required this.venda});

  @override
  State<EditarPedidoScreen> createState() => _EditarPedidoScreenState();
}

class _EditarPedidoScreenState extends State<EditarPedidoScreen> {
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _motivoController = TextEditingController();
  late final List<_LinhaEdicao> _linhas;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _linhas = widget.venda.itens
        .map((i) => _LinhaEdicao(
              idItem: i.id,
              produto: i.produto,
              precoUnitario: i.precoUnitario,
              quantidadeOriginal: i.quantidade,
              quantidade: i.quantidade,
            ))
        .toList();
  }

  @override
  void dispose() {
    _motivoController.dispose();
    super.dispose();
  }

  bool get _pagoOnline => widget.venda.pagoOnline;

  double get _produtosAntes => _linhas.where((l) => !l.nova).fold(0, (s, l) => s + l.precoUnitario * l.quantidadeOriginal);
  double get _produtosDepois => _linhas.fold(0, (s, l) => s + l.precoUnitario * l.quantidade);
  double get _diferenca => _produtosDepois - _produtosAntes;
  double get _totalNovo => (widget.venda.valorTotal + _diferenca).clamp(0, double.infinity).toDouble();

  bool get _alterou => _linhas.any((l) => l.quantidade != l.quantidadeOriginal);
  bool get _ficaVazio => _linhas.every((l) => l.quantidade == 0);

  Future<void> _adicionarProduto() async {
    final produtos = context.read<ProdutoProvider>().produtos.where((p) => p.ativo && p.id != null).toList();
    final produto = await showModalBottomSheet<Produto>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BuscaProdutoSheet(produtos: produtos, permiteCadastrarNovo: false, mostrarPrecoVenda: true),
    );
    if (produto == null || !mounted) return;

    final existente = _linhas.where((l) => l.produto.id == produto.id).firstOrNull;
    setState(() {
      if (existente != null) {
        existente.quantidade++;
      } else {
        _linhas.add(_LinhaEdicao(
          idItem: null,
          produto: produto,
          precoUnitario: produto.precoVendaAtual,
          quantidadeOriginal: 0,
          quantidade: 1,
        ));
      }
    });
  }

  void _mudarQuantidade(_LinhaEdicao linha, int delta) {
    final nova = linha.quantidade + delta;
    if (nova < 0) return;
    // Pago online só diminui: acrescentar seria cobrança nova.
    if (_pagoOnline && nova > linha.quantidadeOriginal) return;
    setState(() {
      if (linha.nova && nova == 0) {
        _linhas.remove(linha);
      } else {
        linha.quantidade = nova;
      }
    });
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    try {
      final itens = _linhas
          .map((l) => l.nova
              ? {'produto_id': l.produto.id, 'quantidade': l.quantidade}
              : {'id': l.idItem, 'quantidade': l.quantidade})
          .toList();
      final motivo = _motivoController.text.trim();
      final atualizada = await VendaRepository().editarItens(
        widget.venda.idVenda!,
        itens,
        motivo: motivo.isEmpty ? null : motivo,
      );
      if (!mounted) return;
      Navigator.pop(context, atualizada);
    } catch (e) {
      if (!mounted) return;
      final texto = e.toString().replaceFirst(RegExp(r'^.*?message: '), '').replaceFirst(RegExp(r', code:.*$'), '');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível salvar: $texto')));
      setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final numero = widget.venda.numeroSequencial != null ? ' #${widget.venda.numeroSequencial}' : '';
    final diferenca = _diferenca;

    return Scaffold(
      appBar: AppBar(title: Text('Editar pedido$numero')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_pagoOnline)
            const Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: AvisoBanner(
                tipo: TipoAviso.info,
                icone: Icons.credit_card,
                texto: 'Pago online: dá pra tirar ou diminuir itens. A diferença volta pro cliente pelo Mercado Pago. '
                    'Pra acrescentar, faça um pedido novo.',
              ),
            ),
          ..._linhas.map(_linhaWidget),
          if (!_pagoOnline)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: OutlinedButton.icon(
                onPressed: _salvando ? null : _adicionarProduto,
                icon: const Icon(Icons.add),
                label: const Text('Adicionar produto'),
              ),
            ),
          const SizedBox(height: 8),
          TextField(
            controller: _motivoController,
            decoration: const InputDecoration(
              labelText: 'Motivo (opcional, só pra loja)',
              hintText: 'Ex: faltou o produto',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  _linhaTotal('Total antes', _moeda.format(widget.venda.valorTotal)),
                  if (diferenca != 0)
                    _linhaTotal('Diferença', '${diferenca > 0 ? '+' : '−'} ${_moeda.format(diferenca.abs())}'),
                  const Divider(),
                  _linhaTotal('Total novo', _moeda.format(_totalNovo), destaque: true),
                  if (widget.venda.petcashUsado > 0 || widget.venda.desconto > 0 || widget.venda.valorEntrega > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Desconto, frete e PetCash continuam como estavam.',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton(
            onPressed: _salvando || !_alterou || _ficaVazio ? null : _salvar,
            style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: _salvando
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_ficaVazio ? 'Pedido sem itens: cancele o pedido' : 'Salvar alterações'),
          ),
        ),
      ),
    );
  }

  Widget _linhaWidget(_LinhaEdicao linha) {
    final riscado = linha.retirada;
    final estilo = TextStyle(
      decoration: riscado ? TextDecoration.lineThrough : null,
      color: riscado ? Theme.of(context).disabledColor : null,
    );
    final podeAumentar = !_pagoOnline || linha.quantidade < linha.quantidadeOriginal;
    String? marca;
    if (linha.nova) {
      marca = 'novo';
    } else if (linha.retirada) {
      marca = 'retirado';
    } else if (linha.quantidade != linha.quantidadeOriginal) {
      marca = 'era ${linha.quantidadeOriginal}';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(linha.produto.nome, style: estilo),
                  const SizedBox(height: 2),
                  Text(
                    '${_moeda.format(linha.precoUnitario)} un.${marca != null ? ' · $marca' : ''}',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (riscado)
              TextButton(
                onPressed: () => setState(() => linha.quantidade = linha.quantidadeOriginal),
                child: const Text('Desfazer'),
              )
            else ...[
              IconButton(
                icon: Icon(linha.quantidade == 1 ? Icons.delete_outline : Icons.remove_circle_outline),
                tooltip: linha.quantidade == 1 ? 'Tirar do pedido' : 'Diminuir',
                onPressed: () => _mudarQuantidade(linha, -1),
              ),
              Text('${linha.quantidade}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                tooltip: 'Aumentar',
                onPressed: podeAumentar ? () => _mudarQuantidade(linha, 1) : null,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _linhaTotal(String rotulo, String valor, {bool destaque = false}) {
    final estilo = TextStyle(fontSize: destaque ? 17 : 14, fontWeight: destaque ? FontWeight.bold : FontWeight.normal);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(rotulo, style: estilo), Text(valor, style: estilo)],
      ),
    );
  }
}
