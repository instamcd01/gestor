import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/produto_provider.dart';

/// Lista sugestões de agrupamento de variante que já foram rejeitadas —
/// dá pra reconsiderar (volta pra "pendente", reaparece no chip normal do
/// produto) quando a rejeição foi engano.
class SugestoesVarianteRejeitadasScreen extends StatefulWidget {
  const SugestoesVarianteRejeitadasScreen({super.key});

  @override
  State<SugestoesVarianteRejeitadasScreen> createState() => _SugestoesVarianteRejeitadasScreenState();
}

class _SugestoesVarianteRejeitadasScreenState extends State<SugestoesVarianteRejeitadasScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProdutoProvider>().carregarSugestoesRejeitadas();
    });
  }

  @override
  Widget build(BuildContext context) {
    final produtoProvider = context.watch<ProdutoProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Sugestões de variante rejeitadas')),
      body: produtoProvider.sugestoesRejeitadas.isEmpty
          ? Center(
              child: Text(
                'Nenhuma sugestão rejeitada',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: produtoProvider.sugestoesRejeitadas.length,
              itemBuilder: (context, i) {
                final sugestao = produtoProvider.sugestoesRejeitadas[i];
                final produto = produtoProvider.getProdutoPorId(sugestao.produtoId);
                final candidato = produtoProvider.getProdutoPorId(sugestao.produtoCandidatoId);

                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(produto?.nome ?? sugestao.produtoId),
                    subtitle: Text('${sugestao.tipoVariacao} · ${candidato?.nome ?? sugestao.produtoCandidatoId}'),
                    trailing: TextButton(
                      onPressed: () => context.read<ProdutoProvider>().reconsiderarSugestaoVariante(sugestao.id),
                      child: const Text('Reconsiderar'),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
