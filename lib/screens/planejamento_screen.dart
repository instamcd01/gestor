import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/pedido_compra.dart';
import '../models/periodo_planejamento.dart';
import '../models/sugestao_planejamento.dart';
import '../models/tarefa.dart';
import '../providers/auth_provider.dart';
import '../providers/meta_financeira_provider.dart';
import '../providers/sugestao_planejamento_provider.dart';
import '../providers/tarefa_provider.dart';
import '../widgets/aviso_banner.dart';
import '../widgets/estado_erro_lista.dart';
import '../widgets/form_section.dart';

// Evita `DateFormat('MMMM', 'pt_BR')` de propósito — precisaria de
// `initializeDateFormatting('pt_BR')`, que este app nunca chama em lugar
// nenhum (ver mesmo comentário em metricas_despesas_screen.dart).
const _mesesPorExtenso = [
  'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
  'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
];
// DateTime.weekday: 1=segunda ... 7=domingo — usado nos cabeçalhos de data.
const _diasDaSemana = ['Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado', 'Domingo'];

// Postgres `extract(dow from ...)`: 0=domingo ... 6=sábado — convenção
// DIFERENTE de DateTime.weekday, usada só pra gravar/ler
// tarefas.recorrencia_dia_semana (o mesmo valor que
// gerar_tarefas_recorrentes() compara no banco).
const _diasSemanaPgDow = ['Domingo', 'Segunda', 'Terça', 'Quarta', 'Quinta', 'Sexta', 'Sábado'];

/// Fases 2-3 do módulo Planejamento (ver plano): CRUD de tarefas + seletor
/// de período dia/semana/mês. Recorrência/Sugestões/Metas entram nas fases
/// seguintes, como abas adicionais por cima desta base.
class PlanejamentoScreen extends StatefulWidget {
  const PlanejamentoScreen({super.key});

  @override
  State<PlanejamentoScreen> createState() => _PlanejamentoScreenState();
}

class _PlanejamentoScreenState extends State<PlanejamentoScreen> with SingleTickerProviderStateMixin {
  PeriodoSelecionado _periodo = PeriodoSelecionado(tipo: PeriodoPlanejamento.dia, referencia: DateTime.now());
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this)..addListener(() => setState(() {}));
    Provider.of<TarefaProvider>(context, listen: false).carregar();
    Provider.of<SugestaoPlanejamentoProvider>(context, listen: false).carregar();
    Provider.of<MetaFinanceiraProvider>(context, listen: false).carregar(_periodo);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _mudarTipoPeriodo(PeriodoPlanejamento tipo) {
    setState(() => _periodo = PeriodoSelecionado(tipo: tipo, referencia: _periodo.referencia));
    context.read<MetaFinanceiraProvider>().carregar(_periodo);
  }

  void _navegarPeriodo(int n) {
    setState(() => _periodo = _periodo.navegar(n));
    context.read<MetaFinanceiraProvider>().carregar(_periodo);
  }

  void _irParaHoje() {
    setState(() => _periodo = PeriodoSelecionado(tipo: _periodo.tipo, referencia: DateTime.now()));
    context.read<MetaFinanceiraProvider>().carregar(_periodo);
  }

  String _rotuloIntervalo() {
    final dateFormat = DateFormat('dd/MM');
    switch (_periodo.tipo) {
      case PeriodoPlanejamento.dia:
        return DateFormat('dd/MM/yyyy').format(_periodo.inicio);
      case PeriodoPlanejamento.semana:
        final fimInclusive = _periodo.fim.subtract(const Duration(days: 1));
        return '${dateFormat.format(_periodo.inicio)} - ${dateFormat.format(fimInclusive)}';
      case PeriodoPlanejamento.mes:
        return '${_mesesPorExtenso[_periodo.inicio.month - 1]} ${_periodo.inicio.year}';
    }
  }

  Future<void> _abrirFormulario({Tarefa? tarefa}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => _TarefaFormScreen(tarefa: tarefa)),
    );
  }

  Future<void> _alternarConcluida(Tarefa tarefa) async {
    final provider = context.read<TarefaProvider>();
    try {
      if (tarefa.concluida) {
        await provider.reabrir(tarefa.id!);
      } else {
        final usuarioId = context.read<AuthProvider>().usuarioAtual?.id;
        await provider.concluir(tarefa.id!, concluidaPor: usuarioId ?? '');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível atualizar a tarefa: $e')));
    }
  }

  Future<void> _excluir(Tarefa tarefa) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir tarefa'),
        content: Text('Excluir "${tarefa.titulo}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    try {
      await context.read<TarefaProvider>().excluir(tarefa.id!);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível excluir: $e')));
    }
  }

  Widget _cardTarefa(Tarefa tarefa) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Checkbox(
          value: tarefa.concluida,
          onChanged: (_) => _alternarConcluida(tarefa),
        ),
        title: Text(
          tarefa.titulo,
          style: tarefa.concluida ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
        ),
        subtitle: tarefa.descricao.isEmpty ? null : Text(tarefa.descricao, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'editar') _abrirFormulario(tarefa: tarefa);
            if (v == 'excluir') _excluir(tarefa);
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'editar', child: Text('Editar')),
            PopupMenuItem(value: 'excluir', child: Text('Excluir')),
          ],
        ),
        onTap: () => _abrirFormulario(tarefa: tarefa),
      ),
    );
  }

  /// No período "dia" a data já está implícita no cabeçalho, então a lista
  /// não repete data por card. Em "semana"/"mês" agrupa por dia com um
  /// cabeçalho de seção, pra não misturar tarefas de dias diferentes.
  List<Widget> _listaAgrupada(List<Tarefa> tarefas) {
    if (_periodo.tipo == PeriodoPlanejamento.dia) {
      return tarefas.map(_cardTarefa).toList();
    }

    final porDia = <DateTime, List<Tarefa>>{};
    for (final t in tarefas) {
      final chave = DateTime(t.data.year, t.data.month, t.data.day);
      porDia.putIfAbsent(chave, () => []).add(t);
    }
    final dias = porDia.keys.toList()..sort();
    final dateFormat = DateFormat('dd/MM');

    final widgets = <Widget>[];
    for (final dia in dias) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 4, left: 4),
          child: Text(
            '${_diasDaSemana[dia.weekday - 1]}, ${dateFormat.format(dia)}',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      );
      widgets.addAll(porDia[dia]!.map(_cardTarefa));
    }
    return widgets;
  }

  Widget _construirAbaTarefas(TarefaProvider provider) {
    final tarefasDoPeriodo = provider.tarefas.where((t) => _periodo.contem(t.data)).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: SegmentedButton<PeriodoPlanejamento>(
            segments: const [
              ButtonSegment(value: PeriodoPlanejamento.dia, label: Text('Dia')),
              ButtonSegment(value: PeriodoPlanejamento.semana, label: Text('Semana')),
              ButtonSegment(value: PeriodoPlanejamento.mes, label: Text('Mês')),
            ],
            selected: {_periodo.tipo},
            onSelectionChanged: (s) => _mudarTipoPeriodo(s.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _navegarPeriodo(-1)),
              TextButton(onPressed: _irParaHoje, child: Text(_rotuloIntervalo())),
              IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _navegarPeriodo(1)),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: provider.carregando
              ? const Center(child: CircularProgressIndicator())
              : provider.erro != null
                  ? EstadoErroLista(mensagem: provider.erro!, onTentarNovamente: provider.carregar)
                  : tarefasDoPeriodo.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.event_note_outlined,
                                  size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              const SizedBox(height: 16),
                              Text(
                                'Nenhuma tarefa neste período.',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: provider.carregar,
                          child: ListView(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            children: _listaAgrupada(tarefasDoPeriodo),
                          ),
                        ),
        ),
      ],
    );
  }

  Future<void> _adicionarSugestaoCompraAoPlano(SugestaoCompra sugestao) async {
    final empresaId = context.read<AuthProvider>().empresaId;
    final usuarioId = context.read<AuthProvider>().usuarioAtual?.id;
    if (empresaId == null) return;

    try {
      await context.read<TarefaProvider>().adicionar(
            Tarefa(
              titulo: 'Comprar: ${sugestao.produtoNome}',
              descricao:
                  'Sugestão automática — ${sugestao.quantidadeSugerida} un. de "${sugestao.fornecedorNome}" '
                  '(estoque atual: ${sugestao.estoqueAtual}).',
              data: DateTime.now(),
              origem: OrigemTarefa.sugestaoCompra,
              origemReferenciaId: sugestao.produtoId,
            ),
            criadoPor: usuarioId,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${sugestao.produtoNome}" adicionado ao plano de hoje.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível adicionar: $e')));
    }
  }

  Future<void> _adicionarSugestaoRecompraAoPlano(SugestaoRecompra sugestao) async {
    final usuarioId = context.read<AuthProvider>().usuarioAtual?.id;
    final tarefaProvider = context.read<TarefaProvider>();
    final sugestaoProvider = context.read<SugestaoPlanejamentoProvider>();

    try {
      await tarefaProvider.adicionar(
        Tarefa(
          titulo: 'Contatar: ${sugestao.nome}',
          descricao: 'Sugestão automática — ${sugestao.diasDesdeUltimaCompra.round()} dias sem comprar '
              '(telefone: ${sugestao.telefone}).',
          data: DateTime.now(),
          origem: OrigemTarefa.sugestaoRecompra,
          origemReferenciaId: sugestao.clienteId,
        ),
        criadoPor: usuarioId,
      );
      // Evita a mesma sugestão reaparecer amanhã (respeita o cooldown já
      // embutido na RPC clientes_devido_recompra).
      await sugestaoProvider.marcarRecompraLembrada(sugestao.clienteId);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('"${sugestao.nome}" adicionado ao plano de hoje.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível adicionar: $e')));
    }
  }

  Future<void> _adicionarContatoParadoAoPlano(SugestaoContatoParado contato) async {
    final usuarioId = context.read<AuthProvider>().usuarioAtual?.id;
    final tarefaProvider = context.read<TarefaProvider>();

    try {
      await tarefaProvider.adicionar(
        Tarefa(
          titulo: 'Fazer follow-up: ${contato.nomeWhatsapp}',
          descricao: 'Sugestão automática — contato da campanha "${contato.campanhaNome}", '
              'convite enviado há ${contato.diasParado.round()} dias sem ativar (telefone: ${contato.telefone}).',
          data: DateTime.now(),
          origem: OrigemTarefa.sugestaoCampanha,
          origemReferenciaId: contato.contatoId,
        ),
        criadoPor: usuarioId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('"${contato.nomeWhatsapp}" adicionado ao plano de hoje.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível adicionar: $e')));
    }
  }

  Future<void> _adicionarConteudoPendenteAoPlano(PostConteudoPendente post) async {
    final usuarioId = context.read<AuthProvider>().usuarioAtual?.id;
    final tarefaProvider = context.read<TarefaProvider>();

    try {
      await tarefaProvider.adicionar(
        Tarefa(
          titulo: 'Revisar conteúdo: ${post.tema ?? post.formato}',
          descricao: 'Sugestão automática — post do pilar "${post.pilar}" (${post.canal}) aguardando aprovação.',
          data: DateTime.now(),
          origem: OrigemTarefa.sugestaoConteudo,
          origemReferenciaId: post.id,
        ),
        criadoPor: usuarioId,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Adicionado ao plano de hoje.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível adicionar: $e')));
    }
  }

  Widget _construirAbaSugestoes(SugestaoPlanejamentoProvider provider) {
    if (provider.carregando) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: provider.carregar,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Text('Compras', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Produtos com estoque baixo pra reposição.',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          if (provider.erroCompra != null)
            EstadoErroLista(mensagem: provider.erroCompra!, onTentarNovamente: provider.carregar)
          else if (provider.sugestoesCompra.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Nenhuma sugestão de compra no momento.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            )
          else
            ...provider.sugestoesCompra.map(
              (s) => Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  title: Text(s.produtoNome),
                  subtitle: Text('${s.quantidadeSugerida} un. sugeridas • estoque atual: ${s.estoqueAtual}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.playlist_add),
                    tooltip: 'Adicionar ao plano',
                    onPressed: () => _adicionarSugestaoCompraAoPlano(s),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 20),
          Text('Recompra', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Clientes que provavelmente já precisam repor — baseado no intervalo médio de compra de cada um.',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          if (provider.erroRecompra != null)
            EstadoErroLista(mensagem: provider.erroRecompra!, onTentarNovamente: provider.carregar)
          else if (provider.sugestoesRecompra.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Nenhum cliente devido no momento.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            )
          else
            ...provider.sugestoesRecompra.map(
              (s) => Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  title: Text(s.nome),
                  subtitle: Text('${s.diasDesdeUltimaCompra.round()} dias sem comprar • ${s.telefone}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.playlist_add),
                    tooltip: 'Adicionar ao plano',
                    onPressed: () => _adicionarSugestaoRecompraAoPlano(s),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 20),
          Text('Campanhas', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Contatos convidados que nunca ativaram o cadastro (aproximado — o app não sabe se responderam).',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          if (provider.erroContatosParados != null)
            EstadoErroLista(mensagem: provider.erroContatosParados!, onTentarNovamente: provider.carregar)
          else if (provider.contatosParados.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Nenhum contato parado no momento.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            )
          else
            ...provider.contatosParados.map(
              (c) => Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  title: Text(c.nomeWhatsapp.isEmpty ? c.telefone : c.nomeWhatsapp),
                  subtitle: Text('${c.diasParado.round()} dias sem ativar • ${c.campanhaNome}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.playlist_add),
                    tooltip: 'Adicionar ao plano',
                    onPressed: () => _adicionarContatoParadoAoPlano(c),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 20),
          Text('Conteúdo Social', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            'Posts gerados pela automação de conteúdo aguardando aprovação.',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          if (provider.erroConteudoPendente != null)
            EstadoErroLista(mensagem: provider.erroConteudoPendente!, onTentarNovamente: provider.carregar)
          else if (provider.conteudoPendente.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: AvisoBanner(
                texto: 'Nenhum post pendente — a automação de conteúdo social ainda não está implantada em '
                    'produção, então esta seção fica vazia até lá.',
              ),
            )
          else
            ...provider.conteudoPendente.map(
              (p) => Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  title: Text(p.tema ?? p.formato),
                  subtitle: Text('${p.pilar} • ${p.canal}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.playlist_add),
                    tooltip: 'Adicionar ao plano',
                    onPressed: () => _adicionarConteudoPendenteAoPlano(p),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _editarMeta(MetaFinanceiraProvider provider) async {
    final controller = TextEditingController(
      text: provider.meta != null ? provider.meta!.valorMeta.toStringAsFixed(2).replaceAll('.', ',') : '',
    );
    final valor = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Meta de ${_periodo.rotulo.toLowerCase()}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Valor (R\$)', prefixText: 'R\$ '),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () {
              final texto = controller.text.trim().replaceAll('.', '').replaceAll(',', '.');
              Navigator.pop(ctx, double.tryParse(texto));
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (valor == null || !mounted) return;

    final usuarioId = context.read<AuthProvider>().usuarioAtual?.id;
    try {
      await provider.salvar(_periodo, valor, criadoPor: usuarioId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível salvar a meta: $e')));
    }
  }

  Widget _construirAbaMetas(MetaFinanceiraProvider provider, bool podeEditar) {
    if (provider.carregando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.erro != null) {
      return EstadoErroLista(mensagem: provider.erro!, onTentarNovamente: () => provider.carregar(_periodo));
    }

    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
    final valorMeta = provider.meta?.valorMeta ?? 0;
    final progresso = valorMeta > 0 ? (provider.realizado / valorMeta).clamp(0, 1).toDouble() : 0.0;

    return RefreshIndicator(
      onRefresh: () => provider.carregar(_periodo),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Meta de ${_periodo.rotulo.toLowerCase()}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  if (valorMeta <= 0)
                    Text(
                      'Nenhuma meta definida pra este período.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    )
                  else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Realizado: ${currencyFormat.format(provider.realizado)}'),
                        Text('Meta: ${currencyFormat.format(valorMeta)}'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(value: progresso, minHeight: 10),
                    ),
                    const SizedBox(height: 4),
                    Text('${(progresso * 100).round()}% da meta'),
                  ],
                  if (podeEditar) ...[
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => _editarMeta(provider),
                      icon: const Icon(Icons.edit_outlined),
                      label: Text(valorMeta > 0 ? 'Editar meta' : 'Definir meta'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tarefaProvider = context.watch<TarefaProvider>();
    final sugestaoProvider = context.watch<SugestaoPlanejamentoProvider>();
    final metaProvider = context.watch<MetaFinanceiraProvider>();
    final podeEditarMeta = context.watch<AuthProvider>().isDono || context.watch<AuthProvider>().isGerente;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Planejamento'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Tarefas'),
            Tab(text: 'Sugestões'),
            Tab(text: 'Metas'),
          ],
        ),
      ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton(
              onPressed: () => _abrirFormulario(),
              child: const Icon(Icons.add),
            )
          : null,
      body: TabBarView(
        controller: _tabController,
        children: [
          _construirAbaTarefas(tarefaProvider),
          _construirAbaSugestoes(sugestaoProvider),
          _construirAbaMetas(metaProvider, podeEditarMeta),
        ],
      ),
    );
  }
}

class _TarefaFormScreen extends StatefulWidget {
  final Tarefa? tarefa;

  const _TarefaFormScreen({this.tarefa});

  @override
  State<_TarefaFormScreen> createState() => _TarefaFormScreenState();
}

class _TarefaFormScreenState extends State<_TarefaFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _tituloController;
  late final TextEditingController _descricaoController;
  late final TextEditingController _dataController;
  late final TextEditingController _recorrenciaDiaMesController;
  late bool _recorrente;
  late String _recorrenciaTipo;
  late int _recorrenciaDiaSemana; // convenção Postgres dow, ver _diasSemanaPgDow
  bool _salvando = false;

  bool get _editando => widget.tarefa != null;

  @override
  void initState() {
    super.initState();
    final t = widget.tarefa;
    _tituloController = TextEditingController(text: t?.titulo ?? '');
    _descricaoController = TextEditingController(text: t?.descricao ?? '');
    final dataInicial = t?.data ?? DateTime.now();
    _dataController = TextEditingController(text: _formatarData(dataInicial));
    _recorrente = t?.recorrente ?? false;
    _recorrenciaTipo = t?.recorrenciaTipo ?? RecorrenciaTarefa.diaria;
    // % 7 converte DateTime.weekday (1=segunda..7=domingo) pra dow do
    // Postgres (0=domingo..6=sábado): domingo(7)%7=0, os demais mantêm -1.
    _recorrenciaDiaSemana = t?.recorrenciaDiaSemana ?? (dataInicial.weekday % 7);
    _recorrenciaDiaMesController = TextEditingController(
      text: (t?.recorrenciaDiaMes ?? dataInicial.day.clamp(1, 28)).toString(),
    );
  }

  @override
  void dispose() {
    _tituloController.dispose();
    _descricaoController.dispose();
    _dataController.dispose();
    _recorrenciaDiaMesController.dispose();
    super.dispose();
  }

  String _formatarData(DateTime data) =>
      '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}';

  DateTime? _parsearData(String? texto) {
    if (texto == null) return null;
    final partes = texto.trim().split('/');
    if (partes.length != 3) return null;
    final dia = int.tryParse(partes[0]);
    final mes = int.tryParse(partes[1]);
    final ano = int.tryParse(partes[2]);
    if (dia == null || mes == null || ano == null) return null;
    try {
      final data = DateTime(ano, mes, dia);
      if (data.day != dia || data.month != mes || data.year != ano) return null;
      return data;
    } catch (_) {
      return null;
    }
  }

  Future<void> _selecionarData() async {
    final atual = _parsearData(_dataController.text) ?? DateTime.now();
    final escolhida = await showDatePicker(
      context: context,
      initialDate: atual,
      firstDate: DateTime(atual.year - 1),
      lastDate: DateTime(atual.year + 2),
    );
    if (escolhida != null) {
      setState(() => _dataController.text = _formatarData(escolhida));
    }
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    final data = _parsearData(_dataController.text);
    if (data == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data inválida.')));
      return;
    }

    setState(() => _salvando = true);

    final tarefa = Tarefa(
      id: widget.tarefa?.id,
      titulo: _tituloController.text.trim(),
      descricao: _descricaoController.text.trim(),
      data: data,
      concluida: widget.tarefa?.concluida ?? false,
      concluidaEm: widget.tarefa?.concluidaEm,
      concluidaPor: widget.tarefa?.concluidaPor,
      atribuidoA: widget.tarefa?.atribuidoA,
      recorrente: _recorrente,
      recorrenciaTipo: _recorrente ? _recorrenciaTipo : null,
      recorrenciaDiaSemana: _recorrente && _recorrenciaTipo == RecorrenciaTarefa.semanal ? _recorrenciaDiaSemana : null,
      recorrenciaDiaMes: _recorrente && _recorrenciaTipo == RecorrenciaTarefa.mensal
          ? int.tryParse(_recorrenciaDiaMesController.text.trim())
          : null,
    );

    try {
      final provider = context.read<TarefaProvider>();
      if (_editando) {
        await provider.atualizar(tarefa);
      } else {
        final criadoPor = context.read<AuthProvider>().usuarioAtual?.id;
        await provider.adicionar(tarefa, criadoPor: criadoPor);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar tarefa: $e')));
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar Tarefa' : 'Nova Tarefa')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FormSection(
                titulo: 'Dados da tarefa',
                children: [
                  TextFormField(
                    controller: _tituloController,
                    decoration: const InputDecoration(labelText: 'Título'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe o título' : null,
                  ),
                  TextFormField(
                    controller: _dataController,
                    decoration: const InputDecoration(labelText: 'Data', hintText: 'DD/MM/AAAA'),
                    readOnly: true,
                    onTap: _selecionarData,
                    validator: (v) => _parsearData(v) == null ? 'Data inválida' : null,
                  ),
                  TextFormField(
                    controller: _descricaoController,
                    decoration: const InputDecoration(labelText: 'Descrição (Opcional)'),
                    maxLines: 3,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FormSection(
                titulo: 'Recorrência',
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tarefa recorrente'),
                    subtitle: const Text('Gera a próxima ocorrência sozinha (diária/semanal/mensal)'),
                    value: _recorrente,
                    onChanged: (v) => setState(() => _recorrente = v),
                  ),
                  if (_recorrente) ...[
                    DropdownButtonFormField<String>(
                      initialValue: _recorrenciaTipo,
                      decoration: const InputDecoration(labelText: 'Repete'),
                      items: const [
                        DropdownMenuItem(value: RecorrenciaTarefa.diaria, child: Text('Todo dia')),
                        DropdownMenuItem(value: RecorrenciaTarefa.semanal, child: Text('Toda semana')),
                        DropdownMenuItem(value: RecorrenciaTarefa.mensal, child: Text('Todo mês')),
                      ],
                      onChanged: (v) => setState(() => _recorrenciaTipo = v!),
                    ),
                    if (_recorrenciaTipo == RecorrenciaTarefa.semanal)
                      DropdownButtonFormField<int>(
                        initialValue: _recorrenciaDiaSemana,
                        decoration: const InputDecoration(labelText: 'Dia da semana'),
                        items: List.generate(
                          7,
                          (i) => DropdownMenuItem(value: i, child: Text(_diasSemanaPgDow[i])),
                        ),
                        onChanged: (v) => setState(() => _recorrenciaDiaSemana = v!),
                      ),
                    if (_recorrenciaTipo == RecorrenciaTarefa.mensal)
                      TextFormField(
                        controller: _recorrenciaDiaMesController,
                        decoration: const InputDecoration(
                          labelText: 'Dia do mês',
                          helperText: 'De 1 a 28 — evita ambiguidade em meses mais curtos',
                        ),
                        keyboardType: TextInputType.number,
                        validator: (v) {
                          if (!_recorrente || _recorrenciaTipo != RecorrenciaTarefa.mensal) return null;
                          final dia = int.tryParse(v?.trim() ?? '');
                          if (dia == null || dia < 1 || dia > 28) return 'Informe um dia entre 1 e 28';
                          return null;
                        },
                      ),
                  ],
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _salvando ? null : _salvar,
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                child: _salvando
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary),
                      )
                    : const Text('Salvar'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
