import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/kit_produto.dart';
import '../providers/auth_provider.dart';
import '../providers/kit_produto_provider.dart';
import '../utils/busca_utils.dart';
import 'kit_produto_form_screen.dart';

class KitsScreen extends StatefulWidget {
  const KitsScreen({super.key});

  @override
  State<KitsScreen> createState() => _KitsScreenState();
}

class _KitsScreenState extends State<KitsScreen> {
  final _searchController = TextEditingController();
  String _busca = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<KitProdutoProvider>().carregarKits();
    });
  }

  @override
  Widget build(BuildContext context) {
    final kitProvider = context.watch<KitProdutoProvider>();
    final isVendedor = context.watch<AuthProvider>().isVendedor;

    final kitsFiltrados = kitProvider.kits
        .where((k) => contemTodasPalavras(k.nome, _busca) || contemTodasPalavras(k.categoria, _busca))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Kits (${kitProvider.kits.length})'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () => kitProvider.carregarKits(),
          ),
        ],
      ),
      floatingActionButton: isVendedor
          ? null
          : FloatingActionButton.extended(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const KitProdutoFormScreen(),
              )),
              icon: const Icon(Icons.add),
              label: const Text('Novo kit'),
            ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar por nome ou categoria',
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
            child: kitProvider.carregando
                ? const Center(child: CircularProgressIndicator())
                : kitProvider.erro != null
                    ? Center(child: Text(kitProvider.erro!))
                    : kitsFiltrados.isEmpty
                        ? _EstadoVazio(temBusca: _busca.isNotEmpty)
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                            itemCount: kitsFiltrados.length,
                            itemBuilder: (ctx, i) {
                              final kit = kitsFiltrados[i];
                              return _KitCard(
                                kit: kit,
                                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => KitProdutoFormScreen(kitInicial: kit),
                                )),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _KitCard extends StatelessWidget {
  final KitProduto kit;
  final VoidCallback onTap;

  const _KitCard({required this.kit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final semEstoque = kit.estoqueDisponivel <= 0;

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
                  child: kit.imagemUrl.isNotEmpty
                      ? Image.network(
                          kit.imagemUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(Icons.card_giftcard, color: colorScheme.onSurfaceVariant),
                        )
                      : Icon(Icons.card_giftcard, color: colorScheme.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      kit.nome,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${kit.componentes.length} produto(s) no kit',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'R\$ ${kit.preco.toStringAsFixed(2)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700, color: colorScheme.primary),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: (semEstoque ? colorScheme.error : colorScheme.secondary).withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              semEstoque ? 'Sem estoque' : '${kit.estoqueDisponivel} kits disponíveis',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: semEstoque ? colorScheme.error : colorScheme.secondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
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
            Icon(temBusca ? Icons.search_off : Icons.card_giftcard, size: 56, color: colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              temBusca ? 'Nenhum kit encontrado' : 'Nenhum kit cadastrado ainda',
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              temBusca ? 'Tente buscar por outro termo.' : 'Toque em "Novo kit" pra começar.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
