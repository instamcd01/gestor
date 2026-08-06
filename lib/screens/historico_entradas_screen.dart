import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/entrada_provider.dart';
import '../widgets/estado_erro_lista.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _data = DateFormat('dd/MM/yyyy');

/// Histórico das notas fiscais de fornecedor já importadas (`entradas` +
/// `itens_entrada`) — até 2026-08-06 esse provider já existia inteiro
/// (listar, erro, carregando) mas nada na UI chamava `carregar()` nem lia
/// `entradas`, então não havia nenhuma forma de ver o que já tinha sido
/// importado depois da tela de importação fechar.
class HistoricoEntradasScreen extends StatefulWidget {
  const HistoricoEntradasScreen({super.key});

  @override
  State<HistoricoEntradasScreen> createState() => _HistoricoEntradasScreenState();
}

class _HistoricoEntradasScreenState extends State<HistoricoEntradasScreen> {
  @override
  void initState() {
    super.initState();
    Provider.of<EntradaProvider>(context, listen: false).carregar();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EntradaProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Notas Fiscais Importadas')),
      body: provider.carregando
          ? const Center(child: CircularProgressIndicator())
          : provider.erro != null
              ? EstadoErroLista(mensagem: provider.erro!, onTentarNovamente: provider.carregar)
              : provider.entradas.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.upload_file_outlined, size: 56, color: colorScheme.onSurfaceVariant),
                            const SizedBox(height: 16),
                            Text('Nenhuma nota importada ainda.', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 4),
                            Text(
                              'Toda NF-e importada em "Importar Nota Fiscal" aparece aqui.',
                              style: TextStyle(color: colorScheme.onSurfaceVariant),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: provider.carregar,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: provider.entradas.length,
                        itemBuilder: (context, index) {
                          final entrada = provider.entradas[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: colorScheme.primaryContainer,
                                child: Icon(Icons.receipt_long_outlined, color: colorScheme.onPrimaryContainer),
                              ),
                              title: Text(entrada.fornecedor?.nome ?? 'Fornecedor não informado'),
                              subtitle: Text(
                                [
                                  if (entrada.nfeNumero != null) 'NF ${entrada.nfeNumero}',
                                  _data.format(entrada.dataEntrada),
                                ].join(' • '),
                              ),
                              trailing: Text(
                                _moeda.format(entrada.valorTotalNota ?? entrada.valorTotalProdutos ?? 0),
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}
