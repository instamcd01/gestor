import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/produto_provider.dart';
import '../widgets/importar_produtos_planilha.dart';
import '../models/produto.dart';
import 'cadastro_produto_screen.dart';
import 'detalhes_produto_screen.dart';
import 'editar_produto_screen.dart';
import 'produtos_excluidos_screen.dart';

class ProdutosScreen extends StatefulWidget {
  const ProdutosScreen({super.key});

  @override
  State<ProdutosScreen> createState() => _ProdutosScreenState();
}

class _ProdutosScreenState extends State<ProdutosScreen> {
  final _searchController = TextEditingController();
  String _busca = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProdutoProvider>().carregarProdutos();
    });
  }

  Future<void> _importarProdutos() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => ImportarProdutosScreen(),
    ));
    if (mounted) context.read<ProdutoProvider>().carregarProdutos();
  }

  @override
  Widget build(BuildContext context) {
    final produtoProvider = context.watch<ProdutoProvider>();
    // Vendedor só consulta o catálogo (ver detalhesProdutoScreen) — criar,
    // importar/exportar e restaurar produto excluído é gestão de catálogo,
    // não venda.
    final isVendedor = context.watch<AuthProvider>().isVendedor;

    final produtosFiltrados = produtoProvider.produtos.where((p) {
      final termo = _busca.toLowerCase();
      return p.nome.toLowerCase().contains(termo) ||
          p.codigoBarras.toLowerCase().contains(termo) ||
          p.categoria.toLowerCase().contains(termo);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Produtos (${produtoProvider.produtos.length})'),
        actions: [
          if (!isVendedor) ...[
            IconButton(
              tooltip: 'Produtos excluídos',
              icon: const Icon(Icons.restore_from_trash_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const ProdutosExcluidosScreen(),
              )),
            ),
            IconButton(
              tooltip: 'Importar planilha',
              icon: const Icon(Icons.upload_file_outlined),
              onPressed: _importarProdutos,
            ),
          ],
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () => produtoProvider.carregarProdutos(),
          ),
        ],
      ),
      floatingActionButton: isVendedor
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (ctx) => CadastroProdutoScreen(),
                ));
              },
              icon: const Icon(Icons.add),
              label: const Text('Novo produto'),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar por nome, categoria ou código de barras',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _busca.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _busca = '');
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _busca = v),
            ),
          ),
          Expanded(
            child: produtoProvider.carregando
                ? const Center(child: CircularProgressIndicator())
                : produtoProvider.erro != null
                    ? _EstadoErro(
                        mensagem: produtoProvider.erro!,
                        onTentarNovamente: () => produtoProvider.carregarProdutos(),
                      )
                    : produtosFiltrados.isEmpty
                        ? _EstadoVazio(temBusca: _busca.isNotEmpty)
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                            itemCount: produtosFiltrados.length,
                            itemBuilder: (ctx, i) {
                              final produto = produtosFiltrados[i];
                              return _ProdutoCard(
                                produto: produto,
                                isVendedor: isVendedor,
                                onTap: () {
                                  Navigator.of(context).push(MaterialPageRoute(
                                    builder: (context) => isVendedor
                                        ? DetalhesProdutoScreen(produto: produto)
                                        : EditarProdutoScreen(produto: produto),
                                  ));
                                },
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _ProdutoCard extends StatelessWidget {
  final Produto produto;
  final VoidCallback onTap;
  final bool isVendedor;

  const _ProdutoCard({required this.produto, required this.onTap, required this.isVendedor});

  Future<void> _confirmarRevisado(BuildContext context) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Marcar como revisado'),
        content: Text(
          'O custo de "${produto.nome}" mudou (agora R\$ ${produto.custo.toStringAsFixed(2)}). '
          'Marcar como revisado indica que você já conferiu o preço de venda (R\$ ${produto.preco.toStringAsFixed(2)}) e decidiu mantê-lo assim.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Marcar como revisado')),
        ],
      ),
    );
    if (confirmou == true && context.mounted) {
      await context.read<ProdutoProvider>().marcarPrecoRevisado(produto.id!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final estoqueBaixo = produto.estoqueAtual <= produto.estoqueMinimo;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: 64,
                  height: 64,
                  color: colorScheme.surfaceContainerHighest,
                  child: produto.imagemUrl.isNotEmpty
                      ? Image.network(
                          produto.imagemUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.inventory_2_outlined,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        )
                      : Icon(Icons.inventory_2_outlined, color: colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      produto.nome,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      produto.categoria.isNotEmpty ? produto.categoria : 'Sem categoria',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // Flexible nos dois — sem isso, numa coluna estreita
                        // (ex: barra lateral sempre visível tirando espaço)
                        // essa linha estourava (RenderFlex overflow).
                        Flexible(
                          child: Text(
                            'R\$ ${produto.preco.toStringAsFixed(2)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.primary,
                                ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: _BadgeEstoque(
                            quantidade: produto.estoqueAtual,
                            baixo: estoqueBaixo,
                          ),
                        ),
                      ],
                    ),
                    if (produto.revisarPreco && !isVendedor) ...[
                      const SizedBox(height: 8),
                      ActionChip(
                        avatar: const Icon(Icons.price_change_outlined, size: 16, color: Colors.orange),
                        label: const Text('Custo mudou — revisar preço', style: TextStyle(fontSize: 12)),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: Color.alphaBlend(Colors.orange.withValues(alpha: 0.15), colorScheme.surface),
                        onPressed: () => _confirmarRevisado(context),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _BadgeEstoque extends StatelessWidget {
  final int quantidade;
  final bool baixo;

  const _BadgeEstoque({required this.quantidade, required this.baixo});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cor = baixo ? colorScheme.error : colorScheme.secondary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            baixo ? Icons.warning_amber_rounded : Icons.inventory_outlined,
            size: 13,
            color: cor,
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '$quantidade em estoque',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cor),
            ),
          ),
        ],
      ),
    );
  }
}

class _EstadoVazio extends StatelessWidget {
  final bool temBusca;
  const _EstadoVazio({required this.temBusca});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              temBusca ? Icons.search_off : Icons.inventory_2_outlined,
              size: 56,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              temBusca ? 'Nenhum produto encontrado' : 'Nenhum produto cadastrado ainda',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              temBusca
                  ? 'Tente buscar por outro termo.'
                  : 'Toque em "Novo produto" pra começar seu catálogo.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EstadoErro extends StatelessWidget {
  final String mensagem;
  final VoidCallback onTentarNovamente;

  const _EstadoErro({required this.mensagem, required this.onTentarNovamente});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: colorScheme.error),
            const SizedBox(height: 16),
            Text(
              'Não foi possível carregar os produtos',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: onTentarNovamente,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
