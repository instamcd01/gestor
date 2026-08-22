import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/campanha_ativacao.dart';
import '../providers/auth_provider.dart';
import '../repositories/campanha_ativacao_repository.dart';
import '../widgets/estado_erro_lista.dart';
import 'campanha_detalhe_screen.dart';
import 'campanhas_arquivadas_screen.dart';

/// Lista de campanhas de ativação (convite pra base externa/WhatsApp criar
/// cadastro no site em vez de importar os dados direto — ver
/// [[gestor_loja_lista_melhorias_ondas]] pro racional dessa decisão).
class CampanhasAtivacaoScreen extends StatefulWidget {
  const CampanhasAtivacaoScreen({super.key});

  @override
  State<CampanhasAtivacaoScreen> createState() => _CampanhasAtivacaoScreenState();
}

class _CampanhasAtivacaoScreenState extends State<CampanhasAtivacaoScreen> {
  late Future<List<CampanhaAtivacao>> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = CampanhaAtivacaoRepository().listar();
  }

  Future<void> _recarregar() async {
    setState(() => _futuro = CampanhaAtivacaoRepository().listar());
    await _futuro;
  }

  Future<void> _criarCampanha() async {
    final controladorNome = TextEditingController();
    final controladorDescricao = TextEditingController();

    final nome = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nova campanha'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controladorNome,
              decoration: const InputDecoration(labelText: 'Nome (ex: Ativação base WhatsApp — ago/2026)'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controladorDescricao,
              decoration: const InputDecoration(labelText: 'Descrição (opcional)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controladorNome.text.trim()),
            child: const Text('Criar'),
          ),
        ],
      ),
    );

    if (nome == null || nome.isEmpty || !mounted) return;

    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;

    final campanha = await CampanhaAtivacaoRepository().criar(
      empresaId: empresaId,
      nome: nome,
      descricao: controladorDescricao.text.trim().isEmpty ? null : controladorDescricao.text.trim(),
    );

    await _recarregar();
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CampanhaDetalheScreen(campanha: campanha)),
    );
  }

  Future<void> _arquivarCampanha(CampanhaAtivacao campanha) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Arquivar campanha'),
        content: Text(
          'Arquivar "${campanha.nome}"? Ela sai da lista principal, mas os contatos e o histórico '
          'continuam salvos — dá pra desarquivar depois em "Campanhas arquivadas".',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Arquivar')),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    try {
      await CampanhaAtivacaoRepository().arquivar(campanha.id);
      await _recarregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível arquivar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Campanhas de Ativação'),
        actions: [
          IconButton(
            icon: const Icon(Icons.archive_outlined),
            tooltip: 'Campanhas arquivadas',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CampanhasArquivadasScreen()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _criarCampanha,
        icon: const Icon(Icons.add),
        label: const Text('Nova campanha'),
      ),
      body: RefreshIndicator(
        onRefresh: _recarregar,
        child: FutureBuilder<List<CampanhaAtivacao>>(
          future: _futuro,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return EstadoErroLista(
                mensagem: 'Não foi possível carregar as campanhas: ${snapshot.error}',
                onTentarNovamente: _recarregar,
              );
            }
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            final itens = snapshot.data ?? [];
            if (itens.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'Nenhuma campanha ainda. Crie uma pra começar a acompanhar quem ativa e '
                        'compra depois do convite.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: itens.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final c = itens[i];
                return Card(
                  child: ListTile(
                    title: Text(c.nome),
                    subtitle: c.descricao != null ? Text(c.descricao!) : null,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(DateFormat('dd/MM/yyyy').format(c.criadoEm.toLocal())),
                        IconButton(
                          icon: const Icon(Icons.archive_outlined),
                          tooltip: 'Arquivar campanha',
                          onPressed: () => _arquivarCampanha(c),
                        ),
                      ],
                    ),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => CampanhaDetalheScreen(campanha: c)),
                      );
                      if (mounted) _recarregar();
                    },
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
