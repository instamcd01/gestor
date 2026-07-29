import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/produto_provider.dart';

/// Lista produtos excluídos (soft-delete, `deleted_at` preenchido) com
/// opção de restaurar — sem isso não havia como desfazer uma exclusão de
/// produto pela interface, só via acesso direto ao banco.
class ProdutosExcluidosScreen extends StatefulWidget {
  const ProdutosExcluidosScreen({super.key});

  @override
  State<ProdutosExcluidosScreen> createState() => _ProdutosExcluidosScreenState();
}

class _ProdutosExcluidosScreenState extends State<ProdutosExcluidosScreen> {
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await context.read<ProdutoProvider>().carregarExcluidos();
      if (mounted) setState(() => _carregando = false);
    });
  }

  Future<void> _restaurar(String id, String nome) async {
    try {
      await context.read<ProdutoProvider>().restaurarProduto(id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('"$nome" restaurado.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível restaurar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final excluidos = context.watch<ProdutoProvider>().excluidos;

    return Scaffold(
      appBar: AppBar(title: const Text('Produtos excluídos')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : excluidos.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.delete_outline, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(height: 16),
                        const Text('Nenhum produto excluído.'),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: excluidos.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final produto = excluidos[i];
                    return ListTile(
                      title: Text(produto.nome),
                      subtitle: Text(produto.codigoBarras.isEmpty ? 'Sem código de barras' : 'EAN: ${produto.codigoBarras}'),
                      trailing: TextButton.icon(
                        onPressed: () => _restaurar(produto.id!, produto.nome),
                        icon: const Icon(Icons.restore_from_trash_outlined, size: 18),
                        label: const Text('Restaurar'),
                      ),
                    );
                  },
                ),
    );
  }
}
