import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../repositories/nfe_pendente_entrada_repository.dart';
import '../services/nfe_xml_parser.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _data = DateFormat('dd/MM/yyyy');
final _dataHora = DateFormat('dd/MM HH:mm');

/// Lista as NF-e que o poll de fundo (nfe-sefaz-service) já baixou da Sefaz
/// sozinho, mas que ainda não viraram entrada de estoque — pra não precisar
/// escanear/digitar a chave de novo pra uma nota que o sistema já trouxe.
/// Ao tocar numa nota, devolve o XML pra tela de importação processar,
/// exatamente como se tivesse acabado de ser buscada pela chave.
class NotasPendentesEntradaScreen extends StatefulWidget {
  const NotasPendentesEntradaScreen({super.key});

  @override
  State<NotasPendentesEntradaScreen> createState() => _NotasPendentesEntradaScreenState();
}

class _NotasPendentesEntradaScreenState extends State<NotasPendentesEntradaScreen> {
  late Future<List<NfePendenteEntrada>> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = NfePendenteEntradaRepository().listar();
  }

  Future<void> _recarregar() async {
    setState(() => _futuro = NfePendenteEntradaRepository().listar());
    await _futuro;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notas pendentes de entrada')),
      body: RefreshIndicator(
        onRefresh: _recarregar,
        child: FutureBuilder<List<NfePendenteEntrada>>(
          future: _futuro,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return ListView(
                children: [
                  const SizedBox(height: 80),
                  Center(child: Text('Erro ao carregar: ${snapshot.error}')),
                ],
              );
            }
            final notas = snapshot.data ?? [];
            if (notas.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 80),
                  Icon(Icons.inbox_outlined, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 12),
                  const Center(child: Text('Nenhuma nota pendente no momento.')),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      'Assim que uma nota nova chegar da Sefaz pra essa empresa, ela aparece aqui sozinha.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5),
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: notas.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _cardNota(context, notas[i]),
            );
          },
        ),
      ),
    );
  }

  Widget _cardNota(BuildContext context, NfePendenteEntrada pendente) {
    // O XML já foi validado pela Sefaz antes de chegar no cache — um erro
    // aqui só pode ser um formato inesperado, então mostra a nota mesmo
    // assim (com os dados básicos que dá pra confiar) em vez de escondê-la.
    try {
      final nfe = NfeXmlParser.parse(pendente.xml);
      return Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: () => Navigator.pop(context, pendente.xml),
          leading: const CircleAvatar(child: Icon(Icons.description_outlined)),
          title: Text(nfe.fornecedorDetectado.nome),
          subtitle: Text(
            'NF ${nfe.numero ?? "?"}'
            '${nfe.dataEmissao != null ? ' • emitida ${_data.format(nfe.dataEmissao!)}' : ''}'
            '\nRecebida da Sefaz em ${_dataHora.format(pendente.recebidoEm)}',
          ),
          isThreeLine: true,
          trailing: Text(_moeda.format(nfe.valorTotalNota), style: const TextStyle(fontWeight: FontWeight.w600)),
        ),
      );
    } catch (e) {
      return Card(
        child: ListTile(
          onTap: () => Navigator.pop(context, pendente.xml),
          leading: const Icon(Icons.warning_amber_outlined),
          title: Text('Chave ${pendente.chave}'),
          subtitle: Text('Recebida em ${_dataHora.format(pendente.recebidoEm)} — não foi possível ler os detalhes.'),
        ),
      );
    }
  }
}
