import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/entrada_provider.dart';
import '../widgets/estado_erro_lista.dart';
import 'importar_nota_fiscal_screen.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _data = DateFormat('dd/MM/yyyy');

/// Notas fiscais de fornecedor — histórico do que já foi importado
/// (`entradas` + `itens_entrada`) com o ponto de entrada pra importar uma
/// nova junto na mesma tela (FAB), em vez de item de menu separado.
/// `ImportarNotaFiscalScreen` continua existindo à parte (não mexida
/// aqui) porque também é aberta a partir de "Receber Pedido de Compra"
/// (`pedido_compra_detalhe_screen.dart`), um fluxo focado que não deve
/// ganhar a lista de histórico junto.
class HistoricoEntradasScreen extends StatefulWidget {
  const HistoricoEntradasScreen({super.key});

  @override
  State<HistoricoEntradasScreen> createState() => _HistoricoEntradasScreenState();
}

class _HistoricoEntradasScreenState extends State<HistoricoEntradasScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<EntradaProvider>().carregar();
    });
  }

  Future<void> _importar() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ImportarNotaFiscalScreen()));
    if (mounted) Provider.of<EntradaProvider>(context, listen: false).carregar();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<EntradaProvider>();
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Notas Fiscais')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importar,
        icon: const Icon(Icons.upload_file_outlined),
        label: const Text('Importar'),
      ),
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
                              'Toque em "Importar" pra dar entrada na sua primeira NF-e.',
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
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
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
