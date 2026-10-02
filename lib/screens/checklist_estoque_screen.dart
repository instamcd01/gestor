import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/checklist_estoque.dart';
import '../models/produto.dart';
import '../providers/produto_provider.dart';
import '../repositories/checklist_estoque_repository.dart';
import '../utils/busca_utils.dart';
import '../utils/leitor_codigo_barras.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

String formatarValidade(DateTime d) => '${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Dias até vencer (negativo = vencido).
int diasParaVencer(DateTime validade) {
  final hoje = DateTime.now();
  return DateTime(validade.year, validade.month, validade.day)
      .difference(DateTime(hoje.year, hoje.month, hoje.day))
      .inDays;
}

/// Produtos que entram no checklist: todos os ativos, menos kit (estoque vem
/// dos componentes) e o saco fechado que tem granel — o granel é a fonte
/// real do estoque e o saco é recalculado a partir dele, então conta-se só
/// o granel (sacos fechados × fator + soltos).
List<Produto> produtosDoChecklist(List<Produto> todos) {
  final paisDeGranel = {for (final p in todos) if (p.fracionadoDeId != null) p.fracionadoDeId!};
  final lista = todos.where((p) => p.id != null && p.ativo && !p.ehKit && !paisDeGranel.contains(p.id)).toList()
    ..sort((a, b) {
      final c = a.categoria.toLowerCase().compareTo(b.categoria.toLowerCase());
      return c != 0 ? c : a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
    });
  return lista;
}

/// Entrada do checklist: continua o aberto ou inicia o do mês, e lista os
/// anteriores (abre o resumo).
class ChecklistEstoqueScreen extends StatefulWidget {
  const ChecklistEstoqueScreen({super.key});

  @override
  State<ChecklistEstoqueScreen> createState() => _ChecklistEstoqueScreenState();
}

class _ChecklistEstoqueScreenState extends State<ChecklistEstoqueScreen> {
  final _repo = ChecklistEstoqueRepository();
  List<ChecklistEstoque>? _checklists;
  String? _erro;
  bool _iniciando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final lista = await _repo.listar();
      if (mounted) setState(() => _checklists = lista);
    } catch (e) {
      if (mounted) setState(() => _erro = 'Erro ao carregar checklists: $e');
    }
  }

  Future<void> _iniciar() async {
    final referencia = ChecklistEstoque.referenciaDe(DateTime.now());
    setState(() => _iniciando = true);
    try {
      final novo = await _repo.iniciar(referencia);
      if (!mounted) return;
      await _abrir(novo);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível iniciar: $e')));
    } finally {
      if (mounted) setState(() => _iniciando = false);
    }
  }

  Future<void> _abrir(ChecklistEstoque checklist) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => checklist.aberto
          ? ConferenciaChecklistScreen(checklist: checklist)
          : ResumoChecklistScreen(checklist: checklist),
    ));
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final lista = _checklists;
    final aberto = lista?.where((c) => c.aberto).firstOrNull;
    final referenciaAtual = ChecklistEstoque.referenciaDe(DateTime.now());
    final jaFezEsteMes = lista?.any((c) => c.referencia == referenciaAtual) ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Checklist de estoque')),
      body: _erro != null
          ? Center(child: Text(_erro!))
          : lista == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              aberto != null ? 'Checklist de ${aberto.titulo} em andamento' : 'Contagem e validade do mês',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Confira a quantidade na prateleira e a validade mais próxima de cada produto. '
                              'Pode fazer em vários dias — o progresso fica salvo.',
                            ),
                            const SizedBox(height: 12),
                            if (aberto != null)
                              FilledButton.icon(
                                onPressed: () => _abrir(aberto),
                                icon: const Icon(Icons.play_arrow),
                                label: const Text('Continuar'),
                              )
                            else if (jaFezEsteMes)
                              const Text('O checklist deste mês já foi concluído.')
                            else
                              FilledButton.icon(
                                onPressed: _iniciando ? null : _iniciar,
                                icon: const Icon(Icons.fact_check_outlined),
                                label: Text('Iniciar checklist de ${ChecklistEstoque.tituloDe(referenciaAtual)}'),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (lista.any((c) => !c.aberto)) ...[
                      const SizedBox(height: 16),
                      Text('Anteriores', style: Theme.of(context).textTheme.titleSmall),
                      for (final c in lista.where((c) => !c.aberto))
                        ListTile(
                          leading: const Icon(Icons.assignment_turned_in_outlined),
                          title: Text(c.titulo),
                          subtitle: Text('Concluído em ${DateFormat('dd/MM/yyyy').format(c.concluidoEm!)}'),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _abrir(c),
                        ),
                    ],
                  ],
                ),
    );
  }
}

enum _Filtro { pendentes, conferidos, divergencias, todos }

class ConferenciaChecklistScreen extends StatefulWidget {
  final ChecklistEstoque checklist;

  const ConferenciaChecklistScreen({super.key, required this.checklist});

  @override
  State<ConferenciaChecklistScreen> createState() => _ConferenciaChecklistScreenState();
}

class _ConferenciaChecklistScreenState extends State<ConferenciaChecklistScreen> {
  final _repo = ChecklistEstoqueRepository();
  final _buscaController = TextEditingController();
  Map<String, ChecklistItem>? _itens;
  Map<String, DateTime?> _validades = {};
  String? _erro;
  _Filtro _filtro = _Filtro.pendentes;
  String? _categoria;

  bool get _temLeitor => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _buscaController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final resultados = await Future.wait([
        _repo.listarItens(widget.checklist.id),
        _repo.listarValidades(),
      ]);
      if (!mounted) return;
      setState(() {
        _itens = resultados[0] as Map<String, ChecklistItem>;
        _validades = resultados[1] as Map<String, DateTime?>;
      });
    } catch (e) {
      if (mounted) setState(() => _erro = 'Erro ao carregar o checklist: $e');
    }
  }

  List<Produto> _filtrar(List<Produto> produtos) {
    final itens = _itens ?? const {};
    final busca = _buscaController.text.trim();
    return produtos.where((p) {
      final item = itens[p.id];
      final passaFiltro = switch (_filtro) {
        _Filtro.pendentes => item == null,
        _Filtro.conferidos => item != null,
        _Filtro.divergencias => item != null && item.diferenca != 0,
        _Filtro.todos => true,
      };
      if (!passaFiltro) return false;
      if (_categoria != null && p.categoria != _categoria) return false;
      if (busca.isEmpty) return true;
      return p.codigoBarras == busca || contemTodasPalavras(normalizarBusca(p.nome), normalizarBusca(busca));
    }).toList();
  }

  Future<void> _lerCodigo(List<Produto> produtos) async {
    final codigo = await lerCodigoDeBarras(context);
    if (codigo == null || !mounted) return;
    final produto = produtos.where((p) => p.codigoBarras == codigo).firstOrNull;
    if (produto == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Nenhum produto do checklist com o código $codigo.')),
      );
      return;
    }
    await _conferir(produto, produtos);
  }

  /// Abre a conferência de [produto]; com "Confirmar e próximo", segue pro
  /// próximo pendente da lista filtrada sem voltar pra lista.
  Future<void> _conferir(Produto produto, List<Produto> produtos) async {
    Produto? atual = produto;
    while (atual != null && mounted) {
      final proximo = await _abrirConferencia(atual, produtos);
      if (!proximo || !mounted) return;
      final visiveis = _filtrar(produtos);
      final indice = visiveis.indexWhere((p) => p.id == atual!.id);
      final itens = _itens ?? const {};
      atual = visiveis.skip(indice + 1).where((p) => !itens.containsKey(p.id)).firstOrNull ??
          visiveis.where((p) => !itens.containsKey(p.id)).firstOrNull;
    }
  }

  /// true = usuário pediu o próximo.
  Future<bool> _abrirConferencia(Produto produto, List<Produto> produtos) async {
    final pai = produto.fracionadoDeId != null
        ? context.read<ProdutoProvider>().getProdutoPorId(produto.fracionadoDeId!)
        : null;
    final int saldo;
    try {
      saldo = await _repo.saldoAtual(produto.id!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao ler o estoque: $e')));
      }
      return false;
    }
    if (!mounted) return false;

    final validadeAnterior = _validades[produto.id];
    final resultado = await showModalBottomSheet<_ResultadoConferencia>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _PainelConferencia(
        produto: produto,
        pai: pai,
        saldoSistema: saldo,
        jaConferido: _itens?[produto.id],
        validadeAnterior: validadeAnterior,
        conferidoAntes: _validades.containsKey(produto.id),
      ),
    );
    if (resultado == null || !mounted) return false;

    try {
      final item = await _repo.conferir(
        checklistId: widget.checklist.id,
        produtoId: produto.id!,
        quantidadeContada: resultado.quantidade,
        quantidadeEsperada: saldo,
        validade: resultado.validade,
      );
      if (!mounted) return false;
      setState(() {
        _itens = {...?_itens, produto.id!: item};
        _validades = {
          ..._validades,
          produto.id!: resultado.validade,
          if (pai?.id != null) pai!.id!: resultado.validade,
        };
      });
      context.read<ProdutoProvider>().recarregarProdutos([produto.id!, if (pai?.id != null) pai!.id!]);
      return resultado.proximo;
    } catch (e) {
      if (!mounted) return false;
      final msg = e.toString().contains('mudou para')
          ? 'O estoque mudou enquanto você contava (venda ou entrada). Abra o produto de novo e confira.'
          : 'Não foi possível salvar: $e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 5)));
      return false;
    }
  }

  /// Concluir é feito no resumo — se concluiu, esta tela fecha junto.
  Future<void> _abrirResumo() async {
    final concluiu = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ResumoChecklistScreen(checklist: widget.checklist),
    ));
    if (concluiu == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final produtos = produtosDoChecklist(context.watch<ProdutoProvider>().produtos);
    final itens = _itens;

    return Scaffold(
      appBar: AppBar(
        title: Text('Checklist ${widget.checklist.titulo}'),
        actions: [
          TextButton(
            onPressed: itens == null ? null : _abrirResumo,
            child: const Text('Resumo'),
          ),
        ],
      ),
      body: _erro != null
          ? Center(child: Text(_erro!))
          : itens == null
              ? const Center(child: CircularProgressIndicator())
              : _corpo(produtos, itens),
    );
  }

  Widget _corpo(List<Produto> produtos, Map<String, ChecklistItem> itens) {
    final idsChecklist = {for (final p in produtos) p.id!};
    final conferidos = itens.keys.where(idsChecklist.contains).length;
    final divergencias = itens.values.where((i) => i.diferenca != 0).length;
    final visiveis = _filtrar(produtos);
    final categorias = {for (final p in produtos) p.categoria}.toList()..sort();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$conferidos de ${produtos.length} conferidos'
                  '${divergencias > 0 ? ' • $divergencias com diferença' : ''}'),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: produtos.isEmpty ? 0 : conferidos / produtos.length),
              const SizedBox(height: 12),
              TextField(
                controller: _buscaController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Buscar produto ou código',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: _temLeitor
                      ? IconButton(
                          tooltip: 'Ler código de barras',
                          icon: const Icon(Icons.qr_code_scanner),
                          onPressed: () => _lerCodigo(produtos),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final f in _Filtro.values) ...[
                    ChoiceChip(
                      label: Text(switch (f) {
                        _Filtro.pendentes => 'Pendentes',
                        _Filtro.conferidos => 'Conferidos',
                        _Filtro.divergencias => 'Com diferença',
                        _Filtro.todos => 'Todos',
                      }),
                      selected: _filtro == f,
                      onSelected: (_) => setState(() => _filtro = f),
                    ),
                    const SizedBox(width: 6),
                  ],
                  PopupMenuButton<String?>(
                    tooltip: 'Filtrar por categoria',
                    onSelected: (v) => setState(() => _categoria = v),
                    itemBuilder: (_) => [
                      const PopupMenuItem<String?>(value: null, child: Text('Todas as categorias')),
                      for (final c in categorias) PopupMenuItem<String?>(value: c, child: Text(c)),
                    ],
                    child: Chip(
                      avatar: const Icon(Icons.filter_list, size: 18),
                      label: Text(_categoria ?? 'Categoria'),
                    ),
                  ),
                ]),
              ),
            ],
          ),
        ),
        const Divider(height: 16),
        Expanded(
          child: visiveis.isEmpty
              ? Center(
                  child: _filtro == _Filtro.pendentes && _buscaController.text.isEmpty && _categoria == null
                      ? Column(mainAxisSize: MainAxisSize.min, children: [
                          const Text('Tudo conferido!'),
                          const SizedBox(height: 8),
                          FilledButton(onPressed: _abrirResumo, child: const Text('Ver resumo e concluir')),
                        ])
                      : const Text('Nenhum produto com esse filtro.'),
                )
              : ListView.builder(
                  itemCount: visiveis.length,
                  itemBuilder: (context, i) {
                    final p = visiveis[i];
                    final novaCategoria = i == 0 || visiveis[i - 1].categoria != p.categoria;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (novaCategoria)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              p.categoria.isEmpty ? 'Sem categoria' : p.categoria,
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                            ),
                          ),
                        _LinhaProduto(
                          produto: p,
                          item: itens[p.id],
                          validade: _validades[p.id],
                          onTap: () => _conferir(p, produtos),
                        ),
                      ],
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _LinhaProduto extends StatelessWidget {
  final Produto produto;
  final ChecklistItem? item;
  final DateTime? validade;
  final VoidCallback onTap;

  const _LinhaProduto({required this.produto, required this.item, required this.validade, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final conferido = item;
    final partes = <String>[
      conferido == null ? 'Sistema: ${produto.estoqueAtual}' : 'Contado: ${conferido.quantidadeContada}',
      if (validade != null) 'Validade ${formatarValidade(validade!)}',
    ];
    final dias = validade != null ? diasParaVencer(validade!) : null;

    Widget? trailing;
    if (conferido != null) {
      final dif = conferido.diferenca;
      trailing = dif == 0
          ? Icon(Icons.check_circle, color: cores.primary)
          : Chip(
              label: Text(dif > 0 ? '+$dif' : '$dif'),
              backgroundColor: dif < 0 ? cores.errorContainer : cores.tertiaryContainer,
              visualDensity: VisualDensity.compact,
            );
    }

    return ListTile(
      onTap: onTap,
      title: Text(produto.nome, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text.rich(TextSpan(children: [
        TextSpan(text: partes.join(' • ')),
        if (dias != null && dias <= 90)
          TextSpan(
            text: dias < 0 ? ' • VENCIDO' : ' • vence em $dias dias',
            style: TextStyle(color: cores.error, fontWeight: FontWeight.w600),
          ),
      ])),
      trailing: trailing ?? const Icon(Icons.chevron_right),
    );
  }
}

class _ResultadoConferencia {
  final int quantidade;
  final DateTime? validade;
  final bool proximo;

  const _ResultadoConferencia(this.quantidade, this.validade, this.proximo);
}

/// Painel de conferência de 1 produto, pensado pro celular: quantidade já
/// vem com o saldo do sistema (se bate, é só confirmar), botões grandes de
/// −/+ e validade em mês/ano, como vem impressa na embalagem.
class _PainelConferencia extends StatefulWidget {
  final Produto produto;

  /// Saco fechado, quando [produto] é granel.
  final Produto? pai;
  final int saldoSistema;
  final ChecklistItem? jaConferido;
  final DateTime? validadeAnterior;

  /// Já teve validade conferida antes (mesmo que "sem validade").
  final bool conferidoAntes;

  const _PainelConferencia({
    required this.produto,
    required this.pai,
    required this.saldoSistema,
    required this.jaConferido,
    required this.validadeAnterior,
    required this.conferidoAntes,
  });

  @override
  State<_PainelConferencia> createState() => _PainelConferenciaState();
}

class _PainelConferenciaState extends State<_PainelConferencia> {
  late final TextEditingController _qtd;
  late final TextEditingController _fechados;
  late final TextEditingController _soltos;
  late final TextEditingController _validade;
  late bool _semValidade;

  int? get _fator => widget.pai != null ? widget.produto.fatorFracionamento : null;

  @override
  void initState() {
    super.initState();
    final base = widget.saldoSistema;
    final fator = _fator;
    _qtd = TextEditingController(text: '$base');
    _fechados = TextEditingController(text: fator != null && fator > 0 ? '${base ~/ fator}' : '0');
    _soltos = TextEditingController(text: fator != null && fator > 0 ? '${base % fator}' : '$base');
    final validade = widget.validadeAnterior;
    _validade = TextEditingController(text: validade != null ? formatarValidade(validade) : '');
    _semValidade = widget.conferidoAntes && validade == null;
  }

  @override
  void dispose() {
    _qtd.dispose();
    _fechados.dispose();
    _soltos.dispose();
    _validade.dispose();
    super.dispose();
  }

  int? get _quantidade {
    final fator = _fator;
    if (fator != null && fator > 0) {
      final fechados = int.tryParse(_fechados.text.trim());
      final soltos = int.tryParse(_soltos.text.trim());
      if (fechados == null || soltos == null || fechados < 0 || soltos < 0) return null;
      return fechados * fator + soltos;
    }
    final q = int.tryParse(_qtd.text.trim());
    return q == null || q < 0 ? null : q;
  }

  /// 'MM/AAAA' → último dia do mês (é até quando o produto vale).
  DateTime? get _validadeDigitada {
    final m = RegExp(r'^(\d{1,2})/(\d{4})$').firstMatch(_validade.text.trim());
    if (m == null) return null;
    final mes = int.parse(m.group(1)!);
    final ano = int.parse(m.group(2)!);
    if (mes < 1 || mes > 12 || ano < 2000 || ano > 2100) return null;
    return DateTime(ano, mes + 1, 0);
  }

  void _somar(TextEditingController c, int delta) {
    final atual = int.tryParse(c.text.trim()) ?? 0;
    final novo = (atual + delta).clamp(0, 999999);
    setState(() => c.text = '$novo');
  }

  void _confirmar(bool proximo) {
    final q = _quantidade;
    if (q == null) return;
    Navigator.pop(context, _ResultadoConferencia(q, _semValidade ? null : _validadeDigitada, proximo));
  }

  Widget _contador(String rotulo, TextEditingController c) {
    return Row(children: [
      Expanded(child: Text(rotulo, style: Theme.of(context).textTheme.bodyLarge)),
      IconButton.filledTonal(
        iconSize: 28,
        onPressed: () => _somar(c, -1),
        icon: const Icon(Icons.remove),
      ),
      SizedBox(
        width: 84,
        child: TextField(
          controller: c,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          style: Theme.of(context).textTheme.headlineSmall,
          onChanged: (_) => setState(() {}),
          onTap: () => c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length),
        ),
      ),
      IconButton.filledTonal(
        iconSize: 28,
        onPressed: () => _somar(c, 1),
        icon: const Icon(Icons.add),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final q = _quantidade;
    final dif = q != null ? q - widget.saldoSistema : 0;
    final custo = widget.produto.custo;
    final validade = _validadeDigitada;
    final validadeOk = _semValidade || validade != null;
    final dias = validade != null && !_semValidade ? diasParaVencer(validade) : null;
    final fator = _fator;
    final podeConfirmar = q != null && validadeOk;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.produto.nome, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'No sistema: ${widget.saldoSistema}'
              '${widget.produto.codigoBarras.isNotEmpty ? ' • ${widget.produto.codigoBarras}' : ''}',
              style: TextStyle(color: cores.onSurfaceVariant),
            ),
            if (widget.jaConferido != null)
              Text(
                'Já conferido neste checklist (contou ${widget.jaConferido!.quantidadeContada}) — salvar de novo substitui.',
                style: TextStyle(color: cores.onSurfaceVariant),
              ),
            const SizedBox(height: 16),
            if (fator != null && fator > 0) ...[
              _contador('Sacos fechados (×$fator)', _fechados),
              const SizedBox(height: 8),
              _contador('Soltos', _soltos),
              const SizedBox(height: 4),
              Text('Total: ${q ?? '-'}', textAlign: TextAlign.end),
            ] else
              _contador('Quantidade', _qtd),
            if (q != null && dif != 0) ...[
              const SizedBox(height: 8),
              Text(
                '${dif > 0 ? 'Sobra' : 'Falta'} de ${dif.abs()} (${_moeda.format(dif.abs() * custo)} a preço de custo)',
                style: TextStyle(color: dif < 0 ? cores.error : cores.tertiary, fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _validade,
                  enabled: !_semValidade,
                  keyboardType: TextInputType.number,
                  inputFormatters: [_MascaraMesAno()],
                  decoration: InputDecoration(
                    labelText: 'Validade mais próxima (mês/ano)',
                    hintText: 'MM/AAAA',
                    border: const OutlineInputBorder(),
                    errorText: !_semValidade && _validade.text.length == 7 && validade == null ? 'Data inválida' : null,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ]),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Sem validade (ex: acessório)'),
              value: _semValidade,
              onChanged: (v) => setState(() => _semValidade = v ?? false),
            ),
            if (dias != null && dias <= 90)
              Text(
                dias < 0 ? 'Produto vencido!' : 'Vence em $dias dias',
                style: TextStyle(color: cores.error, fontWeight: FontWeight.w600),
              ),
            const SizedBox(height: 16),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
              onPressed: podeConfirmar ? () => _confirmar(true) : null,
              child: const Text('Confirmar e próximo'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: podeConfirmar ? () => _confirmar(false) : null,
              child: const Text('Confirmar e voltar à lista'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Digita só números e insere a barra: "032027" → "03/2027".
class _MascaraMesAno extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digitos = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limitado = digitos.length > 6 ? digitos.substring(0, 6) : digitos;
    final texto = limitado.length > 2 ? '${limitado.substring(0, 2)}/${limitado.substring(2)}' : limitado;
    return TextEditingValue(text: texto, selection: TextSelection.collapsed(offset: texto.length));
  }
}

/// Resumo do checklist: faltas/sobras em unidades e R$ (a preço de custo),
/// comparação com o checklist anterior, e produtos vencendo.
class ResumoChecklistScreen extends StatefulWidget {
  final ChecklistEstoque checklist;

  const ResumoChecklistScreen({super.key, required this.checklist});

  @override
  State<ResumoChecklistScreen> createState() => _ResumoChecklistScreenState();
}

class _ResumoChecklistScreenState extends State<ResumoChecklistScreen> {
  final _repo = ChecklistEstoqueRepository();
  Map<String, ChecklistItem>? _itens;
  Map<String, ChecklistItem>? _itensAnterior;
  ChecklistEstoque? _anterior;
  Map<String, DateTime?> _validades = {};
  String? _erro;
  bool _concluindo = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final todos = await _repo.listar();
      final anterior = todos
          .where((c) => !c.aberto && c.referencia.compareTo(widget.checklist.referencia) < 0)
          .fold<ChecklistEstoque?>(null, (m, c) => m == null || c.referencia.compareTo(m.referencia) > 0 ? c : m);
      final resultados = await Future.wait([
        _repo.listarItens(widget.checklist.id),
        _repo.listarValidades(),
        if (anterior != null) _repo.listarItens(anterior.id),
      ]);
      if (!mounted) return;
      setState(() {
        _itens = resultados[0] as Map<String, ChecklistItem>;
        _validades = resultados[1] as Map<String, DateTime?>;
        _anterior = anterior;
        _itensAnterior = anterior != null ? resultados[2] as Map<String, ChecklistItem> : null;
      });
    } catch (e) {
      if (mounted) setState(() => _erro = 'Erro ao carregar o resumo: $e');
    }
  }

  Future<void> _concluir(int pendentes) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Concluir checklist?'),
        content: Text(pendentes > 0
            ? 'Ainda faltam $pendentes produto(s) sem conferir. Eles ficam sem contagem neste mês.'
            : 'Todos os produtos foram conferidos.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Concluir')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _concluindo = true);
    try {
      await _repo.concluir(widget.checklist.id);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _concluindo = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível concluir: $e')));
    }
  }

  ({int faltaUn, double faltaValor, int sobraUn, double sobraValor}) _totais(Iterable<ChecklistItem> itens) {
    var faltaUn = 0, sobraUn = 0;
    var faltaValor = 0.0, sobraValor = 0.0;
    for (final i in itens) {
      if (i.diferenca < 0) {
        faltaUn += -i.diferenca;
        faltaValor += -i.diferencaValor;
      } else if (i.diferenca > 0) {
        sobraUn += i.diferenca;
        sobraValor += i.diferencaValor;
      }
    }
    return (faltaUn: faltaUn, faltaValor: faltaValor, sobraUn: sobraUn, sobraValor: sobraValor);
  }

  @override
  Widget build(BuildContext context) {
    final itens = _itens;
    return Scaffold(
      appBar: AppBar(title: Text('Resumo ${widget.checklist.titulo}')),
      body: _erro != null
          ? Center(child: Text(_erro!))
          : itens == null
              ? const Center(child: CircularProgressIndicator())
              : _corpo(context, itens),
    );
  }

  Widget _corpo(BuildContext context, Map<String, ChecklistItem> itens) {
    final cores = Theme.of(context).colorScheme;
    final provider = context.watch<ProdutoProvider>();
    final produtos = produtosDoChecklist(provider.produtos);
    final porId = {for (final p in provider.produtos) if (p.id != null) p.id!: p};
    final pendentes = produtos.where((p) => !itens.containsKey(p.id)).length;
    final t = _totais(itens.values);
    final liquido = t.sobraValor - t.faltaValor;
    final anterior = _itensAnterior != null ? _totais(_itensAnterior!.values) : null;

    final divergentes = itens.values.where((i) => i.diferenca != 0).toList()
      ..sort((a, b) => b.diferencaValor.abs().compareTo(a.diferencaValor.abs()));

    // Vencimento olha o estoque atual (não só o conferido neste mês).
    final vencendo = <({Produto produto, DateTime validade, int dias})>[];
    for (final p in produtos) {
      final v = _validades[p.id];
      if (v == null || p.estoqueAtual <= 0) continue;
      final dias = diasParaVencer(v);
      if (dias <= 90) vencendo.add((produto: p, validade: v, dias: dias));
    }
    vencendo.sort((a, b) => a.dias.compareTo(b.dias));
    double valorFaixa(bool Function(int) cond) => vencendo
        .where((v) => cond(v.dias))
        .fold(0.0, (s, v) => s + v.produto.estoqueAtual * v.produto.custo);
    int qtdFaixa(bool Function(int) cond) => vencendo.where((v) => cond(v.dias)).length;

    Widget linhaValor(String rotulo, String valor, {Color? cor}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(rotulo)),
            Text(valor, style: TextStyle(fontWeight: FontWeight.w600, color: cor)),
          ]),
        );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Contagem', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              linhaValor('Conferidos', '${itens.length} de ${produtos.length}'),
              linhaValor('Faltaram', '${t.faltaUn} un. • ${_moeda.format(t.faltaValor)}', cor: cores.error),
              linhaValor('Sobraram', '${t.sobraUn} un. • ${_moeda.format(t.sobraValor)}'),
              const Divider(),
              linhaValor('Resultado', _moeda.format(liquido), cor: liquido < 0 ? cores.error : null),
              if (anterior != null)
                linhaValor(
                  'Mês anterior (${_anterior!.titulo})',
                  _moeda.format(anterior.sobraValor - anterior.faltaValor),
                ),
              const SizedBox(height: 6),
              Text(
                'Falta recorrente costuma ser venda não registrada ou perda; sobra costuma ser entrada não lançada.',
                style: TextStyle(color: cores.onSurfaceVariant, fontSize: 12),
              ),
            ]),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Validade (estoque atual)', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              linhaValor('Vencidos', '${qtdFaixa((d) => d < 0)} • ${_moeda.format(valorFaixa((d) => d < 0))}',
                  cor: cores.error),
              linhaValor('Vencem em até 30 dias',
                  '${qtdFaixa((d) => d >= 0 && d <= 30)} • ${_moeda.format(valorFaixa((d) => d >= 0 && d <= 30))}'),
              linhaValor('31 a 60 dias',
                  '${qtdFaixa((d) => d > 30 && d <= 60)} • ${_moeda.format(valorFaixa((d) => d > 30 && d <= 60))}'),
              linhaValor('61 a 90 dias',
                  '${qtdFaixa((d) => d > 60 && d <= 90)} • ${_moeda.format(valorFaixa((d) => d > 60 && d <= 90))}'),
              for (final v in vencendo)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(v.produto.nome, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${v.produto.estoqueAtual} un. • validade ${formatarValidade(v.validade)}'),
                  trailing: Text(
                    v.dias < 0 ? 'vencido' : '${v.dias} dias',
                    style: TextStyle(color: cores.error, fontWeight: FontWeight.w600),
                  ),
                ),
            ]),
          ),
        ),
        if (divergentes.isNotEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Diferenças (maior valor primeiro)', style: Theme.of(context).textTheme.titleMedium),
                for (final i in divergentes)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(porId[i.produtoId]?.nome ?? 'Produto removido',
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('Sistema ${i.quantidadeSistema} → contado ${i.quantidadeContada}'),
                    trailing: Text(
                      '${i.diferenca > 0 ? '+' : ''}${i.diferenca} • ${_moeda.format(i.diferencaValor)}',
                      style: TextStyle(color: i.diferenca < 0 ? cores.error : null, fontWeight: FontWeight.w600),
                    ),
                  ),
              ]),
            ),
          ),
        if (widget.checklist.aberto) ...[
          const SizedBox(height: 8),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _concluindo ? null : () => _concluir(pendentes),
            child: Text(pendentes > 0 ? 'Concluir checklist ($pendentes pendentes)' : 'Concluir checklist'),
          ),
        ],
      ],
    );
  }
}
