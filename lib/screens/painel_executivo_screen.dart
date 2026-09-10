import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/auth_provider.dart';

/// Resumo executivo de 1 tela — o que players reais de POS pra pequeno
/// varejo (Shopify, Lightspeed) mostram como "resumo do negócio", com 2
/// exceções deliberadas: sem CAC/CLV tratados como número maduro (a base
/// de cliente identificado ainda é pequena, ver [[gestor_pedido_compra_fornecedor]])
/// e sem benchmark de mercado externo (pesquisa real desaconselhou —
/// números de mercado americano não comparam com real brasileiro).
/// CAC/CLV ficam prontos e visíveis, só rotulados com o tamanho real da
/// amostra, pra já estarem funcionando sozinhos quando mais dado chegar.
class PainelExecutivoScreen extends StatefulWidget {
  const PainelExecutivoScreen({super.key});

  @override
  State<PainelExecutivoScreen> createState() => _PainelExecutivoScreenState();
}

class _PainelExecutivoScreenState extends State<PainelExecutivoScreen> {
  bool _carregando = true;
  String? _erro;
  Map<String, dynamic>? _dados;
  int _dias = 30;

  @override
  void initState() {
    super.initState();
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
      final resultado = await Supabase.instance.client
          .rpc('painel_executivo', params: {'p_empresa_id': empresaId, 'p_dias': _dias});
      if (!mounted) return;
      final lista = resultado as List;
      setState(() {
        _dados = lista.isNotEmpty ? lista.first as Map<String, dynamic> : null;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = 'Não foi possível carregar: $e';
        _carregando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Painel Executivo'),
        actions: [
          PopupMenuButton<int>(
            initialValue: _dias,
            onSelected: (v) {
              setState(() => _dias = v);
              _carregar();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 7, child: Text('Últimos 7 dias')),
              PopupMenuItem(value: 30, child: Text('Últimos 30 dias')),
              PopupMenuItem(value: 90, child: Text('Últimos 90 dias')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(children: [Text('$_dias dias'), const Icon(Icons.arrow_drop_down)]),
            ),
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _carregar),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : _erro != null || _dados == null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_erro ?? 'Sem dados no período.', textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _carregar, child: const Text('Tentar de novo')),
                      ],
                    ),
                  ),
                )
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 800),
                    child: ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        _secaoTitulo('Vendas e margem'),
                        _grade([
                          _kpi('Faturamento', currencyFormat.format(_dados!['faturamento'] ?? 0), Icons.attach_money, Colors.blue),
                          _kpi('Lucro bruto', currencyFormat.format(_dados!['lucro_bruto'] ?? 0), Icons.trending_up, Colors.green),
                          _kpi('Margem', '${_dados!['margem_pct'] ?? '—'}%', Icons.percent, Colors.teal),
                          _kpi('Ticket médio', currencyFormat.format(_dados!['ticket_medio'] ?? 0), Icons.receipt_long, Colors.indigo),
                        ]),
                        const SizedBox(height: 16),
                        _secaoTitulo('Estoque'),
                        _grade([
                          _kpi(
                            'Sell-through',
                            '${_dados!['sell_through_pct'] ?? '—'}%',
                            Icons.sync_alt,
                            Colors.orange,
                            explicacao: '% do estoque disponível que foi vendido no período — giro real, não só o que está parado.',
                          ),
                        ]),
                        const SizedBox(height: 16),
                        _secaoTitulo('Cliente (CAC/CLV)'),
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Base de só ${_dados!['clientes_identificados'] ?? 0} cliente(s) identificado(s) — a maioria dos pedidos vem de marketplace sem CRM próprio. '
                            'Os números abaixo já funcionam sozinhos e melhoram conforme mais cliente for identificado (site/WhatsApp/loja física) — hoje, trate como indicativo, não decisão.',
                            style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                          ),
                        ),
                        _grade([
                          _kpi(
                            'CLV médio',
                            _dados!['clv_medio'] != null ? currencyFormat.format(_dados!['clv_medio']) : 'sem dado',
                            Icons.favorite_outline,
                            Colors.pink,
                            explicacao: 'Total histórico médio gasto por cliente identificado (não é uma previsão, é retrospectivo).',
                          ),
                          _kpi('Clientes identificados', '${_dados!['clientes_identificados'] ?? 0}', Icons.people_outline, Colors.brown),
                          _kpi('Novos no período', '${_dados!['novos_clientes_periodo'] ?? 0}', Icons.person_add_outlined, Colors.deepPurple),
                          _kpi(
                            'CAC',
                            _dados!['cac'] != null
                                ? currencyFormat.format(_dados!['cac'])
                                : 'sem gasto de marketing registrado',
                            Icons.campaign_outlined,
                            Colors.deepOrange,
                            explicacao: 'Gasto em despesas categoria "Marketing" ÷ novos clientes no período. Registre uma despesa de Marketing pra isso ativar.',
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _secaoTitulo(String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(texto, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.3)),
      );

  Widget _grade(List<Widget> kpis) {
    return Wrap(spacing: 10, runSpacing: 10, children: kpis);
  }

  Widget _kpi(String label, String valor, IconData icon, Color cor, {String? explicacao}) {
    return Container(
      width: 170,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: cor),
          const SizedBox(height: 8),
          Text(
            valor,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11.5, color: Colors.grey)),
          if (explicacao != null) ...[
            const SizedBox(height: 4),
            Text(explicacao, style: const TextStyle(fontSize: 9.5, color: Colors.grey), maxLines: 3),
          ],
        ],
      ),
    );
  }
}
