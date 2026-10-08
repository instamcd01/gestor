import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/supabase_config.dart';
import '../providers/auth_provider.dart';
import '../widgets/estado_erro_lista.dart';

String _moeda(num? v) => v == null ? '—' : 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

/// Ordem em que os tipos aparecem na aba "Por tipo" — do que mais gira num
/// pet shop de bairro pro que menos gira.
const _ordemTipos = [
  'Ração',
  'Alimento úmido',
  'Petiscos',
  'Farmácia e saúde',
  'Areia',
  'Tapete higiênico',
  'Banho e perfume',
  'Limpeza e pragas',
  'Comer e beber (comedouro, bebedouro, fonte)',
  'Passeio (coleira, guia, peitoral)',
  'Brinquedos',
  'Camas e conforto',
  'Banheiro (caixa, bandeja, pá)',
  'Arranhador',
  'Escovar e tirar pelos',
  'Higiene bucal',
  'Unhas e tosa',
  'Transporte',
  'Roupas e moda',
  'Fraldas e lenços',
  'Casinha, portão e cercado',
  'Educadores e treino',
  'Pássaros',
  'Peixes e aquário',
  'Roedores e outros',
];

class _DistDaMarca {
  final String distribuidorId;
  final String nome;
  final bool seu;
  final String situacao; // compra | confirmado | a_confirmar
  final int? produtosComprados;
  final double? custoMedio;
  final String? telefone;
  final String? site;
  final String? fonte;

  _DistDaMarca.fromJson(Map<String, dynamic> j)
      : distribuidorId = j['distribuidor_id'] as String,
        nome = j['nome'] as String,
        seu = j['seu'] == true,
        situacao = j['situacao'] as String? ?? 'a_confirmar',
        produtosComprados = (j['produtos_comprados'] as num?)?.toInt(),
        custoMedio = (j['custo_medio'] as num?)?.toDouble(),
        telefone = j['telefone'] as String?,
        site = j['site'] as String?,
        fonte = j['fonte'] as String?;
}

class _Marca {
  final String id;
  final String nome;
  final String? fabricante;
  final String? segmento;
  final List<String> necessidades;
  final List<String> especies;
  final int voceProdutos;
  final int voceComEstoque;
  final int voceVendas90d;
  final int regiaoItens;
  final int regiaoLojas;
  final double? precoMin;
  final double? precoMax;
  final bool emAlta;
  final List<_DistDaMarca> distribuidores;

  _Marca.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        nome = j['nome'] as String,
        fabricante = j['fabricante'] as String?,
        segmento = j['segmento'] as String?,
        necessidades = List<String>.from(j['necessidades'] as List? ?? const []),
        especies = List<String>.from(j['especies'] as List? ?? const []),
        voceProdutos = (j['voce_produtos'] as num?)?.toInt() ?? 0,
        voceComEstoque = (j['voce_com_estoque'] as num?)?.toInt() ?? 0,
        voceVendas90d = (j['voce_vendas_90d'] as num?)?.toInt() ?? 0,
        regiaoItens = (j['regiao_itens'] as num?)?.toInt() ?? 0,
        regiaoLojas = (j['regiao_lojas'] as num?)?.toInt() ?? 0,
        precoMin = (j['regiao_preco_min'] as num?)?.toDouble(),
        precoMax = (j['regiao_preco_max'] as num?)?.toDouble(),
        emAlta = j['em_alta'] == true,
        distribuidores = ((j['distribuidores'] as List?) ?? const [])
            .map((d) => _DistDaMarca.fromJson(d as Map<String, dynamic>))
            .toList();

  bool get vende => voceProdutos > 0;
  bool get temFornecedorSeu => distribuidores.any((d) => d.seu);
  bool get compra => distribuidores.any((d) => d.situacao == 'compra');
}

class _Distribuidor {
  final String id;
  final String nome;
  final String? fornecedorId;
  final String tipo;
  final String? cidade;
  final String? endereco;
  final String? regiaoAtendida;
  final String? telefone;
  final String? whatsapp;
  final String? email;
  final String? site;
  final String? pedidoMinimo;
  final String? prazoEntrega;
  final String? prazoPagamento;
  final String? observacoes;
  final String situacao;
  final String? fonte;
  final List<String> necessidades;
  final List<Map<String, dynamic>> marcas;

  _Distribuidor.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        nome = j['nome'] as String,
        fornecedorId = j['fornecedor_id'] as String?,
        tipo = j['tipo'] as String? ?? 'distribuidor',
        cidade = j['cidade'] as String?,
        endereco = j['endereco'] as String?,
        regiaoAtendida = j['regiao_atendida'] as String?,
        telefone = j['telefone'] as String?,
        whatsapp = j['whatsapp'] as String?,
        email = j['email'] as String?,
        site = j['site'] as String?,
        pedidoMinimo = j['pedido_minimo'] as String?,
        prazoEntrega = j['prazo_entrega'] as String?,
        prazoPagamento = j['prazo_pagamento'] as String?,
        observacoes = j['observacoes'] as String?,
        situacao = j['situacao'] as String? ?? 'a_contatar',
        fonte = j['fonte'] as String?,
        necessidades = List<String>.from(j['necessidades'] as List? ?? const []),
        marcas = List<Map<String, dynamic>>.from(j['marcas'] as List? ?? const []);

  bool get seu => fornecedorId != null;
}

class _Tendencia {
  final String id;
  final String titulo;
  final String? descricao;
  final String? necessidade;
  final int pontuacao;
  final List<Map<String, dynamic>> fontes;
  final String? faixaPreco;
  final int? lojasRegiao;
  final String status;
  final String? marcaId;

  _Tendencia.fromJson(Map<String, dynamic> j)
      : id = j['id'] as String,
        titulo = j['titulo'] as String,
        descricao = j['descricao'] as String?,
        necessidade = j['necessidade'] as String?,
        pontuacao = (j['pontuacao'] as num?)?.toInt() ?? 0,
        fontes = List<Map<String, dynamic>>.from(j['fontes'] as List? ?? const []),
        faixaPreco = j['faixa_preco'] as String?,
        lojasRegiao = (j['lojas_regiao'] as num?)?.toInt(),
        status = j['status'] as String? ?? 'nova',
        marcaId = j['marca_id'] as String?;
}

/// Guia de onde comprar: o mercado pet inteiro (o que você vende, o que vende
/// na região, marcas nacionais e o que está em alta) e quem distribui cada
/// marca. "Você compra" sai das notas e do cadastro de fornecedores; o resto
/// veio de pesquisa e nasce "a confirmar" até alguém falar com o fornecedor.
class OndeComprarScreen extends StatefulWidget {
  const OndeComprarScreen({super.key});

  @override
  State<OndeComprarScreen> createState() => _OndeComprarScreenState();
}

class _OndeComprarScreenState extends State<OndeComprarScreen> {
  List<_Marca> _marcas = [];
  List<_Distribuidor> _distribuidores = [];
  List<_Tendencia> _tendencias = [];
  bool _carregando = true;
  bool _recalculando = false;
  String? _erro;

  final _busca = TextEditingController();
  bool _soNaoVendo = false;
  bool _soRegiao = false;
  bool _soFornecedorSeu = false;
  bool _mostrarDescartadas = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final resultados = await Future.wait<dynamic>([
        supabase.rpc('guia_marcas_resumo'),
        supabase.rpc('guia_distribuidores_resumo'),
        supabase.from('guia_tendencias').select().order('pontuacao', ascending: false),
      ]);
      if (!mounted) return;
      setState(() {
        _marcas = (resultados[0] as List).map((r) => _Marca.fromJson(r as Map<String, dynamic>)).toList()
          ..sort((a, b) => b.regiaoItens.compareTo(a.regiaoItens) != 0
              ? b.regiaoItens.compareTo(a.regiaoItens)
              : a.nome.compareTo(b.nome));
        _distribuidores =
            (resultados[1] as List).map((r) => _Distribuidor.fromJson(r as Map<String, dynamic>)).toList();
        _tendencias = (resultados[2] as List).map((r) => _Tendencia.fromJson(r as Map<String, dynamic>)).toList();
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Erro ao carregar o guia: $e';
        _carregando = false;
      });
    }
  }

  /// Recalcula quais produtos (seus e da região) são de cada marca — rodar
  /// depois de cadastrar marca nova ou de uma coleta nova dos concorrentes.
  Future<void> _recalcular() async {
    setState(() => _recalculando = true);
    try {
      await supabase.rpc('guia_atualizar_presenca');
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível atualizar: $e')));
      }
    } finally {
      if (mounted) setState(() => _recalculando = false);
    }
  }

  bool _passaFiltros(_Marca m) {
    final termo = _busca.text.trim().toLowerCase();
    if (termo.isNotEmpty &&
        !m.nome.toLowerCase().contains(termo) &&
        !(m.fabricante ?? '').toLowerCase().contains(termo) &&
        !m.distribuidores.any((d) => d.nome.toLowerCase().contains(termo))) {
      return false;
    }
    if (_soNaoVendo && m.vende) return false;
    if (_soRegiao && m.regiaoLojas == 0) return false;
    if (_soFornecedorSeu && !m.temFornecedorSeu) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Onde Comprar'),
          actions: [
            IconButton(
              tooltip: 'Recalcular marcas dos produtos',
              onPressed: _recalculando ? null : _recalcular,
              icon: _recalculando
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabs: [Tab(text: 'Por tipo'), Tab(text: 'Por marca'), Tab(text: 'Por fornecedor'), Tab(text: 'Em alta')],
          ),
        ),
        body: _carregando && _marcas.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : _erro != null && _marcas.isEmpty
                ? EstadoErroLista(mensagem: _erro!, onTentarNovamente: _carregar)
                : TabBarView(
                    children: [_abaPorTipo(context), _abaPorMarca(context), _abaPorFornecedor(context), _abaEmAlta(context)],
                  ),
      ),
    );
  }

  Widget _barraFiltros(BuildContext context, {bool mostrarChips = true}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _busca,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Buscar marca, fabricante ou fornecedor',
              prefixIcon: const Icon(Icons.search),
              isDense: true,
              suffixIcon: _busca.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () => setState(_busca.clear),
                    ),
            ),
          ),
          if (mostrarChips) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                FilterChip(
                  label: const Text('Só o que não vendo'),
                  selected: _soNaoVendo,
                  onSelected: (v) => setState(() => _soNaoVendo = v),
                ),
                FilterChip(
                  label: const Text('Vende na região'),
                  selected: _soRegiao,
                  onSelected: (v) => setState(() => _soRegiao = v),
                ),
                FilterChip(
                  label: const Text('Tem fornecedor meu'),
                  selected: _soFornecedorSeu,
                  onSelected: (v) => setState(() => _soFornecedorSeu = v),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- Por tipo

  Widget _abaPorTipo(BuildContext context) {
    final filtradas = _marcas.where(_passaFiltros).toList();
    final tipos = <String>[
      ..._ordemTipos,
      ...{for (final m in filtradas) ...m.necessidades}.where((t) => !_ordemTipos.contains(t)),
    ];
    final colorScheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _barraFiltros(context),
          for (final tipo in tipos)
            Builder(builder: (context) {
              final marcas = filtradas.where((m) => m.necessidades.contains(tipo)).toList();
              final dists = _distribuidores.where((d) => d.necessidades.contains(tipo) && d.situacao != 'descartado').toList();
              if (marcas.isEmpty && dists.isEmpty) return const SizedBox.shrink();
              final vendo = marcas.where((m) => m.vende).length;
              return Card(
                margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  title: Text(tipo, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${marcas.length} marcas · você vende $vendo · ${dists.length} fornecedores'),
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  children: [
                    if (dists.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Quem trabalha esse tipo',
                                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final d in dists)
                                  ActionChip(
                                    avatar: Icon(d.seu ? Icons.verified_outlined : Icons.storefront_outlined, size: 16),
                                    label: Text(d.nome),
                                    onPressed: () => _abrirDistribuidor(context, d),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    for (final m in marcas) _linhaMarca(context, m),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- Por marca

  Widget _abaPorMarca(BuildContext context) {
    final filtradas = _marcas.where(_passaFiltros).toList();
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _barraFiltros(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text('${filtradas.length} marcas',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          for (final m in filtradas) _linhaMarca(context, m),
        ],
      ),
    );
  }

  Widget _chipSituacao(BuildContext context, String situacao) {
    final colorScheme = Theme.of(context).colorScheme;
    final (texto, cor) = switch (situacao) {
      'compra' => ('Você compra', Colors.green),
      'confirmado' => ('Vende', colorScheme.primary),
      'nao_vende' => ('Não vende', colorScheme.outline),
      _ => ('A confirmar', Colors.orange),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: cor.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
      child: Text(texto, style: TextStyle(fontSize: 11.5, color: cor, fontWeight: FontWeight.w600)),
    );
  }

  Widget _linhaMarca(BuildContext context, _Marca m) {
    final colorScheme = Theme.of(context).colorScheme;
    final melhor = m.distribuidores.isNotEmpty ? m.distribuidores.first : null;
    final detalhes = [
      if (m.fabricante != null && m.fabricante != m.nome) m.fabricante!,
      m.vende ? 'você vende ${m.voceProdutos}' : 'você não vende',
      if (m.regiaoLojas > 0) 'região: ${m.regiaoItens} itens em ${m.regiaoLojas} ${m.regiaoLojas == 1 ? 'loja' : 'lojas'}',
    ].join(' · ');
    return ListTile(
      dense: true,
      onTap: () => _abrirMarca(context, m),
      title: Row(
        children: [
          Flexible(child: Text(m.nome, style: const TextStyle(fontWeight: FontWeight.w600))),
          if (m.emAlta) ...[
            const SizedBox(width: 6),
            Icon(Icons.trending_up, size: 16, color: colorScheme.tertiary),
          ],
        ],
      ),
      subtitle: Text(detalhes),
      trailing: melhor == null
          ? Text('sem fornecedor', style: TextStyle(fontSize: 11.5, color: colorScheme.error))
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _chipSituacao(context, melhor.situacao),
                const SizedBox(height: 2),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 140),
                  child: Text(
                    m.distribuidores.length > 1 ? '${melhor.nome} +${m.distribuidores.length - 1}' : melhor.nome,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
    );
  }

  // ---------------------------------------------------------- Por fornecedor

  Widget _abaPorFornecedor(BuildContext context) {
    final termo = _busca.text.trim().toLowerCase();
    final lista = _distribuidores.where((d) {
      if (termo.isEmpty) return true;
      return d.nome.toLowerCase().contains(termo) ||
          d.marcas.any((m) => (m['nome'] as String).toLowerCase().contains(termo)) ||
          d.necessidades.any((n) => n.toLowerCase().contains(termo));
    }).toList();
    final seus = lista.where((d) => d.seu).toList();
    final outros = lista.where((d) => !d.seu && d.situacao != 'descartado').toList();
    final descartados = lista.where((d) => !d.seu && d.situacao == 'descartado').toList();
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          _barraFiltros(context, mostrarChips: false),
          if (seus.isNotEmpty) _tituloGrupo(context, 'Seus fornecedores (${seus.length})'),
          for (final d in seus) _cardDistribuidor(context, d),
          if (outros.isNotEmpty) _tituloGrupo(context, 'Para cotar (${outros.length})'),
          for (final d in outros) _cardDistribuidor(context, d),
          if (descartados.isNotEmpty) _tituloGrupo(context, 'Descartados (${descartados.length})'),
          for (final d in descartados) _cardDistribuidor(context, d),
        ],
      ),
    );
  }

  Widget _tituloGrupo(BuildContext context, String texto) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(texto, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      );

  String _rotuloSituacaoDist(_Distribuidor d) {
    if (d.seu) return 'Seu fornecedor';
    return switch (d.situacao) {
      'em_contato' => 'Em contato',
      'aprovado' => 'Aprovado',
      'descartado' => 'Descartado',
      _ => d.tipo == 'fabricante' ? 'Fabricante · a contatar' : 'A contatar',
    };
  }

  Widget _cardDistribuidor(BuildContext context, _Distribuidor d) {
    final colorScheme = Theme.of(context).colorScheme;
    final nomesMarcas = d.marcas.map((m) => m['nome'] as String).toList();
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: ListTile(
        onTap: () => _abrirDistribuidor(context, d),
        leading: Icon(d.seu ? Icons.verified_outlined : (d.tipo == 'fabricante' ? Icons.factory_outlined : Icons.storefront_outlined),
            color: d.seu ? Colors.green : colorScheme.onSurfaceVariant),
        title: Text(d.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text([
          _rotuloSituacaoDist(d),
          if (d.cidade != null) d.cidade!,
          if (nomesMarcas.isNotEmpty)
            'vende ${nomesMarcas.take(4).join(', ')}${nomesMarcas.length > 4 ? ' +${nomesMarcas.length - 4}' : ''}'
          else if (d.necessidades.isNotEmpty)
            d.necessidades.take(3).join(', '),
        ].join(' · ')),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }

  // ----------------------------------------------------------------- Em alta

  Widget _abaEmAlta(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final lista = _tendencias.where((t) => _mostrarDescartadas || t.status != 'descartada').toList();
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Text(
            'Produtos e tipos que estão crescendo em buscas e vendas (Mercado Livre, Amazon, Google, '
            'redes sociais e lojas da região). Quanto maior a nota, mais fontes concordam.',
            style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Mostrar descartadas'),
            value: _mostrarDescartadas,
            onChanged: (v) => setState(() => _mostrarDescartadas = v),
          ),
          if (lista.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text('Nenhuma tendência registrada ainda.',
                  textAlign: TextAlign.center, style: TextStyle(color: colorScheme.onSurfaceVariant)),
            ),
          for (final t in lista) _cardTendencia(context, t),
        ],
      ),
    );
  }

  Widget _cardTendencia(BuildContext context, _Tendencia t) {
    final colorScheme = Theme.of(context).colorScheme;
    final marca = t.marcaId == null ? null : _marcas.where((m) => m.id == t.marcaId).firstOrNull;
    final descartada = t.status == 'descartada';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: descartada ? 0.55 : 1,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(t.titulo, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorScheme.tertiaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('nota ${t.pontuacao}',
                        style: TextStyle(fontSize: 12, color: colorScheme.onTertiaryContainer, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              if (t.descricao != null) ...[
                const SizedBox(height: 4),
                Text(t.descricao!, style: const TextStyle(fontSize: 13)),
              ],
              const SizedBox(height: 6),
              Text(
                [
                  if (t.necessidade != null) t.necessidade!,
                  if (t.faixaPreco != null) t.faixaPreco!,
                  if (t.lojasRegiao != null)
                    t.lojasRegiao == 0 ? 'nenhuma loja vizinha vende ainda' : '${t.lojasRegiao} lojas vizinhas vendem',
                ].join(' · '),
                style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
              ),
              if (t.fontes.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final f in t.fontes)
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        label: Text('${f['fonte'] ?? 'fonte'}${f['sinal'] != null ? ': ${f['sinal']}' : ''}',
                            style: const TextStyle(fontSize: 12)),
                        onPressed: f['url'] == null ? null : () => _abrirLink(f['url'] as String),
                      ),
                  ],
                ),
              ],
              Row(
                children: [
                  if (marca != null)
                    TextButton.icon(
                      onPressed: () => _abrirMarca(context, marca),
                      icon: const Icon(Icons.local_offer_outlined, size: 16),
                      label: Text('Ver ${marca.nome}'),
                    ),
                  const Spacer(),
                  if (t.status != 'interessa')
                    TextButton(onPressed: () => _marcarTendencia(t, 'interessa'), child: const Text('Interessa')),
                  if (t.status == 'interessa')
                    TextButton(onPressed: () => _marcarTendencia(t, 'nova'), child: const Text('Tirar interesse')),
                  if (!descartada)
                    TextButton(onPressed: () => _marcarTendencia(t, 'descartada'), child: const Text('Descartar'))
                  else
                    TextButton(onPressed: () => _marcarTendencia(t, 'nova'), child: const Text('Restaurar')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _marcarTendencia(_Tendencia t, String status) async {
    try {
      await supabase.from('guia_tendencias').update({'status': status}).eq('id', t.id);
      await _carregar();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível salvar: $e')));
    }
  }

  // ---------------------------------------------------------------- Detalhes

  Future<void> _abrirLink(String url) async {
    final uri = Uri.tryParse(url.startsWith('http') ? url : 'https://$url');
    if (uri == null || !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível abrir $url')));
    }
  }

  Future<void> _copiar(String texto) async {
    await Clipboard.setData(ClipboardData(text: texto));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copiado: $texto')));
  }

  Future<void> _abrirMarca(BuildContext context, _Marca m) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => _DetalheMarca(
          marca: m,
          distribuidores: _distribuidores,
          controller: scroll,
          onAlterado: _carregar,
          onAbrirDistribuidor: (d) {
            Navigator.pop(ctx);
            _abrirDistribuidor(context, d);
          },
          chipSituacao: (s) => _chipSituacao(ctx, s),
          abrirLink: _abrirLink,
        ),
      ),
    );
  }

  Future<void> _abrirDistribuidor(BuildContext context, _Distribuidor d) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => _DetalheDistribuidor(
          distribuidor: d,
          controller: scroll,
          onAlterado: _carregar,
          rotuloSituacao: _rotuloSituacaoDist(d),
          chipSituacao: (s) => _chipSituacao(ctx, s),
          abrirLink: _abrirLink,
          copiar: _copiar,
          onAbrirMarca: (marcaId) {
            final marca = _marcas.where((m) => m.id == marcaId).firstOrNull;
            if (marca == null) return;
            Navigator.pop(ctx);
            _abrirMarca(context, marca);
          },
        ),
      ),
    );
  }
}

class _DetalheMarca extends StatelessWidget {
  final _Marca marca;
  final List<_Distribuidor> distribuidores;
  final ScrollController controller;
  final Future<void> Function() onAlterado;
  final void Function(_Distribuidor) onAbrirDistribuidor;
  final Widget Function(String) chipSituacao;
  final Future<void> Function(String) abrirLink;

  const _DetalheMarca({
    required this.marca,
    required this.distribuidores,
    required this.controller,
    required this.onAlterado,
    required this.onAbrirDistribuidor,
    required this.chipSituacao,
    required this.abrirLink,
  });

  Future<void> _definirVinculo(BuildContext context, String distribuidorId, String situacao) async {
    final empresaId = context.read<AuthProvider>().empresaId;
    try {
      await supabase.from('guia_marca_distribuidor').upsert({
        'empresa_id': empresaId,
        'marca_id': marca.id,
        'distribuidor_id': distribuidorId,
        'situacao': situacao,
      }, onConflict: 'marca_id,distribuidor_id');
      if (context.mounted) Navigator.pop(context);
      await onAlterado();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível salvar: $e')));
      }
    }
  }

  Future<void> _adicionarDistribuidor(BuildContext context) async {
    final jaLigados = marca.distribuidores.map((d) => d.distribuidorId).toSet();
    final opcoes = distribuidores.where((d) => !jaLigados.contains(d.id) && d.situacao != 'descartado').toList();
    final escolhido = await showDialog<_Distribuidor>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Quem vende ${marca.nome}?'),
        children: [
          for (final d in opcoes)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, d),
              child: Text(d.seu ? '${d.nome} (seu fornecedor)' : d.nome),
            ),
        ],
      ),
    );
    if (escolhido == null || !context.mounted) return;
    await _definirVinculo(context, escolhido.id, 'confirmado');
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final m = marca;
    Widget dado(String rotulo, String valor) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rotulo, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
              Text(valor, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
          ),
        );
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text(m.nome, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        Text(
          [if (m.fabricante != null) m.fabricante!, if (m.segmento != null) m.segmento!, if (m.especies.isNotEmpty) m.especies.join(', ')]
              .join(' · '),
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Row(children: [
          dado('Você vende', m.vende ? '${m.voceProdutos} (${m.voceComEstoque} c/ estoque)' : 'nada'),
          dado('Vendas 90 dias', '${m.voceVendas90d}'),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          dado('Na região', m.regiaoLojas == 0 ? 'nenhuma loja' : '${m.regiaoItens} itens em ${m.regiaoLojas} lojas'),
          dado('Preço na região', m.precoMin == null ? '—' : '${_moeda(m.precoMin)} – ${_moeda(m.precoMax)}'),
        ]),
        if (m.necessidades.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final n in m.necessidades) Chip(label: Text(n), visualDensity: VisualDensity.compact)]),
        ],
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(child: Text('Onde comprar', style: Theme.of(context).textTheme.titleMedium)),
            TextButton.icon(
              onPressed: () => _adicionarDistribuidor(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Adicionar'),
            ),
          ],
        ),
        if (m.distribuidores.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Nenhum fornecedor encontrado para esta marca. Veja na aba "Por tipo" quem trabalha produtos desse tipo, '
              'ou pergunte aos seus fornecedores atuais.',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
        for (final d in m.distribuidores)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 8, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            final dist = distribuidores.where((x) => x.id == d.distribuidorId).firstOrNull;
                            if (dist != null) onAbrirDistribuidor(dist);
                          },
                          child: Text(d.nome, style: const TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ),
                      chipSituacao(d.situacao),
                    ],
                  ),
                  if (d.situacao == 'compra')
                    Text('${d.produtosComprados ?? 0} produtos comprados · custo médio ${_moeda(d.custoMedio)}',
                        style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant)),
                  if (d.fonte != null && d.situacao != 'compra')
                    Text(d.fonte!, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
                  if (d.situacao != 'compra')
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (d.situacao != 'confirmado')
                          TextButton(onPressed: () => _definirVinculo(context, d.distribuidorId, 'confirmado'), child: const Text('Confirmar')),
                        TextButton(onPressed: () => _definirVinculo(context, d.distribuidorId, 'nao_vende'), child: const Text('Não vende')),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _DetalheDistribuidor extends StatelessWidget {
  final _Distribuidor distribuidor;
  final ScrollController controller;
  final Future<void> Function() onAlterado;
  final String rotuloSituacao;
  final Widget Function(String) chipSituacao;
  final Future<void> Function(String) abrirLink;
  final Future<void> Function(String) copiar;
  final void Function(String marcaId) onAbrirMarca;

  const _DetalheDistribuidor({
    required this.distribuidor,
    required this.controller,
    required this.onAlterado,
    required this.rotuloSituacao,
    required this.chipSituacao,
    required this.abrirLink,
    required this.copiar,
    required this.onAbrirMarca,
  });

  Future<void> _mudarSituacao(BuildContext context, String situacao) async {
    try {
      await supabase.from('guia_distribuidores').update({'situacao': situacao}).eq('id', distribuidor.id);
      if (context.mounted) Navigator.pop(context);
      await onAlterado();
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível salvar: $e')));
    }
  }

  Future<void> _editar(BuildContext context) async {
    final d = distribuidor;
    final campos = <String, TextEditingController>{
      'telefone': TextEditingController(text: d.telefone ?? ''),
      'whatsapp': TextEditingController(text: d.whatsapp ?? ''),
      'email': TextEditingController(text: d.email ?? ''),
      'site': TextEditingController(text: d.site ?? ''),
      'pedido_minimo': TextEditingController(text: d.pedidoMinimo ?? ''),
      'prazo_entrega': TextEditingController(text: d.prazoEntrega ?? ''),
      'prazo_pagamento': TextEditingController(text: d.prazoPagamento ?? ''),
      'observacoes': TextEditingController(text: d.observacoes ?? ''),
    };
    const rotulos = {
      'telefone': 'Telefone',
      'whatsapp': 'WhatsApp',
      'email': 'E-mail',
      'site': 'Site',
      'pedido_minimo': 'Pedido mínimo',
      'prazo_entrega': 'Prazo de entrega',
      'prazo_pagamento': 'Prazo de pagamento',
      'observacoes': 'Observações',
    };
    final salvar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Dados de ${d.nome}'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in campos.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: TextField(
                      controller: e.value,
                      maxLines: e.key == 'observacoes' ? 3 : 1,
                      decoration: InputDecoration(labelText: rotulos[e.key]),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar')),
        ],
      ),
    );
    final valores = {for (final e in campos.entries) e.key: e.value.text.trim().isEmpty ? null : e.value.text.trim()};
    for (final c in campos.values) {
      c.dispose();
    }
    if (salvar != true || !context.mounted) return;
    try {
      await supabase.from('guia_distribuidores').update(valores).eq('id', d.id);
      if (context.mounted) Navigator.pop(context);
      await onAlterado();
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível salvar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final d = distribuidor;
    Widget contato(IconData icone, String rotulo, String? valor, {VoidCallback? abrir}) {
      if (valor == null || valor.isEmpty) return const SizedBox.shrink();
      return ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(icone, size: 20),
        title: SelectableText(valor),
        subtitle: Text(rotulo),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(tooltip: 'Copiar', icon: const Icon(Icons.copy, size: 18), onPressed: () => copiar(valor)),
            if (abrir != null) IconButton(tooltip: 'Abrir', icon: const Icon(Icons.open_in_new, size: 18), onPressed: abrir),
          ],
        ),
      );
    }

    String? soDigitos(String? s) => s?.replaceAll(RegExp(r'[^0-9]'), '');

    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        Text(d.nome, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        Text(
          [rotuloSituacao, if (d.cidade != null) d.cidade!, if (d.regiaoAtendida != null) 'atende ${d.regiaoAtendida}'].join(' · '),
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
        if (d.observacoes != null) ...[
          const SizedBox(height: 10),
          Text(d.observacoes!),
        ],
        const SizedBox(height: 12),
        contato(Icons.phone_outlined, 'Telefone', d.telefone, abrir: () => abrirLink('tel:${soDigitos(d.telefone)}')),
        contato(Icons.chat_outlined, 'WhatsApp', d.whatsapp,
            abrir: () => abrirLink('https://wa.me/55${soDigitos(d.whatsapp)}')),
        contato(Icons.mail_outline, 'E-mail', d.email),
        contato(Icons.public, 'Site', d.site, abrir: d.site == null ? null : () => abrirLink(d.site!)),
        contato(Icons.place_outlined, 'Endereço', d.endereco),
        const SizedBox(height: 8),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            Text('Pedido mínimo: ${d.pedidoMinimo ?? 'não informado'}'),
            Text('Entrega: ${d.prazoEntrega ?? 'não informado'}'),
            Text('Pagamento: ${d.prazoPagamento ?? 'não informado'}'),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            OutlinedButton.icon(onPressed: () => _editar(context), icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Editar dados')),
            if (!d.seu && d.situacao != 'em_contato')
              OutlinedButton(onPressed: () => _mudarSituacao(context, 'em_contato'), child: const Text('Em contato')),
            if (!d.seu && d.situacao != 'aprovado')
              OutlinedButton(onPressed: () => _mudarSituacao(context, 'aprovado'), child: const Text('Aprovado')),
            if (!d.seu && d.situacao != 'descartado')
              OutlinedButton(onPressed: () => _mudarSituacao(context, 'descartado'), child: const Text('Descartar')),
            if (!d.seu && d.situacao == 'descartado')
              OutlinedButton(onPressed: () => _mudarSituacao(context, 'a_contatar'), child: const Text('Restaurar')),
          ],
        ),
        if (d.necessidades.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Tipos de produto', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [for (final n in d.necessidades) Chip(label: Text(n), visualDensity: VisualDensity.compact)]),
        ],
        const SizedBox(height: 16),
        Text('Marcas (${d.marcas.length})', style: Theme.of(context).textTheme.titleSmall),
        if (d.marcas.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Nenhuma marca ligada ainda.', style: TextStyle(color: colorScheme.onSurfaceVariant)),
          ),
        for (final m in d.marcas)
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            onTap: () => onAbrirMarca(m['marca_id'] as String),
            title: Text(m['nome'] as String),
            subtitle: Text([
              if ((m['voce_produtos'] as num? ?? 0) > 0) 'você vende ${m['voce_produtos']}',
              if ((m['regiao_lojas'] as num? ?? 0) > 0) 'região: ${m['regiao_lojas']} lojas',
            ].join(' · ')),
            trailing: chipSituacao(m['situacao'] as String? ?? 'a_confirmar'),
          ),
        if (d.fonte != null) ...[
          const SizedBox(height: 12),
          Text('Origem da informação: ${d.fonte}', style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
        ],
      ],
    );
  }
}
