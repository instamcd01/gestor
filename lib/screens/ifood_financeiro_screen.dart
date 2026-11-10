import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../repositories/ifood_merchant_repository.dart';

/// Financeiro do iFood pela API (módulo Financial v3.0), pela Edge Function
/// `ifood-merchant`: vendas, eventos financeiros, repasses, antecipações e o
/// arquivo de conciliação do mês. Tudo é consultado no iFood na hora; cada
/// lista exporta CSV.
///
/// "Dados de teste do iFood" manda o header x-request-homologation (o iFood
/// devolve dados fictícios da loja de teste), que é o que o questionário de
/// homologação pede.
class IfoodFinanceiroScreen extends StatefulWidget {
  const IfoodFinanceiroScreen({super.key});

  @override
  State<IfoodFinanceiroScreen> createState() => _IfoodFinanceiroScreenState();
}

final _dia = DateFormat('yyyy-MM-dd');
final _diaBr = DateFormat('dd/MM/yyyy');
final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

class _IfoodFinanceiroScreenState extends State<IfoodFinanceiroScreen> {
  DateTime _inicio = DateTime.now().subtract(const Duration(days: 7));
  DateTime _fim = DateTime.now();
  bool _homologacao = false;

  Future<void> _escolher(bool inicio) async {
    final d = await showDatePicker(
      context: context,
      initialDate: inicio ? _inicio : _fim,
      firstDate: DateTime.now().subtract(const Duration(days: 400)),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (d != null) setState(() => inicio ? _inicio = d : _fim = d);
  }

  @override
  Widget build(BuildContext context) {
    final periodo = _Periodo(_dia.format(_inicio), _dia.format(_fim), _homologacao);
    return DefaultTabController(
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Financeiro iFood'),
          bottom: const TabBar(isScrollable: true, tabs: [
            Tab(text: 'Vendas'),
            Tab(text: 'Eventos financeiros'),
            Tab(text: 'Repasses'),
            Tab(text: 'Antecipações'),
            Tab(text: 'Conciliação'),
          ]),
        ),
        body: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              OutlinedButton.icon(onPressed: () => _escolher(true), icon: const Icon(Icons.event), label: Text('De ${_diaBr.format(_inicio)}')),
              OutlinedButton.icon(onPressed: () => _escolher(false), icon: const Icon(Icons.event), label: Text('Até ${_diaBr.format(_fim)}')),
              FilterChip(
                label: const Text('Dados de teste do iFood (homologação)'),
                selected: _homologacao,
                onSelected: (v) => setState(() => _homologacao = v),
              ),
            ]),
          ),
          Expanded(
            child: TabBarView(children: [
              _AbaLista(
                key: ValueKey('vendas$periodo'),
                periodo: periodo,
                titulo: 'Vendas',
                vazio: 'Nenhuma venda no período.',
                buscar: (r, p) => r.finVendas(p.inicio, p.fim, homologacao: p.homologacao),
                extrair: (d) => _lista(d, 'sales'),
                titulo1: (m) => 'Pedido ${m['shortId'] ?? m['id'] ?? ''} · ${m['currentStatus'] ?? ''}',
                linhas: _linhasVenda,
                totais: _totaisVendas,
                nomeArquivo: 'vendas-ifood',
                dica: 'O iFood aceita no máximo 8 dias por consulta; o Gestor quebra o período e junta as páginas.',
              ),
              _AbaLista(
                key: ValueKey('eventos$periodo'),
                periodo: periodo,
                titulo: 'Eventos financeiros',
                vazio: 'Nenhum evento financeiro no período.',
                buscar: (r, p) => r.finEventos(p.inicio, p.fim, homologacao: p.homologacao),
                extrair: (d) => _lista(d, 'financialEvents'),
                linhas: _linhasEvento,
                totais: _totaisEventos,
                titulo1: (m) => '${m['name'] ?? m['trigger'] ?? 'Evento'}${m['trigger'] != null && m['name'] != null ? ' · ${m['trigger']}' : ''}',
                nomeArquivo: 'eventos-financeiros-ifood',
                dica: 'Crédito e débito com sinal; "tem impacto no repasse" indica o que entra no valor transferido.',
              ),
              _AbaLista(
                key: ValueKey('repasses$periodo'),
                periodo: periodo,
                titulo: 'Repasses',
                vazio: 'Nenhum repasse com pagamento no período.',
                buscar: (r, p) => r.finRepasses(p.inicio, p.fim, homologacao: p.homologacao),
                extrair: _titulos,
                titulo1: (m) => '${m['type'] ?? 'Repasse'} · ${_r(m['amount'])} · ${m['status'] ?? ''}',
                linhas: _linhasTitulo,
                nomeArquivo: 'repasses-ifood',
                resumo: (d) => d is Map && d['balance'] != null ? 'Saldo do período: ${_moeda.format(_num(d['balance']) ?? 0)}' : null,
                dica: 'Filtra pela data de pagamento. Títulos REPASSE, BOLETO e REGISTRO_RECEBIVEIS; dados bancários quando SUCCEED.',
              ),
              _AbaLista(
                key: ValueKey('antecipacoes$periodo'),
                periodo: periodo,
                titulo: 'Antecipações',
                vazio: 'Nenhuma antecipação calculada no período.',
                buscar: (r, p) => r.finAntecipacoes(p.inicio, p.fim, homologacao: p.homologacao),
                extrair: _titulos,
                titulo1: (m) => 'Antecipação · ${_r(m['amount'] ?? m['netValue'])} · ${m['status'] ?? ''}',
                linhas: _linhasTitulo,
                nomeArquivo: 'antecipacoes-ifood',
                resumo: (d) => d is Map && d['balance'] != null ? 'Saldo do período: ${_moeda.format(_num(d['balance']) ?? 0)}' : null,
                dica: 'Valor original × valor líquido, data original × antecipada e a taxa cobrada.',
              ),
              _AbaConciliacao(homologacao: _homologacao),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Periodo {
  final String inicio;
  final String fim;
  final bool homologacao;
  const _Periodo(this.inicio, this.fim, this.homologacao);
  @override
  String toString() => '$inicio|$fim|$homologacao';
}

List<Map<String, dynamic>> _lista(dynamic d, String chave) {
  if (d is Map && d[chave] is List) return (d[chave] as List).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
  return const [];
}

num? _num(dynamic v) => v is num ? v : num.tryParse('${v ?? ''}');

String _r(dynamic v) => _moeda.format(_num(v) ?? 0);

String _data(dynamic v) {
  final d = DateTime.tryParse('${v ?? ''}');
  if (d == null) return '${v ?? '-'}';
  return '$v'.length > 10 ? DateFormat('dd/MM/yyyy HH:mm').format(d.toLocal()) : DateFormat('dd/MM/yyyy').format(d);
}

const _nomesLancamento = {
  'ORDER_PAYMENT': 'Pagamento do pedido',
  'ORDER_COMMISSION': 'Comissão iFood',
  'PAYMENT_TRANSACTION_FEE': 'Taxa de transação',
  'SERVICE_FEE': 'Taxa de serviço',
  'IFOOD_SUBSIDY': 'Subsídio iFood (cupom)',
  'DELIVERY_FEE': 'Taxa de entrega',
};

List<Map> _mapas(dynamic v) => v is List ? v.whereType<Map>().toList() : const [];

/// Venda: bruto, pagamento (e quem paga), cupom, lançamentos (comissão, taxas) e líquido.
List<(String, String)> _linhasVenda(Map<String, dynamic> m) {
  final bruto = (m['saleGrossValue'] as Map?) ?? const {};
  final pag = _mapas((m['payments'] as Map?)?['methods']);
  final ben = (m['benefits'] as Map?) ?? const {};
  final bill = (m['billingSummary'] as Map?) ?? const {};
  final cupom = _num(ben['totalValue']) ?? 0;
  final patrocinios = _mapas(ben['benefits']).expand((b) => _mapas(b['sponsorships']))
      .map((s) => '${s['name'] ?? s['sponsor'] ?? ''} ${_r(s['value'])}'.trim()).join(', ');
  return [
    ('Data', _data(m['createdAt'])),
    ('Valor bruto', '${_r(bruto['bag'])} itens + ${_r(bruto['deliveryFee'])} entrega'
        '${bruto['serviceFee'] != null ? ' · taxa de serviço ${_r(bruto['serviceFee'])}' : ''}'),
    if (pag.isNotEmpty)
      ('Pagamento', pag.map((p) => '${p['method']} ${p['type'] ?? ''} ${_r(p['value'])} (responsável: ${p['liability'] ?? '-'})').join(' + ')),
    if (cupom != 0) ('Cupom/benefício', '${_r(cupom)}${patrocinios.isNotEmpty ? ' (patrocínio: $patrocinios)' : ''}'),
    for (final e in _mapas(bill['billingEntries'])) (_nomesLancamento[e['name']] ?? '${e['name']}', _r(e['value'])),
    if (bill['saleBalance'] != null) ('Líquido da venda', _r(bill['saleBalance'])),
  ];
}

String _totaisVendas(List<Map<String, dynamic>> itens) {
  num bruto = 0, liquido = 0, comissao = 0, taxas = 0;
  for (final m in itens) {
    final b = (m['saleGrossValue'] as Map?) ?? const {};
    bruto += (_num(b['bag']) ?? 0) + (_num(b['deliveryFee']) ?? 0);
    final bill = (m['billingSummary'] as Map?) ?? const {};
    liquido += _num(bill['saleBalance']) ?? 0;
    for (final e in _mapas(bill['billingEntries'])) {
      final v = _num(e['value']) ?? 0;
      if (e['name'] == 'ORDER_COMMISSION') comissao += v;
      if ('${e['name']}'.contains('FEE')) taxas += v;
    }
  }
  return '${itens.length} venda(s) · bruto ${_moeda.format(bruto)} · comissões ${_moeda.format(comissao)} · '
      'taxas ${_moeda.format(taxas)} · líquido ${_moeda.format(liquido)}';
}

/// Evento financeiro: valor com sinal, gatilho, data esperada do repasse e impacto no repasse.
List<(String, String)> _linhasEvento(Map<String, dynamic> m) => [
      if ('${m['description'] ?? ''}'.isNotEmpty) ('Descrição', '${m['description']}'),
      ('Valor', _r((m['amount'] as Map?)?['value'] ?? m['amount'])),
      ('Gatilho', '${m['trigger'] ?? '-'}'),
      ('Repasse previsto', _data((m['settlement'] as Map?)?['expectedDate'])),
      ('Impacta o repasse', m['hasTransferImpact'] == true ? 'Sim' : 'Não'),
      ('Competência', '${m['competence'] ?? '-'}'),
      if ((m['payment'] as Map?)?['liability'] != null) ('Responsável', '${(m['payment'] as Map)['liability']}'),
    ];

String _totaisEventos(List<Map<String, dynamic>> itens) {
  num comImpacto = 0, semImpacto = 0;
  for (final m in itens) {
    final v = _num((m['amount'] as Map?)?['value'] ?? m['amount']) ?? 0;
    if (m['hasTransferImpact'] == true) {
      comImpacto += v;
    } else {
      semImpacto += v;
    }
  }
  return '${itens.length} evento(s) · com impacto no repasse ${_moeda.format(comImpacto)} · sem impacto ${_moeda.format(semImpacto)}';
}

/// Repasses/antecipações vêm como períodos com closingItems (títulos): um cartão por título.
List<Map<String, dynamic>> _titulos(dynamic d) {
  final saida = <Map<String, dynamic>>[];
  for (final per in _lista(d, 'settlements')) {
    final itens = _mapas(per['closingItems']);
    if (itens.isEmpty) {
      saida.add(per);
      continue;
    }
    for (final t in itens) {
      saida.add({...Map<String, dynamic>.from(t), 'periodoInicio': per['startDateCalculation'], 'periodoFim': per['endDateCalculation']});
    }
  }
  return saida;
}

List<(String, String)> _linhasTitulo(Map<String, dynamic> m) {
  final conta = (m['accountDetails'] as Map?) ?? const {};
  return [
    ('Valor', _r(m['amount'] ?? m['netValue'] ?? m['value'])),
    if (m['originalAmount'] != null) ('Valor original', _r(m['originalAmount'])),
    if (m['fee'] != null || m['feeAmount'] != null) ('Taxa', _r(m['fee'] ?? m['feeAmount'])),
    ('Status', '${m['status'] ?? '-'}'),
    ('Data de pagamento', _data(m['paymentDate'] ?? m['anticipatedPaymentDate'] ?? m['expectedPaymentDate'])),
    if (m['periodoInicio'] != null) ('Vendas de', '${_data(m['periodoInicio'])} a ${_data(m['periodoFim'])}'),
    if (conta.isNotEmpty)
      ('Conta', '${conta['bankName'] ?? ''} · ag. ${conta['branchCode'] ?? ''} · cc ${conta['accountNumber'] ?? ''}-${conta['accountDigit'] ?? ''}'),
  ];
}

/// Achata um objeto em "a.b.c" → valor (pra mostrar e pro CSV), sem listas grandes.
Map<String, String> _achatar(dynamic v, [String prefixo = '']) {
  final saida = <String, String>{};
  if (v is Map) {
    v.forEach((k, x) => saida.addAll(_achatar(x, prefixo.isEmpty ? '$k' : '$prefixo.$k')));
  } else if (v is List) {
    if (v.every((e) => e is! Map && e is! List)) {
      saida[prefixo] = v.join(' | ');
    } else {
      for (var i = 0; i < v.length && i < 10; i++) {
        saida.addAll(_achatar(v[i], '$prefixo[$i]'));
      }
    }
  } else if (v != null) {
    saida[prefixo] = '$v';
  }
  return saida;
}

String _csv(List<Map<String, dynamic>> linhas) {
  final planas = linhas.map((l) => _achatar(l)).toList();
  final colunas = <String>[];
  for (final p in planas) {
    for (final k in p.keys) {
      if (!colunas.contains(k)) colunas.add(k);
    }
  }
  String q(String s) => '"${s.replaceAll('"', '""')}"';
  final b = StringBuffer()..writeln(colunas.map(q).join(';'));
  for (final p in planas) {
    b.writeln(colunas.map((c) => q(p[c] ?? '')).join(';'));
  }
  return b.toString();
}

Future<void> _salvarCsv(BuildContext context, String conteudo, String nome) async {
  // BOM pro Excel abrir os acentos certo.
  final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(conteudo)]);
  final desktop = !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
  if (desktop) {
    final caminho = await FilePicker.platform.saveFile(
      dialogTitle: 'Salvar CSV', fileName: nome, type: FileType.custom, allowedExtensions: ['csv'], bytes: bytes);
    if (caminho != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('CSV salvo em $caminho')));
    }
    return;
  }
  await SharePlus.instance.share(ShareParams(files: [XFile.fromData(bytes, name: nome, mimeType: 'text/csv')]));
}

/// Uma aba de lista (vendas, eventos, repasses, antecipações).
class _AbaLista extends StatefulWidget {
  final _Periodo periodo;
  final String titulo;
  final String vazio;
  final String nomeArquivo;
  final String? dica;
  final Future<RespostaIfood> Function(IfoodMerchantRepository r, _Periodo p) buscar;
  final List<Map<String, dynamic>> Function(dynamic dados) extrair;
  final String Function(Map<String, dynamic> m) titulo1;
  final String? Function(dynamic dados)? resumo;
  /// Campos principais de cada registro (rótulo, valor), no lugar da lista genérica.
  final List<(String, String)> Function(Map<String, dynamic> m)? linhas;
  /// Totais da lista (ex.: bruto, comissões, líquido).
  final String? Function(List<Map<String, dynamic>> itens)? totais;

  const _AbaLista({
    super.key,
    required this.periodo,
    required this.titulo,
    required this.vazio,
    required this.buscar,
    required this.extrair,
    required this.titulo1,
    required this.nomeArquivo,
    this.dica,
    this.resumo,
    this.linhas,
    this.totais,
  });

  @override
  State<_AbaLista> createState() => _AbaListaState();
}

class _AbaListaState extends State<_AbaLista> with AutomaticKeepAliveClientMixin {
  final _repo = IfoodMerchantRepository();
  RespostaIfood? _r;
  bool _carregando = false;

  @override
  bool get wantKeepAlive => true;

  Future<void> _consultar() async {
    setState(() => _carregando = true);
    final r = await widget.buscar(_repo, widget.periodo);
    if (mounted) setState(() { _r = r; _carregando = false; });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final r = _r;
    final itens = r == null || !r.ok ? const <Map<String, dynamic>>[] : widget.extrair(r.dados);
    final resumo = r != null && r.ok && widget.resumo != null ? widget.resumo!(r.dados) : null;
    final totais = r != null && r.ok && widget.totais != null && itens.isNotEmpty ? widget.totais!(itens) : null;
    return ListView(padding: const EdgeInsets.all(12), children: [
      if (widget.dica != null) Text(widget.dica!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        FilledButton.icon(
          onPressed: _carregando ? null : _consultar,
          icon: _carregando ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search),
          label: Text('Consultar ${widget.titulo.toLowerCase()} no iFood'),
        ),
        if (itens.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => _salvarCsv(context, _csv(itens),
                '${widget.nomeArquivo}-${widget.periodo.inicio}-a-${widget.periodo.fim}.csv'),
            icon: const Icon(Icons.download),
            label: const Text('Exportar CSV'),
          ),
      ]),
      if (r != null && !r.ok)
        Card(
          color: Colors.red.withValues(alpha: 0.08),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text('O iFood respondeu ${r.status}: ${r.mensagemErro ?? r.erro ?? ''}', style: const TextStyle(color: Colors.red)),
          ),
        ),
      if (r != null && r.ok) ...[
        const SizedBox(height: 8),
        Text('${itens.length} registro(s)${resumo != null ? ' · $resumo' : ''}', style: const TextStyle(fontWeight: FontWeight.w600)),
        if (totais != null)
          Card(
            color: Colors.green.withValues(alpha: 0.06),
            child: Padding(padding: const EdgeInsets.all(10), child: Text(totais, style: const TextStyle(fontSize: 13))),
          ),
        if (itens.isEmpty) Padding(padding: const EdgeInsets.all(16), child: Text(widget.vazio, style: const TextStyle(color: Colors.grey))),
        ...itens.map((m) => _CartaoRegistro(titulo: widget.titulo1(m), dados: m, linhas: widget.linhas?.call(m))),
      ],
    ]);
  }
}

/// Mostra os campos principais (valores, datas, status) e o resto expandível.
class _CartaoRegistro extends StatelessWidget {
  final String titulo;
  final Map<String, dynamic> dados;
  final List<(String, String)>? linhas;
  const _CartaoRegistro({required this.titulo, required this.dados, this.linhas});

  static final _chaveImportante = RegExp(
      r'(value|amount|gross|net|fee|commission|comiss|tax|balance|total|date|status|method|liability|responsible|transfer|impact|anticipat|bank|type|name|trigger)',
      caseSensitive: false);

  @override
  Widget build(BuildContext context) {
    final plano = _achatar(dados);
    final principais = plano.entries.where((e) => _chaveImportante.hasMatch(e.key)).take(14).toList();
    return Card(
      child: ExpansionTile(
        title: Text(titulo, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (linhas != null)
            for (final (rotulo, valor) in linhas!)
              Text('$rotulo: $valor', style: const TextStyle(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis)
          else
            for (final e in principais.take(6))
              Text('${e.key}: ${_formatar(e.key, e.value)}', style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          for (final e in plano.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 1),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 2, child: Text(e.key, style: const TextStyle(fontSize: 11, color: Colors.grey))),
                Expanded(flex: 3, child: SelectableText(_formatar(e.key, e.value), style: const TextStyle(fontSize: 12))),
              ]),
            ),
        ],
      ),
    );
  }

  static String _formatar(String chave, String valor) {
    final n = num.tryParse(valor);
    final ehDocumento = RegExp(r'(document|number|code|id$|idsaldo|mcc)', caseSensitive: false).hasMatch(chave);
    if (n != null && !ehDocumento && RegExp(r'(value|amount|fee|commission|tax|balance|total|gross|net|bag)', caseSensitive: false).hasMatch(chave)) {
      return _moeda.format(n);
    }
    return valor;
  }
}

/// Arquivo de conciliação do mês (sob demanda): pede, acompanha o status
/// (consulta de novo com espera crescente) e abre o arquivo pronto.
class _AbaConciliacao extends StatefulWidget {
  final bool homologacao;
  const _AbaConciliacao({required this.homologacao});

  @override
  State<_AbaConciliacao> createState() => _AbaConciliacaoState();
}

class _AbaConciliacaoState extends State<_AbaConciliacao> {
  final _repo = IfoodMerchantRepository();
  late String _competencia = DateFormat('yyyy-MM').format(DateTime(DateTime.now().year, DateTime.now().month - 1));
  RespostaIfood? _pedido;
  RespostaIfood? _status;
  bool _ocupado = false;
  int _tentativas = 0;
  Timer? _timer;
  List<Map<String, dynamic>> _historico = [];

  @override
  void initState() {
    super.initState();
    _carregarHistorico();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  List<String> get _meses {
    final agora = DateTime.now();
    return [for (var i = 0; i < 25; i++) DateFormat('yyyy-MM').format(DateTime(agora.year, agora.month - i))];
  }

  Future<void> _carregarHistorico() async {
    final r = await _repo.finConciliacaoListar();
    if (!mounted || !r.ok) return;
    setState(() => _historico = _lista(r.dados, 'pedidos'));
  }

  Future<void> _pedir() async {
    setState(() { _ocupado = true; _status = null; });
    final r = await _repo.finConciliacaoPedir(_competencia, homologacao: widget.homologacao);
    if (!mounted) return;
    setState(() { _pedido = r; _ocupado = false; });
    _carregarHistorico();
    if (r.ok) {
      _tentativas = 0;
      _consultarStatus();
    }
  }

  /// Consulta o status; enquanto não ficar pronto, tenta de novo com espera
  /// crescente (5 s, 10 s, 20 s, 40 s, 60 s), sem ficar consultando sem parar.
  Future<void> _consultarStatus({String? requestId, bool? homologacao}) async {
    _timer?.cancel();
    final id = requestId ?? (_pedido?.dados is Map ? _pedido!.dados['requestId'] as String? : null);
    final teste = homologacao ?? widget.homologacao;
    final r = await _repo.finConciliacaoStatus(_competencia, requestId: id, homologacao: teste);
    if (!mounted) return;
    setState(() => _status = r);
    final st = (r.dados is Map ? r.dados['status'] : null)?.toString().toUpperCase() ?? '';
    final pronto = r.dados is Map && (r.dados['filePath'] ?? '').toString().isNotEmpty;
    final falhou = st.contains('FAIL') || st.contains('ERROR');
    if (r.ok && !pronto && !falhou && _tentativas < 5) {
      final espera = [5, 10, 20, 40, 60][_tentativas++];
      _timer = Timer(Duration(seconds: espera), () => _consultarStatus(requestId: id, homologacao: teste));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _status?.dados is Map ? _status!.dados as Map : null;
    final arquivo = (s?['filePath'] ?? '').toString();
    return ListView(padding: const EdgeInsets.all(12), children: [
      const Text('Arquivo de conciliação do mês (repasses, comissões, taxas e ajustes com impacto no repasse). '
          'O iFood gera sob demanda; pode levar alguns minutos.', style: TextStyle(fontSize: 12, color: Colors.grey)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        DropdownButton<String>(
          value: _competencia,
          items: _meses.map((m) => DropdownMenuItem(value: m, child: Text('Mês $m'))).toList(),
          onChanged: (v) => setState(() { _competencia = v ?? _competencia; _pedido = null; _status = null; }),
        ),
        FilledButton.icon(
          onPressed: _ocupado ? null : _pedir,
          icon: _ocupado ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.description),
          label: const Text('Gerar arquivo do mês'),
        ),
        OutlinedButton.icon(onPressed: () { _tentativas = 0; _consultarStatus(); }, icon: const Icon(Icons.refresh), label: const Text('Ver status')),
      ]),
      if (_pedido != null && !_pedido!.ok)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('O iFood respondeu ${_pedido!.status}: ${_pedido!.mensagemErro ?? ''}', style: const TextStyle(color: Colors.red)),
        ),
      if (_pedido?.ok == true && _pedido!.dados is Map && _pedido!.dados['reaproveitado'] == true)
        const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Text('Esse mês já tinha sido pedido (409): acompanhando o pedido anterior.', style: TextStyle(fontSize: 12)),
        ),
      if (_status != null) ...[
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Status: ${s?['status'] ?? (_status!.ok ? '—' : 'erro ${_status!.status}')}', style: const TextStyle(fontWeight: FontWeight.w600)),
              if (s?['competence'] != null) Text('Competência: ${s?['competence']}'),
              if ((s?['errorMessage'] ?? '').toString().isNotEmpty) Text('Erro: ${s?['errorMessage']}', style: const TextStyle(color: Colors.red)),
              if (!_status!.ok) Text(_status!.mensagemErro ?? '', style: const TextStyle(color: Colors.red)),
              if (arquivo.isEmpty && _status!.ok && _timer?.isActive == true)
                const Text('Ainda gerando — consulto de novo sozinho.', style: TextStyle(fontSize: 12, color: Colors.grey)),
              if (arquivo.isNotEmpty) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: () => launchUrl(Uri.parse(arquivo), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.download),
                  label: const Text('Baixar arquivo de conciliação (CSV)'),
                ),
              ],
            ]),
          ),
        ),
      ],
      if (_historico.isNotEmpty) ...[
        const SizedBox(height: 16),
        const Text('Pedidos anteriores', style: TextStyle(fontWeight: FontWeight.w600)),
        ..._historico.map((h) {
          final d = (h['dados'] as Map?) ?? const {};
          final quando = DateTime.tryParse('${h['created_at']}')?.toLocal();
          return ListTile(
            dense: true,
            title: Text('Mês ${d['competencia']}${d['homologacao'] == true ? ' (teste)' : ''}'),
            subtitle: Text('${quando != null ? DateFormat('dd/MM HH:mm').format(quando) : ''} · requestId ${d['request_id']}'),
            trailing: TextButton(
              onPressed: () {
                setState(() => _competencia = '${d['competencia']}');
                _tentativas = 0;
                _consultarStatus(requestId: '${d['request_id']}', homologacao: d['homologacao'] == true);
              },
              child: const Text('Ver status'),
            ),
          );
        }),
      ],
    ]);
  }
}
