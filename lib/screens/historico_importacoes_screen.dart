import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/importacao_planilha.dart';
import '../repositories/importacao_planilha_repository.dart';

class HistoricoImportacoesScreen extends StatefulWidget {
  /// 'produtos' | 'clientes' | null (mostra os dois tipos misturados).
  final String? tipo;
  const HistoricoImportacoesScreen({super.key, this.tipo});

  @override
  State<HistoricoImportacoesScreen> createState() => _HistoricoImportacoesScreenState();
}

class _HistoricoImportacoesScreenState extends State<HistoricoImportacoesScreen> {
  late Future<List<ImportacaoPlanilha>> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = ImportacaoPlanilhaRepository().listar(tipo: widget.tipo);
  }

  Future<void> _recarregar() async {
    setState(() => _futuro = ImportacaoPlanilhaRepository().listar(tipo: widget.tipo));
    await _futuro;
  }

  @override
  Widget build(BuildContext context) {
    final sufixo = widget.tipo == 'produtos'
        ? ' — Produtos'
        : widget.tipo == 'clientes'
            ? ' — Clientes'
            : '';
    return Scaffold(
      appBar: AppBar(title: Text('Histórico de Importações$sufixo')),
      body: RefreshIndicator(
        onRefresh: _recarregar,
        child: FutureBuilder<List<ImportacaoPlanilha>>(
          future: _futuro,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(child: Text('Erro ao carregar: ${snapshot.error}'));
            }
            final itens = snapshot.data ?? [];
            if (itens.isEmpty) {
              return ListView(
                children: const [
                  Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('Nenhuma importação registrada ainda.')),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: itens.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _CartaoImportacao(item: itens[i]),
            );
          },
        ),
      ),
    );
  }
}

class _CartaoImportacao extends StatelessWidget {
  final ImportacaoPlanilha item;
  const _CartaoImportacao({required this.item});

  @override
  Widget build(BuildContext context) {
    final sucesso = item.status == 'sucesso';
    final dataFormatada = DateFormat('dd/MM/yyyy HH:mm').format(item.criadoEm.toLocal());

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  sucesso ? Icons.check_circle : Icons.error,
                  color: sucesso ? Colors.green : Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.nomeArquivo ?? (item.tipo == 'produtos' ? 'Planilha de produtos' : 'Planilha de clientes'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(dataFormatada, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            if (sucesso)
              Text(
                '${item.totalLinhas} linhas lidas — ${item.novos} novo${item.novos == 1 ? '' : 's'}, '
                '${item.atualizados} atualizado${item.atualizados == 1 ? '' : 's'}'
                '${item.linhasIgnoradas > 0 ? ', ${item.linhasIgnoradas} ignorada${item.linhasIgnoradas == 1 ? '' : 's'}' : ''}.',
              )
            else
              Text(
                item.mensagemErro ?? 'Falhou sem detalhe do motivo.',
                style: const TextStyle(color: Colors.red),
              ),
          ],
        ),
      ),
    );
  }
}
