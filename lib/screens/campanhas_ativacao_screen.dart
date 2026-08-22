import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/campanha_ativacao.dart';
import '../providers/auth_provider.dart';
import '../repositories/campanha_ativacao_repository.dart';
import 'campanha_detalhe_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Campanhas de Ativação')),
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
                    trailing: Text(DateFormat('dd/MM/yyyy').format(c.criadoEm.toLocal())),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => CampanhaDetalheScreen(campanha: c)),
                    ),
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
