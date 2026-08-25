import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/push_campanha.dart';
import '../repositories/push_campanha_repository.dart';
import '../widgets/estado_erro_lista.dart';

const _atalhos = {
  'inativos': 'Clientes inativos',
  'prontos_recompra': 'Prontos pra recompra',
  'aniversariantes_hoje': 'Aniversariantes hoje',
};

const _segmentos = {'novo': 'Novo', 'regular': 'Regular', 'vip': 'VIP'};

/// Disparo manual de campanha de push segmentada. O filtro é montado como
/// mapa de chaves fixas (mesmo shape que `_audiencia_push_campanha` no
/// banco espera) — nunca texto livre virando SQL.
class PushCampanhaScreen extends StatefulWidget {
  const PushCampanhaScreen({super.key});

  @override
  State<PushCampanhaScreen> createState() => _PushCampanhaScreenState();
}

class _PushCampanhaScreenState extends State<PushCampanhaScreen> {
  final _repo = PushCampanhaRepository();
  final _controladorTitulo = TextEditingController();
  final _controladorMensagem = TextEditingController();
  final _controladorLink = TextEditingController();
  final _controladorEspecie = TextEditingController();
  final _controladorPorte = TextEditingController();
  final _controladorCidade = TextEditingController();
  final _controladorCategoria = TextEditingController();
  final _controladorDiasSemComprar = TextEditingController();
  final _controladorSaldoPetcashMin = TextEditingController();

  String? _segmento;
  String? _atalho;
  int? _audiencia;
  bool _carregandoAudiencia = false;
  bool _enviando = false;
  Timer? _debounce;

  late Future<List<PushCampanha>> _futuroHistorico;

  @override
  void initState() {
    super.initState();
    _futuroHistorico = _repo.listar();
    _agendarRecalculoAudiencia();
    for (final c in [
      _controladorEspecie,
      _controladorPorte,
      _controladorCidade,
      _controladorCategoria,
      _controladorDiasSemComprar,
      _controladorSaldoPetcashMin,
    ]) {
      c.addListener(_agendarRecalculoAudiencia);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controladorTitulo.dispose();
    _controladorMensagem.dispose();
    _controladorLink.dispose();
    _controladorEspecie.dispose();
    _controladorPorte.dispose();
    _controladorCidade.dispose();
    _controladorCategoria.dispose();
    _controladorDiasSemComprar.dispose();
    _controladorSaldoPetcashMin.dispose();
    super.dispose();
  }

  Map<String, dynamic> _montarFiltro() {
    final filtro = <String, dynamic>{};
    if (_segmento != null) filtro['segmento'] = _segmento;
    if (_atalho != null) filtro['reaproveitar_view'] = _atalho;
    if (_controladorEspecie.text.trim().isNotEmpty) filtro['especie_pet'] = _controladorEspecie.text.trim();
    if (_controladorPorte.text.trim().isNotEmpty) filtro['porte_pet'] = _controladorPorte.text.trim();
    if (_controladorCidade.text.trim().isNotEmpty) filtro['cidade'] = _controladorCidade.text.trim();
    if (_controladorCategoria.text.trim().isNotEmpty) {
      filtro['categoria_comprada'] = _controladorCategoria.text.trim();
    }
    final dias = int.tryParse(_controladorDiasSemComprar.text.trim());
    if (dias != null) filtro['dias_sem_comprar_min'] = dias;
    final saldoMin = double.tryParse(_controladorSaldoPetcashMin.text.trim().replaceAll(',', '.'));
    if (saldoMin != null) filtro['saldo_petcash_min'] = saldoMin;
    return filtro;
  }

  void _agendarRecalculoAudiencia() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _recalcularAudiencia);
  }

  Future<void> _recalcularAudiencia() async {
    if (!mounted) return;
    setState(() => _carregandoAudiencia = true);
    try {
      final total = await _repo.contarAudiencia(_montarFiltro());
      if (mounted) setState(() => _audiencia = total);
    } catch (_) {
      if (mounted) setState(() => _audiencia = null);
    } finally {
      if (mounted) setState(() => _carregandoAudiencia = false);
    }
  }

  Future<void> _recarregarHistorico() async {
    setState(() => _futuroHistorico = _repo.listar());
    await _futuroHistorico;
  }

  Future<void> _enviarCampanha() async {
    final titulo = _controladorTitulo.text.trim();
    final mensagem = _controladorMensagem.text.trim();
    if (titulo.isEmpty || mensagem.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Preencha título e mensagem.')),
      );
      return;
    }

    final audiencia = _audiencia;
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enviar campanha?'),
        content: Text(
          audiencia == null
              ? 'Não foi possível confirmar o tamanho da audiência. Enviar mesmo assim?'
              : audiencia == 0
                  ? 'Nenhum cliente alcançável com esse filtro hoje (push exige login no site/app). '
                    'Enviar mesmo assim não notifica ninguém.'
                  : 'Vai ser enviado pra $audiencia cliente${audiencia == 1 ? '' : 's'}. Confirma?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enviar')),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    setState(() => _enviando = true);
    try {
      await _repo.criar(
        titulo: titulo,
        mensagem: mensagem,
        link: _controladorLink.text.trim().isEmpty ? null : _controladorLink.text.trim(),
        filtro: _montarFiltro(),
      );
      if (!mounted) return;
      _controladorTitulo.clear();
      _controladorMensagem.clear();
      _controladorLink.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Campanha enviada.')),
      );
      await _recarregarHistorico();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível enviar: $e')));
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Campanha de Push')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Nova campanha', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _controladorTitulo,
            decoration: const InputDecoration(labelText: 'Título', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controladorMensagem,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Mensagem', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controladorLink,
            decoration: const InputDecoration(
              labelText: 'Link ao tocar (opcional)',
              hintText: '/loja/slug/produto/xyz ou URL completa',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 20),
          Text('Público', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              DropdownMenu<String?>(
                label: const Text('Segmento'),
                initialSelection: _segmento,
                onSelected: (v) {
                  setState(() => _segmento = v);
                  _agendarRecalculoAudiencia();
                },
                dropdownMenuEntries: [
                  const DropdownMenuEntry(value: null, label: 'Qualquer'),
                  ..._segmentos.entries.map((e) => DropdownMenuEntry(value: e.key, label: e.value)),
                ],
              ),
              DropdownMenu<String?>(
                label: const Text('Atalho'),
                initialSelection: _atalho,
                onSelected: (v) {
                  setState(() => _atalho = v);
                  _agendarRecalculoAudiencia();
                },
                dropdownMenuEntries: [
                  const DropdownMenuEntry(value: null, label: 'Nenhum'),
                  ..._atalhos.entries.map((e) => DropdownMenuEntry(value: e.key, label: e.value)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _controladorEspecie,
                  decoration: const InputDecoration(labelText: 'Espécie do pet', border: OutlineInputBorder()),
                ),
              ),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _controladorPorte,
                  decoration: const InputDecoration(labelText: 'Porte do pet', border: OutlineInputBorder()),
                ),
              ),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _controladorCidade,
                  decoration: const InputDecoration(labelText: 'Cidade', border: OutlineInputBorder()),
                ),
              ),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _controladorCategoria,
                  decoration:
                      const InputDecoration(labelText: 'Categoria já comprada', border: OutlineInputBorder()),
                ),
              ),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _controladorDiasSemComprar,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Dias sem comprar (mín.)', border: OutlineInputBorder()),
                ),
              ),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _controladorSaldoPetcashMin,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration:
                      const InputDecoration(labelText: 'Saldo PetCash mín.', border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.groups_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _carregandoAudiencia
                          ? 'Calculando audiência...'
                          : _audiencia == null
                              ? 'Não foi possível calcular a audiência.'
                              : '$_audiencia cliente${_audiencia == 1 ? '' : 's'} alcançável${_audiencia == 1 ? '' : 'is'} '
                                'com esse filtro hoje.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _enviando ? null : _enviarCampanha,
            icon: _enviando
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.send),
            label: const Text('Enviar campanha'),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          Text('Histórico', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          FutureBuilder<List<PushCampanha>>(
            future: _futuroHistorico,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return EstadoErroLista(
                  mensagem: 'Não foi possível carregar o histórico: ${snapshot.error}',
                  onTentarNovamente: _recarregarHistorico,
                );
              }
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final itens = snapshot.data ?? [];
              if (itens.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Nenhuma campanha enviada ainda.'),
                );
              }
              return Column(
                children: itens
                    .map(
                      (c) => Card(
                        child: ListTile(
                          title: Text(c.titulo),
                          subtitle: Text(
                            '${c.mensagem}\n${DateFormat('dd/MM/yyyy HH:mm').format(c.criadoEm.toLocal())}',
                          ),
                          isThreeLine: true,
                          trailing: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(c.status),
                              Text('${c.totalEnviados}/${c.totalDestinatarios} enviados'),
                              if (c.totalFalhas > 0) Text('${c.totalFalhas} falhas'),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
