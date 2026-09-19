import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/campanha_ativacao.dart';
import '../providers/auth_provider.dart';
import '../repositories/campanha_ativacao_repository.dart';
import '../utils/produto_validators.dart';

/// Tela de filtros reutilizável pra selecionar clientes por critério
/// (inatividade, valor gasto, ticket médio, canal, segmento etc) e
/// confirmá-los em lote como contatos de uma campanha de ativação — em vez
/// de só importar por planilha. Pensada pra servir qualquer campanha
/// futura, não só a de reativação com brinde: nenhum critério é fixo aqui,
/// tudo fica em branco (sem filtro) por padrão.
class FiltroClientesCampanhaScreen extends StatefulWidget {
  final CampanhaAtivacao campanha;
  const FiltroClientesCampanhaScreen({super.key, required this.campanha});

  @override
  State<FiltroClientesCampanhaScreen> createState() => _FiltroClientesCampanhaScreenState();
}

class _FiltroClientesCampanhaScreenState extends State<FiltroClientesCampanhaScreen> {
  final _diasMinCtrl = TextEditingController();
  final _diasMaxCtrl = TextEditingController();
  final _qtdPedidosMinCtrl = TextEditingController();
  final _qtdPedidosMaxCtrl = TextEditingController();
  final _valorTotalMinCtrl = TextEditingController();
  final _valorTotalMaxCtrl = TextEditingController();
  final _ticketMedioMinCtrl = TextEditingController();
  final _ticketMedioMaxCtrl = TextEditingController();

  static const _canaisDisponiveis = ['site_proprio', 'ifood', 'kyte_historico'];
  static const _segmentosDisponiveis = ['novo', 'regular', 'vip', 'inativo'];

  final Set<String> _canaisSelecionados = {};
  final Set<String> _segmentosSelecionados = {};
  bool? _aceitaMarketing;
  bool? _jaUsouCupom;
  String _ordenarPor = 'recencia';
  String _ordem = 'desc';

  bool _carregando = false;
  bool _adicionando = false;
  List<ClienteFiltradoCampanha>? _resultado;
  final Set<String> _clienteIdsExcluidos = {};

  @override
  void dispose() {
    _diasMinCtrl.dispose();
    _diasMaxCtrl.dispose();
    _qtdPedidosMinCtrl.dispose();
    _qtdPedidosMaxCtrl.dispose();
    _valorTotalMinCtrl.dispose();
    _valorTotalMaxCtrl.dispose();
    _ticketMedioMinCtrl.dispose();
    _ticketMedioMaxCtrl.dispose();
    super.dispose();
  }

  int? _int(TextEditingController c) => c.text.trim().isEmpty ? null : int.tryParse(c.text.trim());
  double? _double(TextEditingController c) => ProdutoValidators.parseNumero(c.text);

  Future<void> _aplicarFiltros() async {
    setState(() {
      _carregando = true;
      _resultado = null;
      _clienteIdsExcluidos.clear();
    });
    try {
      final lista = await CampanhaAtivacaoRepository().filtrarClientes(
        diasInatividadeMin: _int(_diasMinCtrl),
        diasInatividadeMax: _int(_diasMaxCtrl),
        qtdPedidosMin: _int(_qtdPedidosMinCtrl),
        qtdPedidosMax: _int(_qtdPedidosMaxCtrl),
        valorTotalMin: _double(_valorTotalMinCtrl),
        valorTotalMax: _double(_valorTotalMaxCtrl),
        ticketMedioMin: _double(_ticketMedioMinCtrl),
        ticketMedioMax: _double(_ticketMedioMaxCtrl),
        canais: _canaisSelecionados.isEmpty ? null : _canaisSelecionados.toList(),
        segmentos: _segmentosSelecionados.isEmpty ? null : _segmentosSelecionados.toList(),
        aceitaMarketing: _aceitaMarketing,
        jaUsouCupom: _jaUsouCupom,
        ordenarPor: _ordenarPor,
        ordem: _ordem,
      );
      if (!mounted) return;
      setState(() => _resultado = lista);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível filtrar: $e')));
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _confirmarAdicao() async {
    final selecionados = _resultado!.where((c) => !_clienteIdsExcluidos.contains(c.clienteId)).toList();
    if (selecionados.isEmpty) return;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adicionar à campanha'),
        content: Text(
          '${selecionados.length} cliente${selecionados.length == 1 ? '' : 's'} '
          'ser${selecionados.length == 1 ? 'á adicionado' : 'ão adicionados'} como contato${selecionados.length == 1 ? '' : 's'} '
          'de "${widget.campanha.nome}", com a prioridade de ordenação já calculada pelo filtro.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Adicionar')),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    setState(() => _adicionando = true);
    try {
      final empresaId = context.read<AuthProvider>().empresaId;
      if (empresaId == null) throw StateError('Empresa não identificada.');

      final qtd = await CampanhaAtivacaoRepository().adicionarContatosFiltrados(
        campanhaId: widget.campanha.id,
        empresaId: empresaId,
        clientes: selecionados,
      );
      if (!mounted) return;
      Navigator.of(context).pop(qtd);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível adicionar: $e')));
      }
    } finally {
      if (mounted) setState(() => _adicionando = false);
    }
  }

  Widget _campoNumero(String label, TextEditingController ctrl, {bool decimal = false}) {
    return SizedBox(
      width: 140,
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder(), isDense: true),
      ),
    );
  }

  Widget _secao(String titulo, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  String _rotuloCanal(String canal) => switch (canal) {
        'site_proprio' => 'Site próprio',
        'ifood' => 'iFood',
        'kyte_historico' => 'Histórico Kyte',
        _ => canal,
      };

  String _rotuloSegmento(String segmento) => switch (segmento) {
        'novo' => 'Novo',
        'regular' => 'Regular',
        'vip' => 'VIP',
        'inativo' => 'Inativo',
        _ => segmento,
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Filtrar clientes')),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _secao(
                    'Inatividade (dias desde a última compra)',
                    Wrap(spacing: 12, runSpacing: 8, children: [
                      _campoNumero('Mínimo', _diasMinCtrl),
                      _campoNumero('Máximo', _diasMaxCtrl),
                    ]),
                  ),
                  _secao(
                    'Quantidade de pedidos',
                    Wrap(spacing: 12, runSpacing: 8, children: [
                      _campoNumero('Mínimo', _qtdPedidosMinCtrl),
                      _campoNumero('Máximo', _qtdPedidosMaxCtrl),
                    ]),
                  ),
                  _secao(
                    'Valor total gasto (R\$)',
                    Wrap(spacing: 12, runSpacing: 8, children: [
                      _campoNumero('Mínimo', _valorTotalMinCtrl, decimal: true),
                      _campoNumero('Máximo', _valorTotalMaxCtrl, decimal: true),
                    ]),
                  ),
                  _secao(
                    'Ticket médio (R\$)',
                    Wrap(spacing: 12, runSpacing: 8, children: [
                      _campoNumero('Mínimo', _ticketMedioMinCtrl, decimal: true),
                      _campoNumero('Máximo', _ticketMedioMaxCtrl, decimal: true),
                    ]),
                  ),
                  _secao(
                    'Canal de origem',
                    Wrap(
                      spacing: 8,
                      children: _canaisDisponiveis
                          .map((c) => FilterChip(
                                label: Text(_rotuloCanal(c)),
                                selected: _canaisSelecionados.contains(c),
                                onSelected: (v) => setState(
                                    () => v ? _canaisSelecionados.add(c) : _canaisSelecionados.remove(c)),
                              ))
                          .toList(),
                    ),
                  ),
                  _secao(
                    'Segmento',
                    Wrap(
                      spacing: 8,
                      children: _segmentosDisponiveis
                          .map((s) => FilterChip(
                                label: Text(_rotuloSegmento(s)),
                                selected: _segmentosSelecionados.contains(s),
                                onSelected: (v) => setState(
                                    () => v ? _segmentosSelecionados.add(s) : _segmentosSelecionados.remove(s)),
                              ))
                          .toList(),
                    ),
                  ),
                  _secao(
                    'Outros critérios',
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      FilterChip(
                        label: const Text('Aceita marketing'),
                        selected: _aceitaMarketing == true,
                        onSelected: (v) => setState(() => _aceitaMarketing = v ? true : null),
                      ),
                      FilterChip(
                        label: const Text('Nunca usou cupom'),
                        selected: _jaUsouCupom == false,
                        onSelected: (v) => setState(() => _jaUsouCupom = v ? false : null),
                      ),
                      FilterChip(
                        label: const Text('Já usou cupom'),
                        selected: _jaUsouCupom == true,
                        onSelected: (v) => setState(() => _jaUsouCupom = v ? true : null),
                      ),
                    ]),
                  ),
                  _secao(
                    'Ordenar por (define a prioridade)',
                    Wrap(spacing: 12, runSpacing: 8, children: [
                      DropdownButton<String>(
                        value: _ordenarPor,
                        items: const [
                          DropdownMenuItem(value: 'recencia', child: Text('Tempo de inatividade')),
                          DropdownMenuItem(value: 'ticket_medio', child: Text('Ticket médio')),
                          DropdownMenuItem(value: 'valor_total', child: Text('Valor total gasto')),
                          DropdownMenuItem(value: 'qtd_pedidos', child: Text('Quantidade de pedidos')),
                          DropdownMenuItem(
                            value: 'combinado',
                            child: Text('Combinado (recência + valor + ticket + pedidos)'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _ordenarPor = v ?? 'recencia'),
                      ),
                      DropdownButton<String>(
                        value: _ordem,
                        items: const [
                          DropdownMenuItem(value: 'desc', child: Text('Maior primeiro')),
                          DropdownMenuItem(value: 'asc', child: Text('Menor primeiro')),
                        ],
                        onChanged: (v) => setState(() => _ordem = v ?? 'desc'),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _carregando ? null : _aplicarFiltros,
                    icon: _carregando
                        ? const SizedBox(
                            width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.filter_alt),
                    label: Text(_carregando ? 'Filtrando...' : 'Aplicar filtros'),
                  ),
                  if (_resultado != null) ...[
                    const Divider(height: 32),
                    Text(
                      '${_resultado!.length - _clienteIdsExcluidos.length} de ${_resultado!.length} cliente${_resultado!.length == 1 ? '' : 's'} selecionado${_resultado!.length - _clienteIdsExcluidos.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    if (_resultado!.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text('Nenhum cliente bate com esses critérios.'),
                      )
                    else
                      ..._resultado!.map((c) {
                        final excluido = _clienteIdsExcluidos.contains(c.clienteId);
                        return CheckboxListTile(
                          value: !excluido,
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _clienteIdsExcluidos.remove(c.clienteId);
                            } else {
                              _clienteIdsExcluidos.add(c.clienteId);
                            }
                          }),
                          title: Text(c.nome),
                          subtitle: Text(
                            '${c.diasInatividade}d inativo · ${c.qtdPedidos} pedido${c.qtdPedidos == 1 ? '' : 's'} · '
                            'R\$ ${ProdutoValidators.formatarMoeda(c.valorTotal)} total · '
                            'ticket R\$ ${ProdutoValidators.formatarMoeda(c.ticketMedio)}'
                            '${c.segmento != null ? ' · ${_rotuloSegmento(c.segmento!)}' : ''}',
                          ),
                          dense: true,
                        );
                      }),
                  ],
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: (_resultado == null || _resultado!.isEmpty)
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: _adicionando ? null : _confirmarAdicao,
                  icon: _adicionando
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.person_add_alt_1),
                  label: Text(_adicionando
                      ? 'Adicionando...'
                      : 'Adicionar ${_resultado!.length - _clienteIdsExcluidos.length} à campanha'),
                ),
              ),
            ),
    );
  }
}
