import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/campanha_ativacao.dart';
import '../repositories/campanha_ativacao_repository.dart';
import '../widgets/estado_erro_lista.dart';
import 'campanha_detalhe_screen.dart';

/// Lista campanhas arquivadas (soft-delete, `deleted_at` preenchido) com
/// opção de desarquivar — mesmo padrão de [[ProdutosExcluidosScreen]].
class CampanhasArquivadasScreen extends StatefulWidget {
  const CampanhasArquivadasScreen({super.key});

  @override
  State<CampanhasArquivadasScreen> createState() => _CampanhasArquivadasScreenState();
}

class _CampanhasArquivadasScreenState extends State<CampanhasArquivadasScreen> {
  late Future<List<CampanhaAtivacao>> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = CampanhaAtivacaoRepository().listarArquivadas();
  }

  Future<void> _recarregar() async {
    setState(() => _futuro = CampanhaAtivacaoRepository().listarArquivadas());
    await _futuro;
  }

  Future<void> _desarquivar(CampanhaAtivacao campanha) async {
    try {
      await CampanhaAtivacaoRepository().desarquivar(campanha.id);
      await _recarregar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${campanha.nome}" desarquivada.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível desarquivar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Campanhas arquivadas')),
      body: RefreshIndicator(
        onRefresh: _recarregar,
        child: FutureBuilder<List<CampanhaAtivacao>>(
          future: _futuro,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return EstadoErroLista(
                mensagem: 'Não foi possível carregar as campanhas arquivadas: ${snapshot.error}',
                onTentarNovamente: _recarregar,
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final itens = snapshot.data ?? [];
            if (itens.isEmpty) {
              return ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.archive_outlined, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
                          const SizedBox(height: 16),
                          const Text('Nenhuma campanha arquivada.'),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: itens.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final c = itens[i];
                return ListTile(
                  title: Text(c.nome),
                  subtitle: Text('Arquivada em ${DateFormat('dd/MM/yyyy').format(c.arquivadaEm!.toLocal())}'),
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => CampanhaDetalheScreen(campanha: c)),
                    );
                    if (mounted) _recarregar();
                  },
                  trailing: TextButton.icon(
                    onPressed: () => _desarquivar(c),
                    icon: const Icon(Icons.unarchive_outlined, size: 18),
                    label: const Text('Desarquivar'),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
