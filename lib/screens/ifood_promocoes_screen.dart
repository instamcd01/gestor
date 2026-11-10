import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../config/supabase_config.dart';
import '../models/produto.dart';
import '../repositories/ifood_merchant_repository.dart';
import '../repositories/produto_repository.dart';
import '../utils/busca_utils.dart';

/// Promoções no iFood (módulo Promotion v2.0), pela Edge Function
/// `ifood-merchant`. A promoção vive no iFood; o Gestor guarda o
/// promotionId e o último resumo lido (`marketplace_promocoes`).
///
/// Abas: Promoções (uso do dia a dia), Roteiro (os 29 cenários da sessão de
/// homologação, um botão por cenário) e Chamadas (log de cada requisição:
/// hora, endpoint, status HTTP, errorCode, promotionId, tentativa).
class IfoodPromocoesScreen extends StatelessWidget {
  const IfoodPromocoesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Promoções iFood'),
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.local_offer_outlined), text: 'Promoções'),
            Tab(icon: Icon(Icons.checklist), text: 'Roteiro'),
            Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Chamadas'),
          ]),
        ),
        body: const TabBarView(children: [_AbaPromocoes(), _AbaRoteiro(), _AbaChamadas()]),
      ),
    );
  }
}

// ── Mecânicas ────────────────────────────────────────────────────────────

enum Mecanica {
  percentual('percentageDiscounts', 'Desconto em %', 'Ex.: 10% off'),
  levePague('buyAndPayDiscounts', 'Leve X, pague Y', 'Ex.: leve 3, pague 2'),
  percentualNaUnidade('percentagePerUnitDiscounts', '% a partir da Xª unidade', 'Ex.: 50% na 2ª unidade'),
  precoFixo('fixedPriceDiscounts', 'Preço fixo', 'Ex.: sai por R\$ 19,90'),
  descontoFixo('fixedDiscounts', 'Desconto em R\$', 'Ex.: R\$ 5 off'),
  atacarejo('wholesaleDiscounts', 'Atacarejo', 'R\$ off levando a partir de X unidades');

  final String chave;
  final String rotulo;
  final String exemplo;
  const Mecanica(this.chave, this.rotulo, this.exemplo);

  bool get usaPercentual => this == percentual || this == percentualNaUnidade;
  bool get usaQtdLevar => this == levePague || this == percentualNaUnidade || this == atacarejo;
  bool get usaQtdPagar => this == levePague;
  bool get usaPrecoFixo => this == precoFixo;
  bool get usaValorDesconto => this == descontoFixo || this == atacarejo;

  static Mecanica? daChave(String? c) {
    for (final m in values) {
      if (m.chave == c) return m;
    }
    return null;
  }
}

/// RFC 3339 em UTC, sem milissegundos (o iFood aceita "2026-03-01T00:00:00Z").
String rfc3339(DateTime d) => '${DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(d.toUtc())}Z';

/// Corpo do POST/PATCH: `{"promotions": {promotionName, <mecânica>: [...]}}`.
Map<String, dynamic> corpoPromocao(String? nome, Map<Mecanica, List<Map<String, dynamic>>> itens) {
  return {
    'promotions': {
      if (nome != null) 'promotionName': nome,
      for (final m in Mecanica.values) m.chave: itens[m] ?? const [],
    },
  };
}

/// Item de uma mecânica, a partir dos parâmetros.
Map<String, dynamic> itemPromocao({
  required Mecanica mecanica,
  String? ean,
  int? sku,
  required DateTime inicio,
  required DateTime fim,
  num? percentual,
  int? qtdLevar,
  int? qtdPagar,
  num? precoFixo,
  num? valorDesconto,
  int? maxIguais,
  bool sobrescrever = false,
}) {
  return {
    if (ean != null) 'ean': ean,
    if (sku != null) 'sku': sku,
    'initialDate': rfc3339(inicio),
    'finalDate': rfc3339(fim),
    if (mecanica.usaPercentual && percentual != null) 'percentage': percentual,
    if (mecanica.usaQtdLevar && qtdLevar != null) 'quantityToBuy': qtdLevar,
    if (mecanica.usaQtdPagar && qtdPagar != null) 'quantityToPay': qtdPagar,
    if (mecanica.usaPrecoFixo && precoFixo != null) 'fixedPrice': precoFixo,
    if (mecanica.usaValorDesconto && valorDesconto != null) 'discountValue': valorDesconto,
    if (maxIguais != null) 'maxEqualItems': maxIguais,
    if (sobrescrever) 'allowOverride': true,
  };
}

final _eanValido = RegExp(r'^\d{5,13}$');

/// Validação local antes de enviar (requisito do iFood). Os cenários do
/// roteiro de homologação mandam payload inválido de propósito e não passam
/// por aqui.
String? validarPromocao({
  required String nome,
  required Mecanica mecanica,
  required List<String> eans,
  required DateTime inicio,
  required DateTime fim,
  num? percentual,
  int? qtdLevar,
  int? qtdPagar,
  num? precoFixo,
  num? valorDesconto,
  int? maxIguais,
}) {
  if (nome.trim().isEmpty) return 'Dê um nome à promoção.';
  if (eans.isEmpty) return 'Escolha pelo menos um produto.';
  final invalidos = eans.where((e) => !_eanValido.hasMatch(e)).toList();
  if (invalidos.isNotEmpty) return 'Código de barras inválido para o iFood (5 a 13 dígitos): ${invalidos.join(', ')}';
  if (eans.toSet().length != eans.length) return 'O mesmo produto está duas vezes.';
  if (fim.isBefore(inicio)) return 'A data final é antes da inicial.';
  if (mecanica.usaPercentual && (percentual == null || percentual < 0.1 || percentual > 100)) {
    return 'O percentual precisa estar entre 0,1 e 100.';
  }
  if (mecanica.usaQtdLevar && (qtdLevar == null || qtdLevar < 2)) return 'A quantidade para levar precisa ser 2 ou mais.';
  if (mecanica.usaQtdPagar && (qtdPagar == null || qtdPagar < 1 || qtdPagar >= (qtdLevar ?? 0))) {
    return 'A quantidade paga precisa ser pelo menos 1 e menor que a levada.';
  }
  if (mecanica.usaPrecoFixo) {
    if (precoFixo == null || precoFixo <= 0) return 'O preço fixo precisa ser maior que zero.';
    if ((precoFixo * 100).roundToDouble() != precoFixo * 100) return 'O preço fixo aceita no máximo 2 casas decimais.';
  }
  if (mecanica.usaValorDesconto && (valorDesconto == null || valorDesconto <= 0)) {
    return 'O valor do desconto precisa ser maior que zero.';
  }
  if (maxIguais != null && maxIguais <= 0) return 'O máximo de itens iguais precisa ser maior que zero.';
  if (mecanica == Mecanica.atacarejo && maxIguais != null && maxIguais < (qtdLevar ?? 0)) {
    return 'No atacarejo, o máximo de itens iguais não pode ser menor que a quantidade mínima.';
  }
  return null;
}

// ── Peças comuns ─────────────────────────────────────────────────────────

String _json(dynamic d) {
  try {
    return const JsonEncoder.withIndent('  ').convert(d);
  } catch (_) {
    return '$d';
  }
}

/// summary.inProgress da resposta de GET /promotions/{id}.
num _emProcessamento(RespostaIfood r, {num seNaoSouber = 0}) {
  final d = r.dados;
  if (d is! Map) return seNaoSouber;
  final s = d['summary'];
  if (s is! Map) return seNaoSouber;
  return (s['inProgress'] as num?) ?? seNaoSouber;
}

Color _corStatus(int s) => s >= 200 && s < 300 ? (s == 206 ? Colors.orange : Colors.green) : Colors.red;

/// Resultado de uma chamada: status, errorCode, mensagem e corpo completo.
class _RespostaCard extends StatelessWidget {
  final RespostaIfood r;
  final String? esperado;
  final bool? passou;
  const _RespostaCard(this.r, {this.esperado, this.passou});

  @override
  Widget build(BuildContext context) {
    final cod = r.codigoErro;
    final msg = r.ok && r.status != 206 ? null : r.mensagemErro;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(color: _corStatus(r.status).withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text('HTTP ${r.status}', style: TextStyle(fontWeight: FontWeight.bold, color: _corStatus(r.status))),
          if (cod != null) Text(cod, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          if (r.tokenRenovado) const Chip(label: Text('token renovado', style: TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact),
          if ((r.tentativas ?? 1) > 1) Text('${r.tentativas} tentativas', style: const TextStyle(fontSize: 12)),
          if (r.requisicoes != null) Text('${r.requisicoes} requisições', style: const TextStyle(fontSize: 12)),
          if (passou != null)
            Icon(passou! ? Icons.check_circle : Icons.cancel, color: passou! ? Colors.green : Colors.red, size: 18),
        ]),
        if (esperado != null) Text('Esperado: $esperado', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        if (msg != null && msg.isNotEmpty) Text(msg, style: const TextStyle(fontSize: 12)),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Resposta completa', style: TextStyle(fontSize: 12)),
          children: [
            SelectableText(_json(r.dados), style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          ],
        ),
      ]),
    );
  }
}

Future<void> _mostrarResposta(BuildContext context, String titulo, RespostaIfood r) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: SingleChildScrollView(child: _RespostaCard(r)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Fechar'))],
    ),
  );
}

/// Produtos com código de barras aceito pelo iFood (5 a 13 dígitos).
Future<List<Produto>> _produtosComEan() async {
  final todos = await ProdutoRepository().listar();
  return todos.where((p) => p.ativo && _eanValido.hasMatch(p.codigoBarras)).toList()
    ..sort((a, b) => a.nome.compareTo(b.nome));
}

// ── Aba Promoções ────────────────────────────────────────────────────────

class _AbaPromocoes extends StatefulWidget {
  const _AbaPromocoes();

  @override
  State<_AbaPromocoes> createState() => _AbaPromocoesState();
}

class _AbaPromocoesState extends State<_AbaPromocoes> {
  final _repo = IfoodMerchantRepository();
  List<Map<String, dynamic>> _promocoes = [];
  bool _carregando = true;
  bool _sincronizando = false;
  String? _filtro; // ACTIVE / INACTIVE / null
  bool _mostrarHomologacao = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final data = await supabase
          .from('marketplace_promocoes')
          .select()
          .order('criado_em', ascending: false)
          .limit(200);
      if (mounted) setState(() { _promocoes = (data as List).cast<Map<String, dynamic>>(); _carregando = false; });
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  /// GET /promotions (filtro de status + paginação) e atualiza o status local.
  Future<void> _sincronizar() async {
    setState(() => _sincronizando = true);
    var pagina = 1;
    RespostaIfood r;
    do {
      r = await _repo.promoListar(page: pagina, size: 100, status: _filtro);
      pagina++;
    } while (r.ok && r.dados is Map && (r.dados['totalPages'] as num? ?? 0) >= pagina && pagina <= 10);
    await _carregar();
    if (!mounted) return;
    setState(() => _sincronizando = false);
    if (!r.ok) _mostrarResposta(context, 'Não deu pra listar no iFood', r);
  }

  @override
  Widget build(BuildContext context) {
    final lista = _promocoes.where((p) {
      if (!_mostrarHomologacao && p['homologacao'] == true) return false;
      if (_filtro != null && p['status'] != _filtro) return false;
      return true;
    }).toList();
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final criou = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const _FormPromocaoScreen()));
          if (criou == true) _carregar();
        },
        icon: const Icon(Icons.add),
        label: const Text('Nova promoção'),
      ),
      body: RefreshIndicator(
        onRefresh: _carregar,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
          children: [
            Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
              ChoiceChip(label: const Text('Todas'), selected: _filtro == null, onSelected: (_) => setState(() => _filtro = null)),
              ChoiceChip(label: const Text('Ativas'), selected: _filtro == 'ACTIVE', onSelected: (_) => setState(() => _filtro = 'ACTIVE')),
              ChoiceChip(label: const Text('Encerradas'), selected: _filtro == 'INACTIVE', onSelected: (_) => setState(() => _filtro = 'INACTIVE')),
              FilterChip(
                label: const Text('Testes de homologação'),
                selected: _mostrarHomologacao,
                onSelected: (v) => setState(() => _mostrarHomologacao = v),
              ),
              OutlinedButton.icon(
                onPressed: _sincronizando ? null : _sincronizar,
                icon: _sincronizando
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.sync),
                label: const Text('Atualizar do iFood'),
              ),
            ]),
            const SizedBox(height: 8),
            if (_carregando)
              const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
            else if (lista.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Nenhuma promoção ainda. Toque em "Nova promoção" pra criar a primeira no iFood.',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              )
            else
              ...lista.map((p) => _cardPromocao(p)),
          ],
        ),
      ),
    );
  }

  Widget _cardPromocao(Map<String, dynamic> p) {
    final resumo = (p['resumo'] as Map?) ?? const {};
    final ativa = p['status'] != 'INACTIVE';
    final emProc = p['em_processamento'] == true;
    return Card(
      child: ListTile(
        leading: Icon(Icons.local_offer, color: ativa ? Colors.red : Colors.grey),
        title: Text(p['nome']?.toString() ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Text([
          ativa ? 'Ativa' : 'Encerrada',
          if (resumo['totalRequested'] != null) '${resumo['successCount'] ?? 0}/${resumo['totalRequested']} itens ok',
          if ((resumo['errorCount'] as num? ?? 0) > 0) '${resumo['errorCount']} com erro',
          if (emProc) 'processando…',
          if (p['homologacao'] == true) 'teste',
        ].join(' · ')),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          await Navigator.push(context, MaterialPageRoute(builder: (_) => _PromocaoDetalheScreen(promocao: p)));
          _carregar();
        },
      ),
    );
  }
}

// ── Detalhe da promoção ──────────────────────────────────────────────────

class _PromocaoDetalheScreen extends StatefulWidget {
  final Map<String, dynamic> promocao;
  const _PromocaoDetalheScreen({required this.promocao});

  @override
  State<_PromocaoDetalheScreen> createState() => _PromocaoDetalheScreenState();
}

class _PromocaoDetalheScreenState extends State<_PromocaoDetalheScreen> {
  final _repo = IfoodMerchantRepository();
  RespostaIfood? _consulta;
  RespostaIfood? _itens;
  RespostaIfood? _acao;
  Timer? _poll;
  int _consultas = 0;
  bool _ocupado = false;
  bool _encerrouAgora = false;

  String get _id => widget.promocao['promotion_id'] as String;
  String get _nome => (_consulta?.dados is Map ? _consulta!.dados['promotionName'] : null)?.toString() ?? widget.promocao['nome']?.toString() ?? '';

  @override
  void initState() {
    super.initState();
    _consultar();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// GET /promotions/{id}. Enquanto houver item em processamento
  /// (summary.inProgress > 0) consulta de novo a cada 3 s, sem assumir
  /// sucesso, por até ~2 min.
  Future<void> _consultar({bool manual = false}) async {
    if (manual) _consultas = 0;
    final r = await _repo.promoConsultar(_id);
    if (!mounted) return;
    setState(() => _consulta = r);
    _consultas++;
    _poll?.cancel();
    final s = r.dados is Map ? (r.dados['summary'] as Map?) : null;
    if (r.ok && (s?['inProgress'] as num? ?? 0) > 0 && _consultas < 40) {
      _poll = Timer(const Duration(seconds: 3), _consultar);
    }
  }

  Future<void> _verItens() async {
    setState(() => _ocupado = true);
    final r = await _repo.promoItens(_id);
    if (mounted) setState(() { _itens = r; _ocupado = false; });
  }

  Future<void> _encerrar() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Encerrar promoção'),
        content: const Text('Todos os itens saem da promoção no iFood e ela fica encerrada. Não dá pra reativar — pra voltar, crie outra.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Encerrar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _ocupado = true);
    final r = await _repo.promoRemoverItens(_id);
    if (!mounted) return;
    setState(() { _acao = r; _ocupado = false; _encerrouAgora = r.ok; });
    _consultar(manual: true);
  }

  Future<void> _removerItem(Map item) async {
    final ean = item['ean']?.toString();
    final sku = item['sku']?.toString();
    setState(() => _ocupado = true);
    final r = await _repo.promoRemoverItens(_id, [
      if (ean != null && ean.isNotEmpty) {'ean': ean} else {'sku': sku},
    ]);
    if (!mounted) return;
    setState(() { _acao = r; _ocupado = false; });
    _verItens();
    _consultar(manual: true);
  }

  Future<void> _pedidos() async {
    setState(() => _ocupado = true);
    final agora = DateTime.now();
    final r = await _repo.promoPedidos(_id,
        startDate: rfc3339(agora.subtract(const Duration(days: 30))), endDate: rfc3339(agora));
    if (!mounted) return;
    setState(() => _ocupado = false);
    _mostrarResposta(context, 'Pedidos com esta promoção (30 dias)', r);
  }

  @override
  Widget build(BuildContext context) {
    final c = _consulta;
    final s = c?.dados is Map ? (c!.dados['summary'] as Map?) : null;
    final erros = c?.dados is Map ? (c!.dados['errors'] as List?) : null;
    final emProc = (s?['inProgress'] as num? ?? 0) > 0;
    final encerrada = widget.promocao['status'] == 'INACTIVE' || _encerrouAgora;
    return Scaffold(
      appBar: AppBar(title: const Text('Promoção')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Text(_nome, style: Theme.of(context).textTheme.titleMedium),
        SelectableText('promotionId: $_id', style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Expanded(child: Text('Processamento no iFood', style: TextStyle(fontWeight: FontWeight.w600))),
                if (emProc) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                IconButton(icon: const Icon(Icons.refresh), tooltip: 'Consultar agora', onPressed: () => _consultar(manual: true)),
              ]),
              if (c == null)
                const Text('Consultando…')
              else if (!c.ok)
                _RespostaCard(c)
              else ...[
                Text('Itens enviados: ${s?['totalRequested'] ?? '-'}'),
                Text('Aplicados: ${s?['successCount'] ?? '-'}', style: const TextStyle(color: Colors.green)),
                Text('Com erro: ${s?['errorCount'] ?? '-'}', style: TextStyle(color: (s?['errorCount'] as num? ?? 0) > 0 ? Colors.red : null)),
                Text('Em processamento: ${s?['inProgress'] ?? '-'}'),
                if (s?['canceledCount'] != null) Text('Cancelados: ${s?['canceledCount']}'),
                if (emProc) const Text('Ainda processando — consulto de novo a cada 3 s.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                if (erros != null && erros.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  const Text('Erros do iFood', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.red)),
                  ...erros.whereType<Map>().map((e) => Text(
                        '• ${e['errorCode'] ?? ''}: ${e['errorMessage'] ?? e['error'] ?? ''}'
                        '${(e['eans'] as List?)?.isNotEmpty == true ? ' (EAN ${(e['eans'] as List).join(', ')})' : ''}',
                        style: const TextStyle(fontSize: 12),
                      )),
                  const Text('Corrija em "Adicionar ou corrigir itens": reenviar o mesmo produto substitui o item.',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ],
            ]),
          ),
        ),
        if (_acao != null) _RespostaCard(_acao!),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(onPressed: _ocupado ? null : _verItens, icon: const Icon(Icons.list), label: const Text('Ver itens')),
          if (!encerrada)
            OutlinedButton.icon(
              onPressed: _ocupado
                  ? null
                  : () async {
                      final mudou = await Navigator.push<bool>(context,
                          MaterialPageRoute(builder: (_) => _FormPromocaoScreen(promotionId: _id, nomeAtual: _nome)));
                      if (mudou == true) _consultar(manual: true);
                    },
              icon: const Icon(Icons.edit),
              label: const Text('Adicionar ou corrigir itens'),
            ),
          OutlinedButton.icon(onPressed: _ocupado ? null : _pedidos, icon: const Icon(Icons.receipt), label: const Text('Pedidos')),
          if (!encerrada)
            OutlinedButton.icon(
              onPressed: _ocupado ? null : _encerrar,
              icon: const Icon(Icons.stop_circle_outlined, color: Colors.red),
              label: const Text('Encerrar promoção'),
            ),
        ]),
        if (_itens != null) ..._listaItens(_itens!, encerrada),
      ]),
    );
  }

  List<Widget> _listaItens(RespostaIfood r, bool encerrada) {
    if (!r.ok) return [_RespostaCard(r)];
    final itens = (r.dados is Map ? (r.dados['items'] as List?) : null) ?? const [];
    return [
      const SizedBox(height: 12),
      Text('Itens (${itens.length})', style: const TextStyle(fontWeight: FontWeight.w600)),
      ...itens.whereType<Map>().map((i) {
        final status = i['status']?.toString() ?? '';
        final cor = switch (status) {
          'COMPLETED' => Colors.green,
          'FAILED' => Colors.red,
          'CANCELED' => Colors.grey,
          _ => Colors.orange,
        };
        return ListTile(
          dense: true,
          title: Text('${i['ean'] ?? i['sku'] ?? '-'} · ${i['mechanicType'] ?? ''}'),
          subtitle: Text([
            status,
            if (i['reason'] != null && '${i['reason']}'.isNotEmpty) '${i['reason']}',
            if (i['itemEndDate'] != null) 'até ${DateFormat('dd/MM HH:mm').format(DateTime.parse('${i['itemEndDate']}').toLocal())}',
          ].join(' · ')),
          leading: Icon(Icons.circle, size: 12, color: cor),
          trailing: !encerrada && status != 'CANCELED'
              ? IconButton(icon: const Icon(Icons.remove_circle_outline), tooltip: 'Tirar da promoção', onPressed: _ocupado ? null : () => _removerItem(i))
              : null,
        );
      }),
    ];
  }
}

// ── Criar / editar ───────────────────────────────────────────────────────

class _FormPromocaoScreen extends StatefulWidget {
  /// Com [promotionId]: PATCH (adiciona itens ou corrige; mesmo EAN substitui).
  final String? promotionId;
  final String? nomeAtual;
  const _FormPromocaoScreen({this.promotionId, this.nomeAtual});

  @override
  State<_FormPromocaoScreen> createState() => _FormPromocaoScreenState();
}

class _FormPromocaoScreenState extends State<_FormPromocaoScreen> {
  final _repo = IfoodMerchantRepository();
  late final _nome = TextEditingController(text: widget.nomeAtual ?? '');
  final _percentual = TextEditingController();
  final _qtdLevar = TextEditingController(text: '2');
  final _qtdPagar = TextEditingController(text: '1');
  final _precoFixo = TextEditingController();
  final _valorDesconto = TextEditingController();
  final _maxIguais = TextEditingController();
  Mecanica _mecanica = Mecanica.percentual;
  DateTime _inicio = DateTime.now();
  DateTime _fim = DateTime.now().add(const Duration(days: 7));
  bool _sobrescrever = false;
  final List<Produto> _produtos = [];
  List<Produto> _catalogo = [];
  bool _enviando = false;
  RespostaIfood? _resposta;

  bool get _editando => widget.promotionId != null;

  num? _num(TextEditingController c) => num.tryParse(c.text.trim().replaceAll(',', '.'));
  int? _int(TextEditingController c) => int.tryParse(c.text.trim());

  Future<void> _escolherProdutos() async {
    if (_catalogo.isEmpty) {
      try {
        _catalogo = await _produtosComEan();
      } catch (_) {}
    }
    if (!mounted) return;
    final busca = TextEditingController();
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) {
        final t = busca.text.trim();
        final filtrados = (t.isEmpty ? _catalogo : _catalogo.where((p) => contemTodasPalavras(p.nome, t) || p.codigoBarras.contains(t))).take(40).toList();
        return AlertDialog(
          title: const Text('Produtos da promoção'),
          content: SizedBox(
            width: double.maxFinite,
            height: 420,
            child: Column(children: [
              TextField(controller: busca, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Nome ou código de barras'), onChanged: (_) => setD(() {})),
              Expanded(
                child: ListView(children: filtrados.map((p) {
                  final marcado = _produtos.any((x) => x.id == p.id);
                  return CheckboxListTile(
                    dense: true,
                    value: marcado,
                    title: Text(p.nome, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${p.codigoBarras} · R\$ ${(p.precoIfood ?? p.preco).toStringAsFixed(2)}'),
                    onChanged: (v) {
                      setD(() {});
                      setState(() => v == true ? _produtos.add(p) : _produtos.removeWhere((x) => x.id == p.id));
                    },
                  );
                }).toList()),
              ),
            ]),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Pronto'))],
        );
      }),
    );
  }

  Future<void> _escolherData(bool inicio) async {
    final atual = inicio ? _inicio : _fim;
    final dia = await showDatePicker(
      context: context,
      initialDate: atual,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 366)),
    );
    if (dia == null || !mounted) return;
    final hora = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(atual));
    final d = DateTime(dia.year, dia.month, dia.day, hora?.hour ?? atual.hour, hora?.minute ?? atual.minute);
    setState(() => inicio ? _inicio = d : _fim = d);
  }

  Future<void> _enviar() async {
    final eans = _produtos.map((p) => p.codigoBarras).toList();
    final erro = validarPromocao(
      nome: _nome.text,
      mecanica: _mecanica,
      eans: eans,
      inicio: _inicio,
      fim: _fim,
      percentual: _num(_percentual),
      qtdLevar: _int(_qtdLevar),
      qtdPagar: _int(_qtdPagar),
      precoFixo: _num(_precoFixo),
      valorDesconto: _num(_valorDesconto),
      maxIguais: _maxIguais.text.trim().isEmpty ? null : _int(_maxIguais),
    );
    if (erro != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro)));
      return;
    }
    final itens = eans
        .map((e) => itemPromocao(
              mecanica: _mecanica,
              ean: e,
              inicio: _inicio,
              fim: _fim,
              percentual: _num(_percentual),
              qtdLevar: _int(_qtdLevar),
              qtdPagar: _int(_qtdPagar),
              precoFixo: _num(_precoFixo),
              valorDesconto: _num(_valorDesconto),
              maxIguais: _maxIguais.text.trim().isEmpty ? null : _int(_maxIguais),
              sobrescrever: _sobrescrever,
            ))
        .toList();
    final corpo = corpoPromocao(_nome.text.trim(), {_mecanica: itens});
    setState(() => _enviando = true);
    final r = _editando ? await _repo.promoEditar(widget.promotionId!, corpo) : await _repo.promoCriar(corpo);
    if (!mounted) return;
    setState(() { _enviando = false; _resposta = r; });
    if (r.ok && r.status != 206) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_editando ? 'Itens enviados ao iFood.' : 'Promoção criada no iFood. Acompanhe o processamento na lista.')));
      Navigator.pop(context, true);
    }
    // 206 (parte aceita, parte com erro) ou erro: fica na tela mostrando o motivo.
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm');
    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Adicionar ou corrigir itens' : 'Nova promoção no iFood')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        TextField(controller: _nome, enabled: !_editando, decoration: const InputDecoration(labelText: 'Nome da promoção')),
        const SizedBox(height: 12),
        DropdownButtonFormField<Mecanica>(
          initialValue: _mecanica,
          decoration: const InputDecoration(labelText: 'Tipo de desconto'),
          items: Mecanica.values.map((m) => DropdownMenuItem(value: m, child: Text(m.rotulo))).toList(),
          onChanged: (m) => setState(() => _mecanica = m ?? _mecanica),
        ),
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(_mecanica.exemplo, style: const TextStyle(fontSize: 12, color: Colors.grey))),
        if (_mecanica.usaPercentual)
          TextField(controller: _percentual, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Desconto (%)')),
        if (_mecanica.usaQtdLevar)
          TextField(
            controller: _qtdLevar,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: _mecanica == Mecanica.levePague ? 'Leve (unidades)' : _mecanica == Mecanica.atacarejo ? 'A partir de (unidades)' : 'Desconto a partir da unidade nº'),
          ),
        if (_mecanica.usaQtdPagar)
          TextField(controller: _qtdPagar, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Pague (unidades)')),
        if (_mecanica.usaPrecoFixo)
          TextField(controller: _precoFixo, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Preço na promoção (R\$)')),
        if (_mecanica.usaValorDesconto)
          TextField(controller: _valorDesconto, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Desconto por unidade (R\$)')),
        TextField(
          controller: _maxIguais,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Máximo de unidades iguais por pedido (opcional)'),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton(onPressed: () => _escolherData(true), child: Text('Início: ${fmt.format(_inicio)}'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(onPressed: () => _escolherData(false), child: Text('Fim: ${fmt.format(_fim)}'))),
        ]),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _sobrescrever,
          onChanged: (v) => setState(() => _sobrescrever = v),
          title: const Text('Substituir outra promoção do mesmo produto nessas datas'),
          subtitle: const Text('Sem isso, o iFood recusa o produto que já estiver em promoção no período.', style: TextStyle(fontSize: 12)),
        ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text('Produtos (${_produtos.length})', style: const TextStyle(fontWeight: FontWeight.w600))),
          TextButton.icon(onPressed: _escolherProdutos, icon: const Icon(Icons.add), label: const Text('Escolher')),
        ]),
        ..._produtos.map((p) => ListTile(
              dense: true,
              title: Text(p.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(p.codigoBarras),
              trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _produtos.remove(p))),
            )),
        if (_resposta != null) _RespostaCard(_resposta!),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _enviando ? null : _enviar,
          style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
          child: _enviando
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_editando ? 'Enviar itens' : 'Criar promoção no iFood'),
        ),
      ]),
    );
  }
}

// ── Roteiro de homologação ───────────────────────────────────────────────

class _Cenario {
  final int numero;
  final String grupo;
  final String titulo;
  final String esperado;
  final int statusEsperado;
  final String? codigoEsperado;
  final Future<RespostaIfood> Function() executar;
  final bool Function(RespostaIfood r)? confere;
  _Cenario(this.numero, this.grupo, this.titulo, this.esperado, this.statusEsperado, this.executar,
      {this.codigoEsperado, this.confere});
}

class _AbaRoteiro extends StatefulWidget {
  const _AbaRoteiro();

  @override
  State<_AbaRoteiro> createState() => _AbaRoteiroState();
}

class _AbaRoteiroState extends State<_AbaRoteiro> {
  final _repo = IfoodMerchantRepository();
  final _outroMerchant = TextEditingController();
  final _merchantSemStoreType = TextEditingController();
  final Map<int, RespostaIfood> _resultados = {};
  final Set<int> _rodando = {};
  List<String> _eans = [];
  int? _skuNumerico;
  String? _carregandoErro;

  // Estado entre cenários
  String? _promo1; // criada no cenário 1
  String? _nome1;
  String? _promo6; // criada no cenário 6 (parcial)
  Map<String, dynamic>? _itemInvalido6;
  final _sufixo = DateFormat('ddMM HHmmss').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _carregarEans();
  }

  Future<void> _carregarEans() async {
    try {
      final ps = await _produtosComEan();
      final eans = ps.map((p) => p.codigoBarras).toSet().take(4).toList();
      final sku = ps.map((p) => int.tryParse(p.sku ?? '')).whereType<int>().firstOrNull;
      if (mounted) setState(() { _eans = eans; _skuNumerico = sku; });
    } catch (e) {
      if (mounted) setState(() => _carregandoErro = '$e');
    }
  }

  DateTime get _ini => DateTime.now().add(const Duration(minutes: 5));
  DateTime get _fim => DateTime.now().add(const Duration(days: 7));
  String _uuid() {
    final t = DateTime.now().microsecondsSinceEpoch.toRadixString(16).padLeft(12, '0');
    return '00000000-0000-4000-8000-${t.substring(t.length - 12)}';
  }

  Map<String, dynamic> _pct(String ean, num p) => itemPromocao(mecanica: Mecanica.percentual, ean: ean, inicio: _ini, fim: _fim, percentual: p);

  String? _precisa({bool p1 = false, bool p6 = false, int eans = 2}) {
    if (_eans.length < eans) return 'Precisa de $eans produtos com código de barras na loja.';
    if (p1 && _promo1 == null) return 'Rode antes o cenário 1.';
    if (p6 && _promo6 == null) return 'Rode antes o cenário 6.';
    return null;
  }

  List<_Cenario> get _cenarios {
    final e = _eans;
    String e0() => e[0];
    String e1() => e[1];
    String e2() => e.length > 2 ? e[2] : e[0];
    return [
      _Cenario(1, 'Criação', 'POST com percentageDiscounts válido', '201 + promotionId', 201, () async {
        final nome = 'Homologação $_sufixo';
        final r = await _repo.promoCriar(corpoPromocao(nome, {Mecanica.percentual: [_pct(e0(), 10)]}), homologacao: true);
        final id = r.dados is Map ? r.dados['promotionId'] as String? : null;
        if (id != null) { _promo1 = id; _nome1 = nome; }
        return r;
      }),
      _Cenario(2, 'Criação', 'buyAndPayDiscounts com quantityToBuy = 1', '400 INVALID_PROGRESSIVE_QUANTITY', 400,
          codigoEsperado: 'INVALID_PROGRESSIVE_QUANTITY', () => _repo.promoCriar(corpoPromocao('Hom $_sufixo leve1', {
                Mecanica.levePague: [itemPromocao(mecanica: Mecanica.levePague, ean: e0(), inicio: _ini, fim: _fim, qtdLevar: 1, qtdPagar: 1)],
              }), homologacao: true)),
      _Cenario(3, 'Criação', 'POST sem promotionName', '400 REQUIRED_FIELD', 400, codigoEsperado: 'REQUIRED_FIELD',
          () => _repo.promoCriar(corpoPromocao(null, {Mecanica.percentual: [_pct(e0(), 10)]}), homologacao: true)),
      _Cenario(4, 'Criação', 'POST sem nenhum desconto', '400 REQUIRED_FIELD', 400, codigoEsperado: 'REQUIRED_FIELD',
          () => _repo.promoCriar(corpoPromocao('Hom $_sufixo vazio', {}), homologacao: true)),
      _Cenario(5, 'Criação', 'POST com EAN repetido na requisição', '400 DUPLICATE_EAN', 400, codigoEsperado: 'DUPLICATE_EAN',
          () => _repo.promoCriar(corpoPromocao('Hom $_sufixo dup', {Mecanica.percentual: [_pct(e0(), 10), _pct(e0(), 12)]}), homologacao: true)),
      _Cenario(6, 'Criação', '1 item válido + 1 inválido', '206 com errors[] só do item rejeitado', 206, () async {
        final invalido = _pct(e2(), 150);
        final r = await _repo.promoCriar(corpoPromocao('Hom $_sufixo parcial', {Mecanica.percentual: [_pct(e1(), 10), invalido]}), homologacao: true);
        final id = r.dados is Map ? r.dados['promotionId'] as String? : null;
        if (id != null) { _promo6 = id; _itemInvalido6 = invalido; }
        return r;
      }),
      _Cenario(7, 'Criação', 'POST com promotionName que já existe', '409', 409,
          () => _repo.promoCriar(corpoPromocao(_nome1, {Mecanica.percentual: [_pct(e1(), 11)]}), homologacao: true)),
      _Cenario(8, 'Criação', 'POST para merchant inexistente', '422 MERCHANT_NOT_FOUND (só com a flag do iFood ligada)', 422,
          codigoEsperado: 'MERCHANT_NOT_FOUND',
          () => _repo.promoCriar(corpoPromocao('Hom $_sufixo merchant', {Mecanica.percentual: [_pct(e0(), 10)]}), merchantId: _uuid(), homologacao: true)),
      _Cenario(9, 'Criação', 'POST para merchant sem storeType', '422 MERCHANT_ATTRIBUTES_MISSING_STORE_TYPE (só com a flag)', 422,
          codigoEsperado: 'MERCHANT_ATTRIBUTES_MISSING_STORE_TYPE',
          () => _repo.promoCriar(corpoPromocao('Hom $_sufixo storetype', {Mecanica.percentual: [_pct(e0(), 10)]}),
              merchantId: _merchantSemStoreType.text.trim().isEmpty ? _uuid() : _merchantSemStoreType.text.trim(), homologacao: true)),
      _Cenario(10, 'Criação', 'percentagePerUnitDiscounts com quantityToBuy = 1', '400 INVALID_QUANTITY', 400, codigoEsperado: 'INVALID_QUANTITY',
          () => _repo.promoCriar(corpoPromocao('Hom $_sufixo ppu', {
                Mecanica.percentualNaUnidade: [itemPromocao(mecanica: Mecanica.percentualNaUnidade, ean: e0(), inicio: _ini, fim: _fim, percentual: 50, qtdLevar: 1)],
              }), homologacao: true)),
      _Cenario(11, 'Criação', 'fixedPriceDiscounts com 3 casas decimais', '400 INVALID_FIXED_PRICE', 400, codigoEsperado: 'INVALID_FIXED_PRICE',
          () => _repo.promoCriar(corpoPromocao('Hom $_sufixo fixo', {
                Mecanica.precoFixo: [itemPromocao(mecanica: Mecanica.precoFixo, ean: e0(), inicio: _ini, fim: _fim, precoFixo: 9.999)],
              }), homologacao: true)),
      _Cenario(12, 'Criação', 'fixedDiscounts com discountValue = 0', '400 INVALID_DISCOUNT_VALUE', 400, codigoEsperado: 'INVALID_DISCOUNT_VALUE',
          () => _repo.promoCriar(corpoPromocao('Hom $_sufixo desc0', {
                Mecanica.descontoFixo: [itemPromocao(mecanica: Mecanica.descontoFixo, ean: e0(), inicio: _ini, fim: _fim, valorDesconto: 0)],
              }), homologacao: true)),
      _Cenario(13, 'Criação', 'wholesaleDiscounts com maxEqualItems < quantityToBuy', '400 INVALID_MAX_EQUAL_ITEMS', 400,
          codigoEsperado: 'INVALID_MAX_EQUAL_ITEMS',
          () => _repo.promoCriar(corpoPromocao('Hom $_sufixo atacarejo', {
                Mecanica.atacarejo: [itemPromocao(mecanica: Mecanica.atacarejo, ean: e0(), inicio: _ini, fim: _fim, valorDesconto: 2, qtdLevar: 3, maxIguais: 2)],
              }), homologacao: true)),
      _Cenario(14, 'Criação', 'POST com sku (sem ean)', '201 (o item é validado no catálogo depois)', 201,
          () => _repo.promoCriar(corpoPromocao('Hom $_sufixo sku', {
                Mecanica.percentual: [itemPromocao(mecanica: Mecanica.percentual, sku: _skuNumerico ?? 1, inicio: _ini, fim: _fim, percentual: 10)],
              }), homologacao: true)),
      _Cenario(140, 'Criação', 'POST sem ean nem sku', '400 EAN_OR_SKU_REQUIRED', 400, codigoEsperado: 'EAN_OR_SKU_REQUIRED',
          () => _repo.promoCriar(corpoPromocao('Hom $_sufixo semid', {
                Mecanica.percentual: [itemPromocao(mecanica: Mecanica.percentual, inicio: _ini, fim: _fim, percentual: 10)],
              }), homologacao: true)),
      _Cenario(15, 'Consulta', 'GET da promoção do cenário 1, repetindo até não ter item em processamento', '200 com summary; inProgress = 0 no fim', 200,
          () async {
        RespostaIfood r;
        var n = 0;
        do {
          if (n > 0) await Future.delayed(const Duration(seconds: 3));
          r = await _repo.promoConsultar(_promo1!);
          n++;
          if (mounted) setState(() => _resultados[15] = r);
        } while (r.ok && _emProcessamento(r) > 0 && n < 20);
        return r;
      }, confere: (r) => r.status == 200 && _emProcessamento(r, seNaoSouber: 1) == 0),
      _Cenario(16, 'Consulta', 'GET com promotionId inexistente', '404', 404, () => _repo.promoConsultar(_uuid())),
      _Cenario(17, 'Consulta', 'GET de promoção de outro merchant', '403', 403,
          () => _repo.promoConsultar(_promo1 ?? _uuid(), merchantId: _outroMerchant.text.trim().isEmpty ? _uuid() : _outroMerchant.text.trim())),
      _Cenario(18, 'Listagem', 'GET /promotions com size = 101', '400 INVALID_PAGING_PARAMETERS', 400,
          codigoEsperado: 'INVALID_PAGING_PARAMETERS', () => _repo.promoListar(size: 101)),
      _Cenario(19, 'Listagem', 'GET /promotions com page = 0', '400 INVALID_PAGING_PARAMETERS', 400,
          codigoEsperado: 'INVALID_PAGING_PARAMETERS', () => _repo.promoListar(page: 0)),
      _Cenario(20, 'Listagem', 'GET /promotions com status inválido', '400', 400, () => _repo.promoListar(status: 'QUALQUER')),
      _Cenario(21, 'Listagem', 'GET /promotions com status = INACTIVE', '200 só com promoções INACTIVE', 200,
          () => _repo.promoListar(status: 'INACTIVE', page: 1, size: 25),
          confere: (r) => r.status == 200 && ((r.dados is Map ? r.dados['items'] as List? : null) ?? const [])
              .whereType<Map>().every((i) => i['status'] == 'INACTIVE')),
      _Cenario(22, 'Edição', 'PATCH com o item rejeitado no cenário 6, corrigido', '200 (mesmo EAN substitui o item)', 200, () {
        final corrigido = Map<String, dynamic>.from(_itemInvalido6 ?? _pct(e2(), 15))..['percentage'] = 15;
        return _repo.promoEditar(_promo6!, corpoPromocao('Hom $_sufixo parcial', {Mecanica.percentual: [corrigido]}));
      }),
      _Cenario(23, 'Edição', 'PATCH com 1 item válido + 1 inválido', '206 com errors[] só do item rejeitado', 206,
          () => _repo.promoEditar(_promo1!, corpoPromocao(_nome1, {Mecanica.percentual: [_pct(e1(), 12), _pct(e2(), 0)]}))),
      _Cenario(24, 'Edição', 'PATCH com promotionId inexistente', '404', 404,
          () => _repo.promoEditar(_uuid(), corpoPromocao('Hom $_sufixo x', {Mecanica.percentual: [_pct(e0(), 10)]}))),
      _Cenario(25, 'Pedidos', 'GET /orders com startDate > endDate', '400', 400, () {
        final agora = DateTime.now();
        return _repo.promoPedidos(_promo1!, startDate: rfc3339(agora), endDate: rfc3339(agora.subtract(const Duration(days: 2))));
      }),
      _Cenario(26, 'Remoção', 'items/remove com lista vazia (encerra a promoção do cenário 6)', '200 e a promoção fica INACTIVE', 200,
          () => _repo.promoRemoverItens(_promo6!)),
      _Cenario(27, 'Remoção', 'items/remove de novo na promoção já encerrada', '404', 404, () => _repo.promoRemoverItens(_promo6!)),
      _Cenario(28, 'Resiliência', 'Requisição com token expirado', '401 tratado: token renovado e reenviado (fica 200)', 200,
          () => _repo.promoConsultar(_promo1!, simularTokenExpirado: true),
          confere: (r) => r.status == 200 && r.tokenRenovado),
      _Cenario(29, 'Resiliência', 'Requisições seguidas até o iFood responder 429', '429 com espera progressiva, sem loop (fica 200)', 200,
          () => _repo.promoTeste429(), confere: (r) => r.status == 200 && r.requisicoes != null),
    ];
  }

  String? _preRequisito(int n) => switch (n) {
        7 || 15 || 23 || 25 || 28 => _precisa(p1: true, eans: 3),
        17 => _precisa(p1: true, eans: 1),
        22 || 26 || 27 => _precisa(p6: true, eans: 3),
        16 || 18 || 19 || 20 || 21 || 24 || 29 || 140 => null,
        14 => null,
        _ => _precisa(eans: n == 6 ? 3 : 1),
      };

  bool _passou(_Cenario c, RespostaIfood r) {
    if (c.confere != null) return c.confere!(r);
    if (r.status != c.statusEsperado) return false;
    if (c.codigoEsperado != null) return (r.codigoErro ?? '').contains(c.codigoEsperado!);
    return true;
  }

  Future<void> _rodar(_Cenario c) async {
    final falta = _preRequisito(c.numero);
    if (falta != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(falta)));
      return;
    }
    setState(() => _rodando.add(c.numero));
    final r = await c.executar();
    if (!mounted) return;
    setState(() { _resultados[c.numero] = r; _rodando.remove(c.numero); });
  }

  @override
  Widget build(BuildContext context) {
    final cenarios = _cenarios;
    String? grupoAnterior;
    final ok = cenarios.where((c) => _resultados[c.numero] != null && _passou(c, _resultados[c.numero]!)).length;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(
        color: Colors.blue.withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Sessão de homologação do módulo Promotion', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('Cada botão faz a chamada do cenário no iFood e mostra a resposta ao lado do resultado esperado. '
                'Vários cenários mandam dados errados de propósito. Rode na loja de teste. Ordem: 1 e 6 primeiro (os outros usam as promoções criadas neles).',
                style: TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            Text(_carregandoErro != null
                ? 'Não consegui carregar os produtos: $_carregandoErro'
                : 'Produtos usados: ${_eans.isEmpty ? 'carregando…' : _eans.join(', ')}',
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
            Text('$ok de ${cenarios.length} cenários com o resultado esperado', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            TextField(controller: _outroMerchant, decoration: const InputDecoration(labelText: 'Cenário 17: merchantId de outra loja', isDense: true)),
            TextField(controller: _merchantSemStoreType, decoration: const InputDecoration(labelText: 'Cenário 9: merchantId sem storeType (o analista informa)', isDense: true)),
          ]),
        ),
      ),
      for (final c in cenarios) ...[
        if (c.grupo != grupoAnterior) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Text((grupoAnterior = c.grupo), style: Theme.of(context).textTheme.titleSmall),
          ),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CircleAvatar(radius: 13, child: Text(c.numero == 140 ? '14b' : '${c.numero}', style: const TextStyle(fontSize: 11))),
                const SizedBox(width: 8),
                Expanded(child: Text(c.titulo, style: const TextStyle(fontWeight: FontWeight.w500))),
                FilledButton.tonal(
                  onPressed: _rodando.contains(c.numero) ? null : () => _rodar(c),
                  child: _rodando.contains(c.numero)
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Executar'),
                ),
              ]),
              if (_resultados[c.numero] == null)
                Padding(padding: const EdgeInsets.only(top: 4), child: Text('Esperado: ${c.esperado}', style: const TextStyle(fontSize: 12, color: Colors.grey)))
              else
                _RespostaCard(_resultados[c.numero]!, esperado: c.esperado, passou: _passou(c, _resultados[c.numero]!)),
            ]),
          ),
        ),
      ],
      const SizedBox(height: 24),
    ]);
  }
}

// ── Chamadas (log) ───────────────────────────────────────────────────────

class _AbaChamadas extends StatefulWidget {
  const _AbaChamadas();

  @override
  State<_AbaChamadas> createState() => _AbaChamadasState();
}

class _AbaChamadasState extends State<_AbaChamadas> {
  List<Map<String, dynamic>> _chamadas = [];
  bool _soPromocao = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _carregar();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _carregar());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      var q = supabase.from('marketplace_api_chamadas').select();
      if (_soPromocao) q = q.like('endpoint', '/promotion/%');
      final data = await q.order('created_at', ascending: false).limit(200);
      if (mounted) setState(() => _chamadas = (data as List).cast<Map<String, dynamic>>());
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM HH:mm:ss');
    return ListView(padding: const EdgeInsets.all(12), children: [
      Row(children: [
        Expanded(child: Text('${_chamadas.length} chamadas mais recentes', style: const TextStyle(fontSize: 12, color: Colors.grey))),
        FilterChip(
          label: const Text('Só promoções'),
          selected: _soPromocao,
          onSelected: (v) { setState(() => _soPromocao = v); _carregar(); },
        ),
      ]),
      ..._chamadas.map((c) {
        final status = c['http_status'] as int?;
        final ok = c['sucesso'] == true;
        final quando = DateTime.tryParse(c['created_at']?.toString() ?? '')?.toLocal();
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(quando == null ? '' : fmt.format(quando), style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                const SizedBox(width: 8),
                Text('${c['metodo']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                const Spacer(),
                if ((c['tentativa'] as int? ?? 1) > 1) Text('tentativa ${c['tentativa']}  ', style: const TextStyle(fontSize: 11)),
                Text(status == null ? (ok ? 'OK' : 'ERRO') : '$status', style: TextStyle(fontWeight: FontWeight.bold, color: ok ? (status == 206 ? Colors.orange : Colors.green) : Colors.red)),
              ]),
              SelectableText('${c['endpoint']}', style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
              if (c['promotion_id'] != null) Text('promotionId ${c['promotion_id']}', style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.grey)),
              if (c['error_code'] != null) Text('errorCode ${c['error_code']}', style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.red)),
              if (c['detalhe'] != null && '${c['detalhe']}'.isNotEmpty)
                Text('${c['detalhe']}', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
          ),
        );
      }),
    ]);
  }
}
