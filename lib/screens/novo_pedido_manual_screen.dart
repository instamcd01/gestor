import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/fornecedor.dart';
import '../models/pedido_compra.dart';
import '../models/produto.dart';
import '../providers/auth_provider.dart';
import '../providers/fornecedor_provider.dart';
import '../providers/pedido_compra_provider.dart';
import '../providers/produto_provider.dart';
import '../utils/produto_validators.dart';
import '../widgets/busca_produto_sheet.dart';
import 'pedido_compra_detalhe_screen.dart';

class _ItemNovoPedido {
  final Produto produto;
  final TextEditingController quantidadeController = TextEditingController(text: '1');
  final TextEditingController custoController;

  _ItemNovoPedido(this.produto) : custoController = TextEditingController(text: ProdutoValidators.formatarMoeda(produto.custo));

  void dispose() {
    quantidadeController.dispose();
    custoController.dispose();
  }
}

/// Cria um pedido de compra do zero, escolhendo fornecedor + produtos —
/// antes só dava pra criar pedido vindo da Sugestão de Compra, e só pra
/// fornecedor/produto que a sugestão calculou (achado real: usuário queria
/// montar pedido pra fornecedor sem nenhuma sugestão pendente, ou só pedir
/// uma cotação exploratória sem comprometer quantidade nenhuma ainda —
/// nesse caso dá pra criar com ZERO itens e ir direto pra Conferência do
/// Espelho ler o PDF, que preenche os itens sozinho a partir da cotação).
class NovoPedidoManualScreen extends StatefulWidget {
  const NovoPedidoManualScreen({super.key});

  @override
  State<NovoPedidoManualScreen> createState() => _NovoPedidoManualScreenState();
}

class _NovoPedidoManualScreenState extends State<NovoPedidoManualScreen> {
  Fornecedor? _fornecedor;
  final List<_ItemNovoPedido> _itens = [];
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<FornecedorProvider>();
      if (provider.fornecedores.isEmpty) provider.carregar();
    });
  }

  @override
  void dispose() {
    for (final item in _itens) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _adicionarProduto() async {
    final produtos = context.read<ProdutoProvider>().produtos.where((p) => p.ativo && p.id != null).toList()
      ..sort((a, b) => a.nome.compareTo(b.nome));

    final produto = await showModalBottomSheet<Produto>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BuscaProdutoSheet(produtos: produtos),
    );
    if (produto == null) return;

    setState(() => _itens.add(_ItemNovoPedido(produto)));
  }

  void _removerItem(_ItemNovoPedido item) {
    setState(() {
      _itens.remove(item);
      item.dispose();
    });
  }

  Future<void> _salvar() async {
    final fornecedor = _fornecedor;
    if (fornecedor == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Escolha o fornecedor antes de criar o pedido.')));
      return;
    }

    setState(() => _salvando = true);
    try {
      final provider = context.read<PedidoCompraProvider>();
      final authProvider = context.read<AuthProvider>();

      final novo = await provider.criarPedido(
        pedido: PedidoCompra(fornecedor: fornecedor),
        itens: _itens
            .map((i) => ItemPedidoCompra(
                  produtoId: i.produto.id!,
                  produtoNome: i.produto.nome,
                  quantidadePedida: int.tryParse(i.quantidadeController.text) ?? 1,
                  custoUnitario: ProdutoValidators.parseNumero(i.custoController.text) ?? i.produto.custo,
                  origem: OrigemItemPedidoCompra.manual,
                ))
            .toList(),
        criadoPor: authProvider.usuarioAtual?.id,
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => PedidoCompraDetalheScreen(pedidoId: novo.id!)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao criar pedido: $e')));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fornecedores = context.watch<FornecedorProvider>().fornecedores;

    return Scaffold(
      appBar: AppBar(title: const Text('Novo pedido manual')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<Fornecedor>(
            initialValue: _fornecedor,
            decoration: const InputDecoration(labelText: 'Fornecedor', border: OutlineInputBorder()),
            items: [
              for (final f in fornecedores) DropdownMenuItem(value: f, child: Text(f.nome)),
            ],
            onChanged: (f) => setState(() => _fornecedor = f),
          ),
          if (_fornecedor != null && _fornecedor!.observacoes.trim().isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.sticky_note_2_outlined, size: 18, color: colorScheme.onSecondaryContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _fornecedor!.observacoes,
                      style: TextStyle(fontSize: 12, color: colorScheme.onSecondaryContainer),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
          Text('Itens (opcional)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Pode deixar sem nenhum item pra já ir direto pra Conferência do Espelho ler o PDF de uma cotação — os itens entram sozinhos a partir do que o fornecedor cotou.',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          for (final item in _itens)
            Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(item.produto.nome, style: const TextStyle(fontWeight: FontWeight.w600))),
                        IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => _removerItem(item)),
                      ],
                    ),
                    Row(
                      children: [
                        SizedBox(
                          width: 100,
                          child: TextField(
                            controller: item.quantidadeController,
                            decoration: const InputDecoration(labelText: 'Quantidade', isDense: true),
                            keyboardType: TextInputType.number,
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 130,
                          child: TextField(
                            controller: item.custoController,
                            decoration: const InputDecoration(labelText: 'Custo (R\$)', isDense: true),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          TextButton.icon(
            onPressed: _adicionarProduto,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Adicionar produto'),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _salvando ? null : _salvar,
            icon: _salvando
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: Text(_salvando ? 'Criando...' : 'Criar pedido'),
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
          ),
        ],
      ),
    );
  }
}
