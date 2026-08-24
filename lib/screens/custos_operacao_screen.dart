import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/auth_provider.dart';
import '../widgets/metric_card.dart';
import 'despesas_screen.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

/// Visão única de "quanto custa manter tudo rodando + quanto sobra de
/// verdade": junta despesas fixas recorrentes (hospedagem, Supabase,
/// domínio — cadastradas em Despesas, categoria "Infraestrutura/Tecnologia")
/// com os custos variáveis por venda já calculados hoje (comissão de
/// marketplace, maquininha, embalagem, entrega própria — ver
/// CustosOperacionaisScreen) num único lucro líquido real do período. Antes
/// disso não existia nenhuma tela agregada — só por venda individual, em
/// venda_detalhes_screen.dart.
class CustosOperacaoScreen extends StatefulWidget {
  const CustosOperacaoScreen({super.key});

  @override
  State<CustosOperacaoScreen> createState() => _CustosOperacaoScreenState();
}

class _CustosOperacaoScreenState extends State<CustosOperacaoScreen> {
  late DateTimeRange _periodo;
  String _filtroRotulo = 'Este mês';

  bool _carregando = true;
  String? _erro;

  double _faturamento = 0;
  double _lucroBruto = 0;
  double _custoEmbalagem = 0;
  double _custoMaquininha = 0;
  double _custoEntrega = 0;
  double _custoComissao = 0;
  double _totalDespesasFixas = 0;
  double _lucroLiquidoReal = 0;

  List<Map<String, dynamic>> _despesasInfra = [];

  int? _bancoBytes;

  // Supabase Free = 500MB de banco incluso. Não há onde ler "qual plano a
  // empresa está" hoje — se migrar pro Pro (8GB), atualizar esse valor aqui.
  static const _limiteBancoBytesFree = 500 * 1024 * 1024;

  @override
  void initState() {
    super.initState();
    final hoje = DateTime.now();
    _periodo = DateTimeRange(start: DateTime(hoje.year, hoje.month, 1), end: hoje);
    _carregar();
  }

  Future<void> _carregar() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final supabase = Supabase.instance.client;
      final resumo = await supabase.rpc('obter_resumo_custos_operacao', params: {
        'p_empresa_id': empresaId,
        'p_data_inicio': _periodo.start.toIso8601String().split('T').first,
        'p_data_fim': _periodo.end.toIso8601String().split('T').first,
      });
      final linha = (resumo as List).first as Map<String, dynamic>;

      final infra = await supabase
          .from('despesas')
          .select('id, descricao, valor, status, observacoes')
          .eq('empresa_id', empresaId)
          .eq('categoria', 'Infraestrutura/Tecnologia')
          .eq('recorrente', true)
          .isFilter('deleted_at', null)
          .order('valor', ascending: false);

      final banco = await supabase.rpc('obter_tamanho_banco');
      final bancoLinha = (banco as List).first as Map<String, dynamic>;

      if (!mounted) return;
      setState(() {
        _faturamento = (linha['faturamento'] as num).toDouble();
        _lucroBruto = (linha['lucro_bruto'] as num).toDouble();
        _custoEmbalagem = (linha['custo_embalagem'] as num).toDouble();
        _custoMaquininha = (linha['custo_maquininha'] as num).toDouble();
        _custoEntrega = (linha['custo_entrega'] as num).toDouble();
        _custoComissao = (linha['custo_comissao_marketplace'] as num).toDouble();
        _totalDespesasFixas = (linha['total_despesas_fixas'] as num).toDouble();
        _lucroLiquidoReal = (linha['lucro_liquido_real'] as num).toDouble();
        _despesasInfra = List<Map<String, dynamic>>.from(infra as List);
        _bancoBytes = (bancoLinha['bytes'] as num).toInt();
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar os custos. Tente de novo.';
        _carregando = false;
      });
    }
  }

  Future<void> _escolherPeriodo(String rotulo) async {
    final hoje = DateTime.now();
    DateTimeRange novoPeriodo;
    switch (rotulo) {
      case 'Este mês':
        novoPeriodo = DateTimeRange(start: DateTime(hoje.year, hoje.month, 1), end: hoje);
        break;
      case 'Mês passado':
        novoPeriodo = DateTimeRange(start: DateTime(hoje.year, hoje.month - 1, 1), end: DateTime(hoje.year, hoje.month, 0));
        break;
      case 'Personalizado':
        final escolhido = await showDateRangePicker(
          context: context,
          firstDate: DateTime(2020),
          lastDate: hoje,
          initialDateRange: _periodo,
        );
        if (escolhido == null) return;
        novoPeriodo = escolhido;
        break;
      default:
        return;
    }
    setState(() {
      _periodo = novoPeriodo;
      _filtroRotulo = rotulo;
    });
    _carregar();
  }

  double get _totalCustosVariaveis => _custoEmbalagem + _custoMaquininha + _custoEntrega + _custoComissao;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Custos da Operação')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_erro!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _carregar, child: const Text('Tentar de novo')),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _carregar,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _seletorPeriodo(),
                      const SizedBox(height: 16),
                      _cardLucroLiquido(colorScheme),
                      const SizedBox(height: 20),
                      Text('No período', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      MetricGrid(
                        cartoes: [
                          MetricCard(
                            icone: Icons.point_of_sale_outlined,
                            titulo: 'Faturamento',
                            valor: _moeda.format(_faturamento),
                          ),
                          MetricCard(
                            icone: Icons.trending_up,
                            titulo: 'Lucro bruto',
                            valor: _moeda.format(_lucroBruto),
                            subtitulo: 'Antes dos custos operacionais',
                          ),
                          MetricCard(
                            icone: Icons.receipt_long_outlined,
                            titulo: 'Custos variáveis',
                            valor: _moeda.format(_totalCustosVariaveis),
                            subtitulo: 'Comissão, maquininha, embalagem, entrega',
                            corIcone: Colors.orange,
                          ),
                          MetricCard(
                            icone: Icons.dns_outlined,
                            titulo: 'Despesas fixas',
                            valor: _moeda.format(_totalDespesasFixas),
                            subtitulo: 'Vencimento no período',
                            corIcone: Colors.orange,
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      _cardBreakdownVariaveis(),
                      const SizedBox(height: 16),
                      _cardInfraestrutura(),
                      const SizedBox(height: 16),
                      _cardUsoBanco(),
                    ],
                  ),
                ),
    );
  }

  Widget _seletorPeriodo() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: ['Este mês', 'Mês passado', 'Personalizado'].map((rotulo) {
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(rotulo, style: const TextStyle(fontSize: 12)),
              visualDensity: VisualDensity.compact,
              selected: _filtroRotulo == rotulo,
              onSelected: (_) => _escolherPeriodo(rotulo),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _cardLucroLiquido(ColorScheme colorScheme) {
    final positivo = _lucroLiquidoReal >= 0;
    final cor = positivo ? Colors.green : Colors.red;
    return Card(
      color: cor.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(positivo ? Icons.check_circle_outline : Icons.warning_amber_outlined, color: cor),
                const SizedBox(width: 8),
                Text('Lucro líquido real', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _moeda.format(_lucroLiquidoReal),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800, color: cor),
            ),
            const SizedBox(height: 4),
            Text(
              'Faturamento − custo do produto − custos variáveis por venda − despesas fixas do período',
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _cardBreakdownVariaveis() {
    final itens = [
      ('Comissão de marketplace', _custoComissao),
      ('Taxa de maquininha', _custoMaquininha),
      ('Embalagem', _custoEmbalagem),
      ('Entrega própria', _custoEntrega),
    ];
    final total = _totalCustosVariaveis;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Custos variáveis por venda', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'Configurados em Configurações > Custos Operacionais',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (total <= 0)
              Text('Nenhum custo variável no período.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
            else
              ...itens.where((i) => i.$2 > 0).map((item) {
                final pct = total > 0 ? (item.$2 / total * 100) : 0.0;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(child: Text(item.$1)),
                          Text('${_moeda.format(item.$2)} (${pct.toStringAsFixed(0)}%)', style: const TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (pct / 100).clamp(0, 1),
                          minHeight: 6,
                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _cardInfraestrutura() {
    final total = _despesasInfra.fold<double>(0, (soma, d) => soma + (d['valor'] as num).toDouble());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Infraestrutura e tecnologia', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const DespesasScreen(apenasPendentes: false)),
                  ).then((_) => _carregar()),
                  child: const Text('Gerenciar'),
                ),
              ],
            ),
            Text(
              'Site, app, n8n, banco de dados e demais assinaturas — ${_moeda.format(total)}/mês',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (_despesasInfra.isEmpty)
              Text('Nenhuma despesa cadastrada nessa categoria ainda.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
            else
              ..._despesasInfra.map((d) {
                final valor = (d['valor'] as num).toDouble();
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          d['descricao']?.toString() ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        valor > 0 ? _moeda.format(valor) : 'Grátis hoje',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: valor > 0 ? null : Colors.green,
                        ),
                      ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _cardUsoBanco() {
    final bytes = _bancoBytes;
    final pct = bytes != null ? (bytes / _limiteBancoBytesFree * 100).clamp(0, 999) : 0.0;
    final alerta = pct >= 80;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Uso do banco de dados (Supabase)', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(
              'Plano Free hoje — 500MB inclusos. Se migrar pro Pro (8GB), o limite muda.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (bytes == null)
              Text('Não foi possível medir agora.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
            else ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatarBytes(bytes), style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('${pct.toStringAsFixed(0)}% de 500MB', style: TextStyle(color: alerta ? Colors.red : null)),
                ],
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (pct / 100).clamp(0, 1),
                  minHeight: 6,
                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  color: alerta ? Colors.red : Colors.green,
                ),
              ),
              if (alerta) ...[
                const SizedBox(height: 8),
                Text(
                  'Já passou de 80% do plano Free — considere migrar pro Pro antes de virar problema.',
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  String _formatarBytes(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
