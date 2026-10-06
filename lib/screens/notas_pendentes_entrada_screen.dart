import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/despesa.dart';
import '../providers/despesa_provider.dart';
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
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_moeda.format(nfe.valorTotalNota), style: const TextStyle(fontWeight: FontWeight.w600)),
              PopupMenuButton<String>(
                tooltip: 'Mais opções',
                onSelected: (_) => _naoEMercadoria(pendente, nfe),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'nao_mercadoria',
                    child: ListTile(
                      leading: Icon(Icons.receipt_long_outlined),
                      title: Text('Não é mercadoria'),
                      subtitle: Text('Lançar como despesa ou dispensar'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ],
          ),
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

  /// Nota que veio contra o CNPJ mas não é pra revenda (equipamento,
  /// material de uso/consumo...): não pode virar entrada de estoque, senão
  /// cria produto no catálogo e mistura o custo com o das mercadorias.
  Future<void> _naoEMercadoria(NfePendenteEntrada pendente, NfeImportada nfe) async {
    final resultado = await showDialog<_DispensaNota>(
      context: context,
      builder: (_) => _DialogNaoEMercadoria(nfe: nfe),
    );
    if (resultado == null || !mounted) return;
    try {
      await NfePendenteEntradaRepository().dispensar(
        chave: pendente.chave,
        lancarDespesa: resultado.lancarDespesa,
        categoria: resultado.categoria,
        descricao: resultado.descricao,
        metodoPagamento: resultado.metodoPagamento,
        dataPagamento: resultado.dataPagamento,
      );
      if (!mounted) return;
      if (resultado.lancarDespesa) {
        // Tela de despesas lê do provider global — sem isso a despesa nova
        // só aparece depois de reabrir o app.
        context.read<DespesaProvider>().carregar();
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(resultado.lancarDespesa
            ? 'Despesa de ${_moeda.format(nfe.valorTotalNota)} lançada e nota retirada da lista'
            : 'Nota retirada da lista'),
      ));
      await _recarregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível concluir: $e')));
    }
  }
}

class _DispensaNota {
  final bool lancarDespesa;
  final String? categoria;
  final String? descricao;
  final String? metodoPagamento;
  final DateTime? dataPagamento;

  _DispensaNota({required this.lancarDespesa, this.categoria, this.descricao, this.metodoPagamento, this.dataPagamento});
}

class _DialogNaoEMercadoria extends StatefulWidget {
  final NfeImportada nfe;

  const _DialogNaoEMercadoria({required this.nfe});

  @override
  State<_DialogNaoEMercadoria> createState() => _DialogNaoEMercadoriaState();
}

class _DialogNaoEMercadoriaState extends State<_DialogNaoEMercadoria> {
  bool _lancarDespesa = true;
  String _categoria = 'Infraestrutura/Tecnologia';
  String _metodo = metodosPagamentoDespesa.first;
  late DateTime _dataPagamento;
  late final TextEditingController _descricao;

  @override
  void initState() {
    super.initState();
    final nfe = widget.nfe;
    _dataPagamento = nfe.dataEmissao ?? DateTime.now();
    final primeiro = nfe.itens.isNotEmpty ? nfe.itens.first.descricaoNfe : 'Compra';
    final extra = nfe.itens.length > 1 ? ' e mais ${nfe.itens.length - 1} item(ns)' : '';
    _descricao = TextEditingController(text: '$primeiro$extra (NF ${nfe.numero ?? "?"})');
  }

  @override
  void dispose() {
    _descricao.dispose();
    super.dispose();
  }

  Future<void> _escolherData() async {
    final escolhida = await showDatePicker(
      context: context,
      initialDate: _dataPagamento,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (escolhida != null) setState(() => _dataPagamento = escolhida);
  }

  void _opcao(bool lancar) => setState(() => _lancarDespesa = lancar);

  @override
  Widget build(BuildContext context) {
    final nfe = widget.nfe;
    return AlertDialog(
      title: const Text('Não é mercadoria'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${nfe.fornecedorDetectado.nome}\n${_moeda.format(nfe.valorTotalNota)}'),
            const SizedBox(height: 4),
            Text(
              'A nota sai da lista de pendentes e não entra no estoque.',
              style: TextStyle(fontSize: 12.5, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(_lancarDespesa ? Icons.radio_button_checked : Icons.radio_button_unchecked),
              title: const Text('Lançar como despesa paga'),
              subtitle: const Text('Paga com dinheiro da loja'),
              onTap: () => _opcao(true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(!_lancarDespesa ? Icons.radio_button_checked : Icons.radio_button_unchecked),
              title: const Text('Só dispensar'),
              subtitle: const Text('Brinde, bonificação, pago fora do caixa'),
              onTap: () => _opcao(false),
            ),
            if (_lancarDespesa) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _descricao,
                decoration: const InputDecoration(labelText: 'Descrição'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _categoria,
                decoration: const InputDecoration(labelText: 'Categoria'),
                items: categoriasDespesaSugeridas.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => _categoria = v!),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _metodo,
                decoration: const InputDecoration(labelText: 'Forma de pagamento'),
                items: metodosPagamentoDespesa.map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
                onChanged: (v) => setState(() => _metodo = v!),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _escolherData,
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Pago em',
                    suffixIcon: Icon(Icons.calendar_today_outlined),
                  ),
                  child: Text(_data.format(_dataPagamento)),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _DispensaNota(
              lancarDespesa: _lancarDespesa,
              categoria: _lancarDespesa ? _categoria : null,
              descricao: _lancarDespesa ? _descricao.text.trim() : null,
              metodoPagamento: _lancarDespesa ? _metodo : null,
              dataPagamento: _lancarDespesa ? _dataPagamento : null,
            ),
          ),
          child: Text(_lancarDespesa ? 'Lançar despesa' : 'Dispensar'),
        ),
      ],
    );
  }
}
