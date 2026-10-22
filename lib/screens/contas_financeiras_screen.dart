import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/conta_financeira.dart';
import '../providers/auth_provider.dart';
import '../providers/modulo_provider.dart';
import '../repositories/conta_financeira_repository.dart';
import '../utils/ofx_parser.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _dataCurta = DateFormat('dd/MM/yyyy');

/// "Contas e Conferência" — saldo real de cada conta da loja (vem do último
/// extrato importado; conectores por API entram depois) e onde cai cada
/// tipo de recebimento, que é o que a conferência automática usa pra saber
/// em que extrato procurar o repasse do iFood, o Pix etc.
class ContasFinanceirasScreen extends StatefulWidget {
  const ContasFinanceirasScreen({super.key});

  @override
  State<ContasFinanceirasScreen> createState() => _ContasFinanceirasScreenState();
}

class _ContasFinanceirasScreenState extends State<ContasFinanceirasScreen> {
  final _repository = ContaFinanceiraRepository();
  bool _carregando = true;
  List<ContaFinanceira> _contas = [];
  Map<String, String> _destinos = {};

  String? get _empresaId => context.read<AuthProvider>().empresaId;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final empresaId = _empresaId;
    if (empresaId == null) return;
    setState(() => _carregando = true);
    try {
      final contas = await _repository.listar(empresaId);
      final destinos = await _repository.listarDestinos(empresaId);
      if (mounted) setState(() { _contas = contas; _destinos = destinos; });
    } catch (e) {
      _aviso('Erro ao carregar contas: $e');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _aviso(String texto) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _editarConta([ContaFinanceira? conta]) async {
    final salvou = await showDialog<bool>(context: context, builder: (_) => _ContaDialog(conta: conta));
    if (salvou == true) _carregar();
  }

  Future<void> _importar(ContaFinanceira conta) async {
    final empresaId = _empresaId;
    if (empresaId == null) return;
    final arquivo = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['ofx'], withData: true);
    final bytes = arquivo?.files.single.bytes;
    if (arquivo == null || bytes == null) return;

    final extrato = OfxParser.parse(bytes);
    if (extrato.lancamentos.isEmpty) {
      _aviso('Nenhuma movimentação encontrada no arquivo. Confira se é o extrato em OFX.');
      return;
    }
    try {
      final r = await _repository.importarOfx(
        empresaId: empresaId,
        conta: conta,
        arquivoNome: arquivo.files.single.name,
        extrato: extrato,
      );
      _aviso(r.repetidas == 0
          ? '${r.novas} movimentações importadas'
          : '${r.novas} novas, ${r.repetidas} já estavam no Gestor');
      _carregar();
    } catch (e) {
      _aviso('Erro ao importar: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final ativas = _contas.where((c) => c.ativa).toList();
    final saldoTotal = ativas.fold<double>(0, (t, c) => t + (c.saldoAtual ?? 0));
    final semSaldo = ativas.where((c) => c.saldoAtual == null && !c.automatica).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Contas e Conferência')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editarConta(),
        icon: const Icon(Icons.add),
        label: const Text('Nova conta'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  if (_contas.isEmpty)
                    _vazio(context)
                  else ...[
                    _cartaoTotal(context, saldoTotal, semSaldo),
                    const SizedBox(height: 12),
                    ..._contas.map((c) => _cartaoConta(context, c)),
                    const SizedBox(height: 20),
                    _ondeCai(context),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _vazio(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            Icon(Icons.account_balance_outlined, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            const Text('Cadastre as contas da loja', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            const Text(
              'Banco, maquininha e conta do site. Depois é só importar o extrato (OFX) de cada uma.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );

  Widget _cartaoTotal(BuildContext context, double total, int semSaldo) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.primaryContainer,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Saldo nas contas', style: TextStyle(color: cs.onPrimaryContainer)),
            const SizedBox(height: 4),
            Text(_moeda.format(total),
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: cs.onPrimaryContainer)),
            if (semSaldo > 0)
              Text(
                '$semSaldo conta${semSaldo > 1 ? 's' : ''} ainda sem extrato importado',
                style: TextStyle(fontSize: 12, color: cs.onPrimaryContainer),
              ),
          ],
        ),
      ),
    );
  }

  Widget _cartaoConta(BuildContext context, ContaFinanceira c) {
    final cs = Theme.of(context).colorScheme;
    final detalhe = [
      c.provedorRotulo == c.nome ? c.tipoRotulo : '${c.provedorRotulo} · ${c.tipoRotulo}',
      if (c.identificacao != null) c.identificacao!,
      if (!c.ativa) 'inativa',
    ].join(' · ');
    final horaSync = c.ultimaSincronizacaoEm == null ? null : DateFormat("dd/MM 'às' HH:mm").format(c.ultimaSincronizacaoEm!);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          ListTile(
            title: Text(c.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(detalhe),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(c.saldoAtual == null ? (c.automatica ? 'saldo em breve' : '—') : _moeda.format(c.saldoAtual),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                if (c.saldoAtualizadoEm != null)
                  Text('em ${_dataCurta.format(c.saldoAtualizadoEm!)}',
                      style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => MovimentacoesContaScreen(conta: c)),
            ),
          ),
          if (c.automatica)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  Icon(c.ultimoErro == null ? Icons.sync : Icons.sync_problem,
                      size: 16, color: c.ultimoErro == null ? Colors.green.shade700 : cs.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      c.ultimoErro != null
                          ? 'Falha ao atualizar: ${c.ultimoErro}'
                          : 'Atualiza sozinha${horaSync == null ? '' : ' · última vez $horaSync'}',
                      style: TextStyle(fontSize: 12, color: c.ultimoErro == null ? cs.onSurfaceVariant : cs.error),
                    ),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(
              children: [
                if (!c.automatica)
                  TextButton.icon(
                    onPressed: () => _importar(c),
                    icon: const Icon(Icons.upload_file, size: 18),
                    label: const Text('Importar extrato'),
                  ),
                TextButton.icon(
                  onPressed: () => _editarConta(c),
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Editar'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ondeCai(BuildContext context) {
    final modulos = context.watch<ModuloProvider>();
    final origens = OrigemDinheiro.todas.where((o) => o.modulos == null || modulos.algumAtivo(o.modulos!)).toList();
    final ativas = _contas.where((c) => c.ativa).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Text('Onde cai cada recebimento',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'É aqui que a conferência procura cada dinheiro: o repasse do iFood no extrato da conta escolhida, e assim por diante.',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (final o in origens)
                ListTile(
                  dense: true,
                  title: Text(o.rotulo),
                  trailing: DropdownButton<String?>(
                    value: ativas.any((c) => c.id == _destinos[o.slug]) ? _destinos[o.slug] : null,
                    hint: const Text('Escolher'),
                    underline: const SizedBox.shrink(),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Não uso')),
                      ...ativas.map((c) => DropdownMenuItem<String?>(value: c.id, child: Text(c.nome))),
                    ],
                    onChanged: (contaId) async {
                      final empresaId = _empresaId;
                      if (empresaId == null) return;
                      setState(() {
                        if (contaId == null) {
                          _destinos.remove(o.slug);
                        } else {
                          _destinos[o.slug] = contaId;
                        }
                      });
                      try {
                        await _repository.definirDestino(empresaId: empresaId, origem: o.slug, contaId: contaId);
                      } catch (e) {
                        _aviso('Erro ao salvar: $e');
                        _carregar();
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ContaDialog extends StatefulWidget {
  final ContaFinanceira? conta;

  const _ContaDialog({this.conta});

  @override
  State<_ContaDialog> createState() => _ContaDialogState();
}

class _ContaDialogState extends State<_ContaDialog> {
  late final _nome = TextEditingController(text: widget.conta?.nome ?? '');
  late final _identificacao = TextEditingController(text: widget.conta?.identificacao ?? '');
  late String _tipo = widget.conta?.tipo ?? 'banco';
  late String _provedor = widget.conta?.provedor ?? 'outro';
  late bool _ativa = widget.conta?.ativa ?? true;
  bool _salvando = false;

  @override
  void dispose() {
    _nome.dispose();
    _identificacao.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null || _nome.text.trim().isEmpty) return;
    setState(() => _salvando = true);
    try {
      await ContaFinanceiraRepository().salvar(
        empresaId: empresaId,
        id: widget.conta?.id,
        nome: _nome.text.trim(),
        tipo: _tipo,
        provedor: _provedor,
        identificacao: _identificacao.text,
        ativa: _ativa,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _salvando = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.conta == null ? 'Nova conta' : 'Editar conta'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _provedor,
              decoration: const InputDecoration(labelText: 'Banco ou empresa'),
              items: ContaFinanceira.provedores.entries
                  .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                  .toList(),
              onChanged: (v) => setState(() {
                _provedor = v ?? 'outro';
                // Sugestão do tipo e do nome pelos provedores conhecidos;
                // o lojista pode trocar.
                _tipo = switch (_provedor) {
                  'stone' => 'maquininha',
                  'mercado_pago' => 'pagamento_online',
                  _ => _tipo,
                };
                if (_nome.text.isEmpty && _provedor != 'outro') _nome.text = ContaFinanceira.provedores[_provedor]!;
              }),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nome,
              decoration: const InputDecoration(labelText: 'Nome', hintText: 'Ex.: Itaú da loja'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _tipo,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: ContaFinanceira.tipos.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
              onChanged: (v) => setState(() => _tipo = v ?? 'banco'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _identificacao,
              decoration: const InputDecoration(labelText: 'Identificação (opcional)', hintText: 'Ex.: Ag 0001 · final 1234'),
            ),
            if (widget.conta != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Conta em uso'),
                value: _ativa,
                onChanged: (v) => setState(() => _ativa = v),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _salvando ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: _salvando ? null : _salvar, child: const Text('Salvar')),
      ],
    );
  }
}

/// Extrato da conta como está no Gestor (o que foi importado), mais novo
/// primeiro. A conferência com pedidos/despesas entra na próxima etapa.
class MovimentacoesContaScreen extends StatefulWidget {
  final ContaFinanceira conta;

  const MovimentacoesContaScreen({super.key, required this.conta});

  @override
  State<MovimentacoesContaScreen> createState() => _MovimentacoesContaScreenState();
}

class _MovimentacoesContaScreenState extends State<MovimentacoesContaScreen> {
  late Future<List<MovimentacaoFinanceira>> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = ContaFinanceiraRepository().listarMovimentacoes(contaId: widget.conta.id);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.conta.nome)),
      body: FutureBuilder<List<MovimentacaoFinanceira>>(
        future: _futuro,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
          if (snap.hasError) return Center(child: Text('Erro: ${snap.error}'));
          final lista = snap.data!;
          if (lista.isEmpty) {
            return const Center(child: Text('Nenhuma movimentação. Importe o extrato na tela anterior.'));
          }
          final entradas = lista.where((m) => m.entrada).fold<double>(0, (t, m) => t + m.valor);
          final saidas = lista.where((m) => !m.entrada).fold<double>(0, (t, m) => t + m.valor);
          final taxas = lista.fold<double>(0, (t, m) => t + (m.taxa ?? 0));
          final aConferir = lista.where((m) => !m.conferida).length;
          return ListView.separated(
            itemCount: lista.length + 1,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, i) {
              if (i == 0) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    [
                      '${lista.length} movimentações · entradas ${_moeda.format(entradas)} · saídas ${_moeda.format(saidas)}',
                      if (taxas > 0) 'taxas descontadas ${_moeda.format(taxas)}',
                      '$aConferir a conferir',
                    ].join(' · '),
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                  ),
                );
              }
              final m = lista[i - 1];
              final cor = m.entrada ? Colors.green.shade700 : cs.error;
              final detalhes = [
                _dataCurta.format(m.data),
                if (m.taxa != null && m.taxa! > 0) 'taxa ${_moeda.format(m.taxa)}',
                if (m.liberado == false && m.liberacao != null) 'libera em ${DateFormat('dd/MM').format(m.liberacao!)}',
                m.conferida ? 'conferida' : 'a conferir',
              ];
              return ListTile(
                dense: true,
                title: Text(m.descricao ?? (m.entrada ? 'Entrada' : 'Saída'), maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Text(detalhes.join(' · ')),
                trailing: Text(
                  '${m.entrada ? '+' : '−'} ${_moeda.format(m.valor)}',
                  style: TextStyle(color: cor, fontWeight: FontWeight.w600),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
