import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../config/supabase_config.dart';
import '../providers/auth_provider.dart';
import '../repositories/ifood_merchant_repository.dart';
import '../repositories/interrupcao_marketplace_repository.dart';

const _ifoodId = 'd4811153-e210-47b0-b910-ee0440914f60';
final _hora = DateFormat('dd/MM/yyyy HH:mm:ss');

/// Loja no iFood pela API: lojas vinculadas, pausas, horário de
/// funcionamento (vários turnos por dia) e catálogo. Tudo consulta o iFood
/// na hora (Edge Function `ifood-merchant`) e mostra a resposta.
class IfoodLojaApiScreen extends StatefulWidget {
  const IfoodLojaApiScreen({super.key});

  @override
  State<IfoodLojaApiScreen> createState() => _IfoodLojaApiScreenState();
}

class _IfoodLojaApiScreenState extends State<IfoodLojaApiScreen> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Loja no iFood'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.storefront), text: 'Lojas'),
              Tab(icon: Icon(Icons.pause_circle_outline), text: 'Pausas'),
              Tab(icon: Icon(Icons.schedule), text: 'Horário'),
              Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Catálogo'),
            ],
          ),
        ),
        body: const TabBarView(children: [_AbaLojas(), _AbaPausas(), _AbaHorario(), _AbaCatalogo()]),
      ),
    );
  }
}

/// Caixa com a resposta crua do iFood (status + JSON), pra conferência.
class _RespostaBox extends StatelessWidget {
  final String titulo;
  final RespostaIfood resposta;

  const _RespostaBox({required this.titulo, required this.resposta});

  @override
  Widget build(BuildContext context) {
    final cor = resposta.ok ? Colors.green : Colors.red;
    String corpo;
    try {
      corpo = const JsonEncoder.withIndent('  ').convert(resposta.dados);
    } catch (_) {
      corpo = resposta.dados?.toString() ?? '';
    }
    return Card(
      margin: const EdgeInsets.only(top: 8),
      child: ExpansionTile(
        leading: Icon(resposta.ok ? Icons.check_circle : Icons.error, color: cor),
        title: Text(titulo, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text('HTTP ${resposta.status} · ${_hora.format(resposta.em)}${resposta.erro != null ? ' · ${resposta.erro}' : ''}',
            style: TextStyle(fontSize: 12, color: cor)),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            color: Colors.black.withValues(alpha: 0.04),
            child: SelectableText(corpo.length > 6000 ? '${corpo.substring(0, 6000)}\n…' : corpo,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

Widget _carregando(bool sim) => sim
    ? const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()))
    : const SizedBox.shrink();

// ---------------------------------------------------------------- Lojas
class _AbaLojas extends StatefulWidget {
  const _AbaLojas();
  @override
  State<_AbaLojas> createState() => _AbaLojasState();
}

class _AbaLojasState extends State<_AbaLojas> {
  final _repo = IfoodMerchantRepository();
  RespostaIfood? _lista, _detalhe, _status;
  String? _selecionada;
  bool _ocupado = false;

  Future<void> _listar() async {
    setState(() => _ocupado = true);
    final r = await _repo.listarLojas();
    if (mounted) setState(() { _lista = r; _detalhe = null; _status = null; _selecionada = null; _ocupado = false; });
  }

  Future<void> _abrir(String id) async {
    setState(() { _ocupado = true; _selecionada = id; });
    final d = await _repo.detalheLoja(id);
    final s = await _repo.statusLoja(id);
    if (mounted) setState(() { _detalhe = d; _status = s; _ocupado = false; });
  }

  @override
  Widget build(BuildContext context) {
    final lojas = (_lista?.dados is List) ? (_lista!.dados as List).cast<Map>() : const <Map>[];
    final det = _detalhe?.dados is Map ? _detalhe!.dados as Map : null;
    final st = _status?.dados is List ? (_status!.dados as List).cast<Map>() : const <Map>[];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        FilledButton.icon(onPressed: _ocupado ? null : _listar, icon: const Icon(Icons.list), label: const Text('Listar lojas vinculadas')),
        _carregando(_ocupado),
        if (_lista != null) ...[
          const SizedBox(height: 8),
          Text('${lojas.length} loja(s) vinculada(s) a este aplicativo', style: const TextStyle(fontWeight: FontWeight.w600)),
          ...lojas.map((l) => Card(
                color: l['id'] == _selecionada ? Theme.of(context).colorScheme.primaryContainer : null,
                child: ListTile(
                  leading: const Icon(Icons.store),
                  title: Text(l['name']?.toString() ?? '-'),
                  subtitle: Text('${l['corporateName'] ?? ''}\nID ${l['id']}'),
                  isThreeLine: true,
                  trailing: const Text('Ver detalhes'),
                  onTap: _ocupado ? null : () => _abrir(l['id'].toString()),
                ),
              )),
          _RespostaBox(titulo: 'GET /merchants', resposta: _lista!),
        ],
        if (det != null) ...[
          const SizedBox(height: 12),
          Text('Detalhes da loja', style: Theme.of(context).textTheme.titleMedium),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _linha('Nome', det['name']),
                _linha('Razão social', det['corporateName']),
                _linha('Descrição', det['description']),
                _linha('Ticket médio', det['averageTicket']),
                _linha('Status', det['status']),
                _linha('Endereço', det['address'] is Map
                    ? [det['address']['street'], det['address']['number'], det['address']['district'], det['address']['city'], det['address']['state']]
                        .where((x) => x != null && '$x'.isNotEmpty).join(', ')
                    : null),
                _linha('Operações', det['operations'] is List
                    ? (det['operations'] as List).map((o) => o is Map ? o['name'] : o).join(', ')
                    : null),
              ]),
            ),
          ),
          _RespostaBox(titulo: 'GET /merchants/{id}', resposta: _detalhe!),
        ],
        if (_status != null) ...[
          const SizedBox(height: 12),
          Text('Disponibilidade agora', style: Theme.of(context).textTheme.titleMedium),
          ...st.map((s) {
            final disponivel = s['available'] == true;
            final validacoes = (s['validations'] as List?)?.cast<Map>() ?? const <Map>[];
            return Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(disponivel ? Icons.check_circle : Icons.cancel, color: disponivel ? Colors.green : Colors.red),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${s['operation'] ?? ''} · ${s['salesChannel'] ?? ''} · ${s['state'] ?? ''}',
                        style: const TextStyle(fontWeight: FontWeight.w600))),
                  ]),
                  if (s['message'] is Map) Text('${s['message']['title'] ?? ''} ${s['message']['subtitle'] ?? ''}'),
                  ...validacoes.map((v) => Text('• ${v['code']}: ${v['state']}${v['message'] is Map ? ' — ${v['message']['title'] ?? ''}' : ''}',
                      style: const TextStyle(fontSize: 12))),
                ]),
              ),
            );
          }),
          _RespostaBox(titulo: 'GET /merchants/{id}/status', resposta: _status!),
        ],
      ],
    );
  }

  Widget _linha(String rotulo, Object? valor) => valor == null || '$valor'.isEmpty
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text.rich(TextSpan(children: [
            TextSpan(text: '$rotulo: ', style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: '$valor'),
          ])),
        );
}

// ---------------------------------------------------------------- Pausas
class _AbaPausas extends StatefulWidget {
  const _AbaPausas();
  @override
  State<_AbaPausas> createState() => _AbaPausasState();
}

class _AbaPausasState extends State<_AbaPausas> {
  final _repo = IfoodMerchantRepository();
  final _interrupcoes = InterrupcaoMarketplaceRepository();
  RespostaIfood? _lista;
  bool _ocupado = false;
  String? _aviso;

  @override
  void initState() {
    super.initState();
    _listar();
  }

  Future<void> _listar() async {
    setState(() => _ocupado = true);
    final r = await _repo.listarPausas();
    if (mounted) setState(() { _lista = r; _ocupado = false; });
  }

  /// A pausa é criada/removida pelo caminho de sempre (tabela → gatilho →
  /// iFood); aqui espera a confirmação e lista de novo.
  Future<void> _esperarELista(String aviso) async {
    setState(() => _aviso = aviso);
    await Future.delayed(const Duration(seconds: 4));
    await _listar();
    if (mounted) setState(() => _aviso = null);
  }

  Future<void> _nova() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;
    final motivo = TextEditingController(text: 'Pausa para manutenção');
    var minutos = 60;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Nova pausa no iFood'),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(controller: motivo, decoration: const InputDecoration(labelText: 'Motivo')),
            const SizedBox(height: 12),
            Wrap(spacing: 8, children: [
              for (final m in [30, 60, 120])
                ChoiceChip(label: Text(m < 60 ? '$m min' : '${m ~/ 60} h'), selected: minutos == m, onSelected: (_) => set(() => minutos = m)),
            ]),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cadastrar pausa')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _interrupcoes.pausar(
      empresaId: empresaId,
      marketplaceId: _ifoodId,
      motivo: motivo.text.trim().isEmpty ? 'Pausa' : motivo.text.trim(),
      fim: DateTime.now().add(Duration(minutes: minutos)),
    );
    await _esperarELista('Pausa cadastrada, enviando ao iFood…');
  }

  Future<void> _remover(String idExterno) async {
    final rows = await supabase
        .from('marketplace_interrupcoes')
        .select('id')
        .eq('id_externo', idExterno)
        .limit(1) as List;
    if (rows.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Essa pausa não foi criada pelo Gestor.')));
      }
      return;
    }
    await _interrupcoes.cancelar(rows.first['id'] as String);
    await _esperarELista('Removendo a pausa no iFood…');
  }

  @override
  Widget build(BuildContext context) {
    final pausas = _lista?.dados is List ? (_lista!.dados as List).cast<Map>() : const <Map>[];
    final f = DateFormat('dd/MM HH:mm');
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: _ocupado ? null : _nova, icon: const Icon(Icons.add), label: const Text('Cadastrar pausa'))),
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: _ocupado ? null : _listar, icon: const Icon(Icons.refresh), label: const Text('Listar pausas ativas')),
        ]),
        if (_aviso != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_aviso!, style: const TextStyle(color: Colors.orange))),
        _carregando(_ocupado),
        if (_lista != null) ...[
          const SizedBox(height: 8),
          Text(pausas.isEmpty ? 'Nenhuma pausa ativa no iFood' : '${pausas.length} pausa(s) ativa(s) no iFood',
              style: const TextStyle(fontWeight: FontWeight.w600)),
          ...pausas.map((p) {
            final ini = DateTime.tryParse('${p['start']}')?.toLocal();
            final fim = DateTime.tryParse('${p['end']}')?.toLocal();
            return Card(
              child: ListTile(
                leading: const Icon(Icons.pause_circle, color: Colors.orange),
                title: Text(p['description']?.toString() ?? 'Pausa'),
                subtitle: Text('${ini != null ? f.format(ini) : '-'} até ${fim != null ? f.format(fim) : '-'}\nID ${p['id']}'),
                isThreeLine: true,
                trailing: TextButton(onPressed: _ocupado ? null : () => _remover('${p['id']}'), child: const Text('Remover')),
              ),
            );
          }),
          _RespostaBox(titulo: 'GET /merchants/{id}/interruptions', resposta: _lista!),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------- Horário
const _dias = [
  ('segunda', 'Segunda', 'MONDAY'),
  ('terca', 'Terça', 'TUESDAY'),
  ('quarta', 'Quarta', 'WEDNESDAY'),
  ('quinta', 'Quinta', 'THURSDAY'),
  ('sexta', 'Sexta', 'FRIDAY'),
  ('sabado', 'Sábado', 'SATURDAY'),
  ('domingo', 'Domingo', 'SUNDAY'),
];

class _Turno {
  final TextEditingController inicio;
  final TextEditingController fim;
  _Turno(String i, String f)
      : inicio = TextEditingController(text: i),
        fim = TextEditingController(text: f);
}

class _AbaHorario extends StatefulWidget {
  const _AbaHorario();
  @override
  State<_AbaHorario> createState() => _AbaHorarioState();
}

class _AbaHorarioState extends State<_AbaHorario> {
  final _repo = IfoodMerchantRepository();
  final Map<String, List<_Turno>> _turnos = {for (final d in _dias) d.$1: []};
  RespostaIfood? _salvo, _consulta;
  bool _ocupado = false;

  @override
  void initState() {
    super.initState();
    _consultar();
  }

  Future<void> _consultar() async {
    setState(() => _ocupado = true);
    final r = await _repo.consultarHorarios();
    if (!mounted) return;
    setState(() {
      _consulta = r;
      _ocupado = false;
      final shifts = r.dados is Map ? (r.dados['shifts'] as List?)?.cast<Map>() : null;
      if (shifts != null) {
        for (final l in _turnos.values) {
          l.clear();
        }
        for (final s in shifts) {
          final dia = _dias.where((d) => d.$3 == s['dayOfWeek']).firstOrNull;
          if (dia == null) continue;
          final ini = '${s['start']}'.substring(0, 5);
          final p = ini.split(':');
          final fimMin = int.parse(p[0]) * 60 + int.parse(p[1]) + ((s['duration'] as num?)?.toInt() ?? 0);
          final fim = fimMin >= 1440 ? '00:00' : '${(fimMin ~/ 60).toString().padLeft(2, '0')}:${(fimMin % 60).toString().padLeft(2, '0')}';
          _turnos[dia.$1]!.add(_Turno(ini, fim));
        }
      }
    });
  }

  Future<void> _salvar() async {
    final lista = <TurnoIfood>[];
    for (final d in _dias) {
      for (final t in _turnos[d.$1]!) {
        lista.add(TurnoIfood(d.$1, t.inicio.text.trim(), t.fim.text.trim()));
      }
    }
    setState(() => _ocupado = true);
    final r = await _repo.salvarHorarios(lista);
    if (!mounted) return;
    setState(() { _salvo = r; _ocupado = false; });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r.ok ? 'Horário enviado ao iFood.' : 'O iFood recusou: ${r.erro ?? r.status}')));
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Horário de funcionamento no iFood (só o iFood; não muda o horário do site nem da loja). Cada dia pode ter vários turnos.',
            style: TextStyle(fontSize: 12)),
        const SizedBox(height: 8),
        for (final d in _dias)
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  SizedBox(width: 80, child: Text(d.$2, style: const TextStyle(fontWeight: FontWeight.w600))),
                  if (_turnos[d.$1]!.isEmpty) const Text('Fechado', style: TextStyle(color: Colors.grey)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => setState(() => _turnos[d.$1]!.add(_Turno('', ''))),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Turno'),
                  ),
                ]),
                for (final t in _turnos[d.$1]!)
                  Padding(padding: const EdgeInsets.only(top: 10), child: Row(children: [
                    const SizedBox(width: 80),
                    SizedBox(width: 110, child: TextField(controller: t.inicio, decoration: const InputDecoration(hintText: '00:00', labelText: 'Abre'))),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('às')),
                    SizedBox(width: 110, child: TextField(controller: t.fim, decoration: const InputDecoration(hintText: '00:00', labelText: 'Fecha'))),
                    IconButton(onPressed: () => setState(() => _turnos[d.$1]!.remove(t)), icon: const Icon(Icons.close, size: 18)),
                  ])),
              ]),
            ),
          ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: FilledButton.icon(onPressed: _ocupado ? null : _salvar, icon: const Icon(Icons.cloud_upload), label: const Text('Salvar no iFood'))),
          const SizedBox(width: 8),
          OutlinedButton.icon(onPressed: _ocupado ? null : _consultar, icon: const Icon(Icons.search), label: const Text('Consultar no iFood')),
        ]),
        _carregando(_ocupado),
        if (_salvo != null) _RespostaBox(titulo: 'PUT /merchants/{id}/opening-hours', resposta: _salvo!),
        if (_consulta != null) _RespostaBox(titulo: 'GET /merchants/{id}/opening-hours', resposta: _consulta!),
      ],
    );
  }
}

// ---------------------------------------------------------------- Catálogo
class _AbaCatalogo extends StatefulWidget {
  const _AbaCatalogo();
  @override
  State<_AbaCatalogo> createState() => _AbaCatalogoState();
}

class _AbaCatalogoState extends State<_AbaCatalogo> {
  static String _motivo(Object? m) => switch (m) {
        'dados_produto' => 'cadastro/dados do produto',
        'preco_disponibilidade' => 'preço, promoção e disponibilidade',
        'estoque' => 'estoque',
        'completo' => 'preço, promoção e estoque',
        null => '',
        _ => '$m',
      };

  final _repo = IfoodMerchantRepository();
  RespostaIfood? _carga;
  List<Map<String, dynamic>> _envios = [];
  bool _ocupado = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _carregarEnvios();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _carregarEnvios());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _carregarEnvios() async {
    try {
      final rows = await supabase
          .from('produto_canal')
          .select('preco, disponivel, ultima_sincronizacao_em, sincronizacao_status, sincronizacao_erro, sincronizacao_motivo_disparo, '
              'produtos(nome, preco, codigo_barras, preco_promocional, estoque(quantidade_atual))')
          .eq('marketplace_id', _ifoodId)
          .not('ultima_sincronizacao_em', 'is', null)
          .order('ultima_sincronizacao_em', ascending: false)
          .limit(8);
      if (mounted) setState(() => _envios = (rows as List).cast<Map<String, dynamic>>());
    } catch (e) {
      debugPrint('Erro ao carregar envios iFood: $e');
    }
  }

  Future<void> _cargaCompleta() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar catálogo completo?'),
        content: const Text('Envia todos os produtos ao iFood com reset=true: o que não estiver na lista fica inativo no iFood.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _ocupado = true);
    final r = await _repo.cargaCompleta();
    if (mounted) setState(() { _carga = r; _ocupado = false; });
  }

  @override
  Widget build(BuildContext context) {
    final f = DateFormat('dd/MM HH:mm:ss');
    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text('Produto novo, preço, estoque e preço promocional vão ao iFood sozinhos na hora em que mudam no Gestor '
            '(novo = POST, alteração = PATCH), e o catálogo é conferido de novo a cada 30 min.',
            style: TextStyle(fontSize: 12)),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _ocupado ? null : _cargaCompleta,
          icon: const Icon(Icons.cloud_sync),
          label: const Text('Enviar catálogo completo (reset=true)'),
        ),
        _carregando(_ocupado),
        if (_carga != null)
          _RespostaBox(
            titulo: 'POST /item/v1.0/ingestion/{merchantId}?reset=true · ${_carga!.itensEnviados ?? 0} itens',
            resposta: _carga!,
          ),
        const SizedBox(height: 16),
        Text('Últimos envios ao iFood', style: Theme.of(context).textTheme.titleMedium),
        ..._envios.map((e) {
          final p = (e['produtos'] as Map?) ?? const {};
          final estoque = ((p['estoque'] as List?) ?? const [])
              .fold<num>(0, (s, x) => s + (((x as Map)['quantidade_atual'] as num?) ?? 0));
          final quando = DateTime.tryParse('${e['ultima_sincronizacao_em']}')?.toLocal();
          final erro = e['sincronizacao_erro'];
          final promo = p['preco_promocional'] as num?;
          return Card(
            child: ListTile(
              leading: Icon(erro == null ? Icons.check_circle : Icons.error, color: erro == null ? Colors.green : Colors.red),
              title: Text('${p['nome'] ?? '-'}', maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                'EAN ${p['codigo_barras'] ?? '-'} · ${moeda.format((e['preco'] as num?) ?? (p['preco'] as num?) ?? 0)}'
                '${promo != null ? ' · promo ${moeda.format(promo)}' : ''} · estoque $estoque\n'
                '${quando != null ? f.format(quando) : '-'} · ${_motivo(e['sincronizacao_motivo_disparo'])} · ${e['sincronizacao_status'] ?? ''}'
                '${erro != null ? '\n$erro' : ''}',
              ),
              isThreeLine: true,
            ),
          );
        }),
      ],
    );
  }
}
