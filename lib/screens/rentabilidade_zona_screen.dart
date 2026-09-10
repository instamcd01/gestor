import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../providers/auth_provider.dart';
import 'custos_operacionais_screen.dart';

/// Rentabilidade real por zona de entrega — separa claramente o que o
/// cliente paga do custo real de entregar: moto (combustível + manutenção
/// + depreciação, ida e volta, rateada pela quantidade de entregas que
/// costumam sair juntas na mesma rota — não cobra a viagem inteira de uma
/// entrega isolada) + o que é pago ao entregador (regra hoje: valor base
/// até um limiar de distância, depois escala com a distância).
/// Só cobre pedidos do site próprio (único canal que grava a zona em
/// `pedidos.metadata`) — amostra ainda pequena, cresce sozinha. Parâmetros
/// de custo em Configurações > Custos Operacionais, editáveis a qualquer
/// momento (o modelo de pagamento ainda está em estudo).
/// Ver [[gestor_pedido_compra_fornecedor]].
class RentabilidadeZonaScreen extends StatefulWidget {
  const RentabilidadeZonaScreen({super.key});

  @override
  State<RentabilidadeZonaScreen> createState() => _RentabilidadeZonaScreenState();
}

class _Zona {
  final String nome;
  final double distanciaMediaKm;
  final int pedidos;
  final double cobradoMedio;
  final double custoMoto;
  final double pagamentoEntregador;
  final double margem;
  _Zona({
    required this.nome,
    required this.distanciaMediaKm,
    required this.pedidos,
    required this.cobradoMedio,
    required this.custoMoto,
    required this.pagamentoEntregador,
    required this.margem,
  });
}

class _RentabilidadeZonaScreenState extends State<RentabilidadeZonaScreen> {
  bool _carregando = true;
  String? _erro;
  List<_Zona> _zonas = [];
  bool _dadoMotoCompleto = false;
  double _custoKmMotoUsado = 0;
  double _mediaEntregasPorRota = 1;
  bool _temDadoRotaReal = false;
  int _pedidosForaDaAnalise = 0;

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
          .rpc('rentabilidade_real_por_zona', params: {'p_empresa_id': empresaId, 'p_dias': 365});
      if (!mounted) return;
      final lista = (resultado as List).cast<Map<String, dynamic>>();
      setState(() {
        _zonas = lista
            .map((l) => _Zona(
                  nome: l['zona'] as String,
                  distanciaMediaKm: (l['distancia_media_km'] as num).toDouble(),
                  pedidos: l['pedidos'] as int,
                  cobradoMedio: (l['faturamento_entrega_medio'] as num).toDouble(),
                  custoMoto: (l['custo_moto_por_entrega'] as num).toDouble(),
                  pagamentoEntregador: (l['pagamento_entregador_por_entrega'] as num).toDouble(),
                  margem: (l['margem_por_entrega'] as num).toDouble(),
                ))
            .toList();
        _dadoMotoCompleto = lista.isNotEmpty ? (lista.first['tem_dado_moto_completo'] as bool? ?? false) : false;
        _custoKmMotoUsado = lista.isNotEmpty ? (lista.first['custo_km_moto_usado'] as num).toDouble() : 0;
        _mediaEntregasPorRota = lista.isNotEmpty ? (lista.first['media_entregas_por_rota_usada'] as num? ?? 1).toDouble() : 1;
        _temDadoRotaReal = lista.isNotEmpty ? (lista.first['tem_dado_rota_real'] as bool? ?? false) : false;
        _carregando = false;
      });

      // Site próprio é o único canal com zona/coordenada estruturada hoje —
      // iFood (a maior parte real do volume) entrega pela mesma moto da loja
      // mas não tem distância real registrada (pedidos vieram do relatório
      // histórico, sem endereço). Contar aqui só pra deixar claro na tela que
      // essa análise cobre uma fatia pequena da operação, não o todo.
      final foraDaAnalise = await Supabase.instance.client
          .from('pedidos')
          .select('id')
          .eq('empresa_id', empresaId)
          .eq('status', 'entregue')
          .neq('canal_venda', 'site_proprio')
          .gte('created_at', DateTime.now().subtract(const Duration(days: 365)).toIso8601String())
          .count(CountOption.exact);
      if (!mounted) return;
      setState(() => _pedidosForaDaAnalise = foraDaAnalise.count);
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
    final totalPedidos = _zonas.fold<int>(0, (s, z) => s + z.pedidos);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rentabilidade por zona'),
        actions: [
          IconButton(
            tooltip: 'Ajustar parâmetros de custo',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const CustosOperacionaisScreen()),
              );
              _carregar();
            },
          ),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _carregar),
        ],
      ),
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
              : Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 700),
                    child: ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        if (_pedidosForaDaAnalise > 0)
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.red.withValues(alpha: 0.35)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.report_outlined, color: Colors.red, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Esta análise cobre só o site próprio ($totalPedidos pedido(s)) — $_pedidosForaDaAnalise pedido(s) '
                                    'de outros canais (a maior parte iFood, entregue pela mesma moto da loja) ficam de fora, porque '
                                    'não têm distância real registrada. Não dá pra estimar com segurança (linha reta até o cliente sai '
                                    'menor que a rota real de moto no Rio) — vai entrar quando o app do entregador tiver km real de rota.',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (!_dadoMotoCompleto)
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Custo da moto ainda incompleto (falta preço do combustível e/ou km rodado por mês em '
                                    'Configurações > Custos Operacionais) — os números abaixo já contam manutenção, mas '
                                    'ainda NÃO contam combustível nem depreciação. A margem real é pior do que aparece '
                                    'aqui, nunca melhor. Toque no ⚙️ pra completar.',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            totalPedidos < 20
                                ? 'Amostra ainda pequena ($totalPedidos pedidos no total) — só o site próprio grava a zona escolhida hoje. Cresce sozinho conforme mais pedidos do site entram.'
                                : 'Baseado em $totalPedidos pedidos do site próprio. Custo de moto usado: ${currencyFormat.format(_custoKmMotoUsado)}/km.',
                            style: const TextStyle(fontSize: 12.5),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            _temDadoRotaReal
                                ? 'O custo de moto por entrega já usa o km real de cada rota registrada no app do entregador.'
                                : 'O custo de moto por entrega considera ida-e-volta até a zona, dividida entre '
                                    '${_mediaEntregasPorRota.toStringAsFixed(0)} entrega(s) — a média que você informou sair '
                                    'na mesma rota, não o custo da viagem inteira pra uma entrega só. É uma estimativa: '
                                    'quando o app do entregador tiver dado real de rota (km rodado por viagem), a conta passa '
                                    'a usar o valor exato de cada rota em vez dessa média. Ajuste em ⚙️.',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (_zonas.isEmpty)
                          const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: Text('Nenhum pedido com zona registrada ainda.')),
                          )
                        else
                          for (final z in _zonas)
                            Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text('${z.nome} (~${z.distanciaMediaKm}km)',
                                              style: const TextStyle(fontWeight: FontWeight.bold)),
                                        ),
                                        Text(
                                          '${z.margem >= 0 ? '+' : ''}${currencyFormat.format(z.margem)} / entrega',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: z.margem >= 0 ? Colors.green : Colors.red,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${z.pedidos} pedido(s) • cobrado ${currencyFormat.format(z.cobradoMedio)} — '
                                      'moto ${currencyFormat.format(z.custoMoto)} − entregador ${currencyFormat.format(z.pagamentoEntregador)}',
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                      ],
                    ),
                  ),
                ),
    );
  }
}
