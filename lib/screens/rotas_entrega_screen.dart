import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/entregador.dart';
import '../models/rota_entrega.dart';
import '../models/venda.dart';
import '../providers/auth_provider.dart';
import '../providers/entregador_provider.dart';
import '../providers/historico_vendas_provider.dart';
import '../repositories/rota_entrega_repository.dart';
import '../services/distancia_service.dart';
import 'rota_mapa_screen.dart';

/// Monta e finaliza rotas de entrega do dia (Fase 2 do custo real por
/// venda, ver [[gestor_custo_real_venda]]) — agrupa pedidos pra um
/// entregador despachar de uma vez, e calcula o custo real de entrega de
/// cada um quando a rota é finalizada (`finalizar_rota_entrega`, RPC).
/// Reaproveita `HistoricoVendasProvider` (já carregado em outro lugar do
/// app) pra saber quais pedidos existem/qual o status de cada um, em vez
/// de duplicar essa consulta aqui.
class RotasEntregaScreen extends StatefulWidget {
  const RotasEntregaScreen({super.key});

  @override
  State<RotasEntregaScreen> createState() => _RotasEntregaScreenState();
}

class _RotasEntregaScreenState extends State<RotasEntregaScreen> {
  final _repository = RotaEntregaRepository();
  DateTime _data = DateTime.now();
  List<RotaEntrega> _rotas = [];
  final Map<String, List<RotaPedidoItem>> _pedidosPorRota = {};
  Set<String> _pedidosJaRoteados = {};
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<EntregadorProvider>().carregar();
      context.read<HistoricoVendasProvider>().carregarVendas();
      _carregar();
    });
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final rotas = await _repository.listarPorData(_data);
      final roteados = await _repository.pedidosJaRoteados();
      final pedidosPorRota = <String, List<RotaPedidoItem>>{};
      for (final rota in rotas) {
        pedidosPorRota[rota.id] = await _repository.pedidosDaRota(rota.id);
      }
      if (!mounted) return;
      setState(() {
        _rotas = rotas;
        _pedidosJaRoteados = roteados;
        _pedidosPorRota
          ..clear()
          ..addAll(pedidosPorRota);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao carregar rotas: $e')));
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _mudarData(int dias) async {
    setState(() => _data = _data.add(Duration(days: dias)));
    await _carregar();
  }

  Future<void> _novaRota() async {
    final ativos = context.read<EntregadorProvider>().ativos;
    if (ativos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cadastre um entregador ativo primeiro (Configurações > Entregadores).')),
      );
      return;
    }

    final entregador = await showDialog<Entregador>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Escolha o entregador'),
        children: ativos
            .map((e) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, e),
                  child: Text(e.nome),
                ))
            .toList(),
      ),
    );
    if (entregador == null || !mounted) return;

    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;

    try {
      await _repository.criar(empresaId: empresaId, entregadorId: entregador.id!, dataRota: _data);
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao criar rota: $e')));
      }
    }
  }

  Venda? _buscarVenda(HistoricoVendasProvider provider, String pedidoId) {
    for (final v in provider.vendas) {
      if (v.idVenda == pedidoId) return v;
    }
    return null;
  }

  List<Venda> _pedidosElegiveis(HistoricoVendasProvider provider) {
    return provider.vendas
        .where((v) =>
            !v.retirada &&
            StatusPedido.emAndamento.contains(v.status) &&
            v.idVenda != null &&
            !_pedidosJaRoteados.contains(v.idVenda))
        .toList();
  }

  Future<void> _adicionarPedidos(RotaEntrega rota) async {
    final provider = context.read<HistoricoVendasProvider>();
    final elegiveis = _pedidosElegiveis(provider);
    if (elegiveis.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum pedido elegível pra rota agora (retirada ou já roteado não entram).')),
      );
      return;
    }

    final selecionados = <String>{};
    final confirmou = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Adicionar pedidos', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: elegiveis.map((v) {
                      final id = v.idVenda!;
                      return CheckboxListTile(
                        value: selecionados.contains(id),
                        title: Text('#${v.numeroSequencial ?? '-'} — ${v.cliente.nome}'),
                        subtitle: Text('${StatusPedido.rotulo(v.status)} • ${v.cliente.bairro}'),
                        onChanged: (marcado) => setModalState(() {
                          if (marcado == true) {
                            selecionados.add(id);
                          } else {
                            selecionados.remove(id);
                          }
                        }),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),
                ElevatedButton(
                  onPressed: selecionados.isEmpty ? null : () => Navigator.pop(ctx, true),
                  child: Text('Adicionar (${selecionados.length})'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmou != true || selecionados.isEmpty) return;

    final jaNaRota = _pedidosPorRota[rota.id]?.length ?? 0;
    var ordem = jaNaRota;
    for (final pedidoId in selecionados) {
      await _repository.adicionarPedido(rota.id, pedidoId, ordem);
      ordem++;
    }
    await _carregar();
  }

  Future<void> _removerPedido(RotaEntrega rota, String pedidoId) async {
    await _repository.removerPedido(rota.id, pedidoId);
    await _carregar();
  }

  /// lat,lng é mais preciso e rápido de geocodificar que o endereço em
  /// texto — só cai pro texto quando o cliente não tem coordenada salva
  /// ainda (ver opcao_entrega_screen.dart, mesma fonte que preenche isso).
  /// Retorna null se qualquer pedido não tiver como resolver destino —
  /// quem chama decide o fallback (não otimiza nada, ou mantém o que já
  /// tinha calculado antes).
  List<String>? _destinosDosPedidos(List<RotaPedidoItem> pedidos, HistoricoVendasProvider historico) {
    final destinos = <String>[];
    for (final item in pedidos) {
      final venda = _buscarVenda(historico, item.pedidoId);
      final cliente = venda?.cliente;
      if (cliente == null) return null;
      final destino = (cliente.latitude != null && cliente.longitude != null)
          ? '${cliente.latitude},${cliente.longitude}'
          : cliente.enderecoCompleto;
      if (destino.isEmpty) return null;
      destinos.add(destino);
    }
    return destinos;
  }

  /// Chamado antes de iniciar uma rota com 2+ pedidos: busca a ordem de
  /// visita que minimiza a distância TOTAL real (não tempo de viagem, ver
  /// DistanciaService.calcularRotaOtimizada) e já reordena os pedidos +
  /// salva a distância/trajeto calculados. Nunca bloqueia o fluxo se
  /// falhar (endereço não localizável, API fora do ar etc.) — a rota só
  /// segue sem otimização, igual já era antes.
  Future<void> _otimizarRota(RotaEntrega rota, List<RotaPedidoItem> pedidos, HistoricoVendasProvider historico) async {
    if (pedidos.length < 2) return;

    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;

    final origem = await DistanciaService.buscarEnderecoEmpresa(empresaId);
    if (origem == null) return;

    final destinos = _destinosDosPedidos(pedidos, historico);
    if (destinos == null) return;

    final resultado = await DistanciaService.calcularRotaOtimizada(origem: origem, destinos: destinos);
    if (resultado == null || resultado.ordemOtimizada == null) return;

    final pedidosNaOrdemOtima = resultado.ordemOtimizada!.map((indice) => pedidos[indice].pedidoId).toList();
    await _repository.reordenar(rota.id, pedidosNaOrdemOtima);
    await _repository.atualizarKmEstimado(
      rota.id,
      kmEstimado: resultado.distanciaCobravelKm,
      kmVoltaEstimado: resultado.distanciaVoltaKm,
      polylineEstimada: resultado.polylineCodificada,
    );
  }

  /// Recalcula distância/trajeto pra ordem ATUAL dos pedidos (já reordenada
  /// manualmente pelo usuário) — reaproveita a mesma rota física, só que
  /// pra ordem que ele escolheu em vez de buscar a menor distância. Chamado
  /// depois de qualquer drag-and-drop na lista.
  Future<void> _recalcularParaOrdemAtual(RotaEntrega rota, List<RotaPedidoItem> pedidosNaOrdem) async {
    final historico = context.read<HistoricoVendasProvider>();
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;

    final origem = await DistanciaService.buscarEnderecoEmpresa(empresaId);
    if (origem == null) return;

    final destinos = _destinosDosPedidos(pedidosNaOrdem, historico);
    if (destinos == null) return;

    final resultado = await DistanciaService.calcularRotaOrdemFixa(origem: origem, destinosNaOrdem: destinos);
    if (resultado == null) return;

    await _repository.atualizarKmEstimado(
      rota.id,
      kmEstimado: resultado.distanciaCobravelKm,
      kmVoltaEstimado: resultado.distanciaVoltaKm,
      polylineEstimada: resultado.polylineCodificada,
    );
  }

  /// Drag-and-drop na lista de pedidos — às vezes um pedido tem prioridade
  /// (cliente esperando, combinou horário) ou o entregador conhece um
  /// atalho que a API não capturou; a ordem calculada automaticamente é só
  /// um ponto de partida, não uma trava. Reordena localmente pra resposta
  /// instantânea, salva no banco, e recalcula a distância em segundo plano
  /// (sem travar a tela) pra km_estimado continuar refletindo a rota real.
  Future<void> _reordenarManualmente(RotaEntrega rota, int oldIndex, int newIndex) async {
    final pedidos = List<RotaPedidoItem>.of(_pedidosPorRota[rota.id] ?? []);
    if (newIndex > oldIndex) newIndex -= 1;
    final item = pedidos.removeAt(oldIndex);
    pedidos.insert(newIndex, item);

    setState(() => _pedidosPorRota[rota.id] = pedidos);

    await _repository.reordenar(rota.id, pedidos.map((p) => p.pedidoId).toList());
    if (pedidos.length >= 2) {
      await _recalcularParaOrdemAtual(rota, pedidos);
      if (mounted) await _carregar();
    }
  }

  Future<void> _iniciarRota(RotaEntrega rota) async {
    final pedidos = _pedidosPorRota[rota.id] ?? [];
    if (pedidos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Adicione pelo menos 1 pedido antes de iniciar.')));
      return;
    }

    final mostrarLoading = pedidos.length >= 2;
    if (mostrarLoading) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 16),
              Expanded(child: Text('Calculando a melhor rota entre os pedidos...')),
            ],
          ),
        ),
      );
    }

    try {
      final historico = context.read<HistoricoVendasProvider>();
      await _otimizarRota(rota, pedidos, historico);
      if (mostrarLoading && mounted) Navigator.of(context, rootNavigator: true).pop();

      await _repository.iniciar(rota.id);
      if (!mounted) return;
      // Avança o status de cada pedido pra "saiu para entrega" — reaproveita
      // o mesmo método já usado na Fila de Pedidos, não duplica a lógica de
      // estoque/notificação que vive na RPC por trás dele.
      for (final item in pedidos) {
        final venda = _buscarVenda(historico, item.pedidoId);
        if (venda != null && venda.status == StatusPedido.preparando) {
          await historico.avancarStatusPedido(item.pedidoId, StatusPedido.saiuParaEntrega);
        }
      }
      await _carregar();
    } catch (e) {
      if (mostrarLoading && mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao iniciar rota: $e')));
      }
    }
  }

  Future<void> _finalizarRota(RotaEntrega rota) async {
    double? kmTotal;
    if (rota.precisaDeKmTotal) {
      // Pré-preenche com a distância calculada pela API ao iniciar a rota
      // (rota otimizada, ida e volta) — o campo continua editável pra quem
      // desviou do trajeto sugerido ou não teve a rota otimizada (só 1
      // pedido, endereço não localizável etc.) ajustar pro valor real.
      final controller = TextEditingController(
        text: rota.kmEstimado?.toStringAsFixed(1).replaceAll('.', ','),
      );
      final confirmou = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Km total da rota'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (rota.kmEstimado != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'Valor sugerido pela rota otimizada calculada ao iniciar — ajuste se o percurso real foi diferente.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                ),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Quantos km foram rodados no total?', suffixText: 'km'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Finalizar')),
          ],
        ),
      );
      if (confirmou != true || !mounted) return;
      kmTotal = double.tryParse(controller.text.trim().replaceAll(',', '.'));
      if (kmTotal == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Km inválido.')));
        return;
      }
    }

    try {
      await _repository.finalizar(rota.id, kmTotal: kmTotal);
      await _carregar();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rota finalizada — custo de entrega calculado.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao finalizar: $e')));
      }
    }
  }

  Color _corStatus(String status) {
    switch (status) {
      case StatusRota.planejada:
        return Colors.orange;
      case StatusRota.emAndamento:
        return Colors.blue;
      case StatusRota.concluida:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _rotuloStatus(String status) {
    switch (status) {
      case StatusRota.planejada:
        return 'Planejada';
      case StatusRota.emAndamento:
        return 'Em andamento';
      case StatusRota.concluida:
        return 'Concluída';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final historico = context.watch<HistoricoVendasProvider>();
    final podeVerFinancas = context.watch<AuthProvider>().podeVerFinancas;
    final dateFormat = DateFormat('dd/MM/yyyy');
    final currencyFormat = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');

    return Scaffold(
      appBar: AppBar(title: const Text('Rotas de Entrega')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _novaRota,
        icon: const Icon(Icons.add),
        label: const Text('Nova rota'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => _mudarData(-1)),
                Text(dateFormat.format(_data), style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => _mudarData(1)),
              ],
            ),
          ),
          if (_carregando)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_rotas.isEmpty)
            const Expanded(child: Center(child: Text('Nenhuma rota nesse dia ainda.')))
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _rotas.length,
                itemBuilder: (context, index) {
                  final rota = _rotas[index];
                  final pedidosDaRota = _pedidosPorRota[rota.id] ?? [];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ExpansionTile(
                      title: Text(rota.entregadorNome, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: _corStatus(rota.status).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(_rotuloStatus(rota.status),
                                style: TextStyle(color: _corStatus(rota.status), fontSize: 11, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),
                          Text('${pedidosDaRota.length} pedido(s)'),
                          if (rota.kmTotal != null)
                            Text(' • ${rota.kmTotal!.toStringAsFixed(1)} km')
                          else if (rota.kmEstimado != null)
                            Text(
                              rota.kmVoltaEstimado != null
                                  ? ' • ~${rota.kmEstimado!.toStringAsFixed(1)} km cobrável'
                                        ' (${(rota.kmEstimado! + rota.kmVoltaEstimado!).toStringAsFixed(1)} km rodado)'
                                  : ' • ~${rota.kmEstimado!.toStringAsFixed(1)} km (estimado)',
                            ),
                        ],
                      ),
                      children: [
                        if (pedidosDaRota.length > 1 && !rota.concluida)
                          // Drag-and-drop: a ordem calculada automaticamente
                          // é só um ponto de partida — o entregador pode
                          // conhecer um atalho, ou um pedido pode ter
                          // prioridade (cliente esperando, horário
                          // combinado). Reordenar aqui recalcula a
                          // distância pra ordem nova em segundo plano.
                          ReorderableListView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: pedidosDaRota.length,
                            onReorder: (oldIndex, newIndex) => _reordenarManualmente(rota, oldIndex, newIndex),
                            itemBuilder: (context, i) {
                              final item = pedidosDaRota[i];
                              final venda = _buscarVenda(historico, item.pedidoId);
                              return _ItemPedidoRota(
                                key: ValueKey(item.pedidoId),
                                posicao: i + 1,
                                venda: venda,
                                custoAlocado: item.custoAlocado,
                                podeVerFinancas: podeVerFinancas,
                                currencyFormat: currencyFormat,
                                onRemover: rota.planejada ? () => _removerPedido(rota, item.pedidoId) : null,
                                arrastavel: true,
                              );
                            },
                          )
                        else
                          ...pedidosDaRota.asMap().entries.map((entry) {
                            final item = entry.value;
                            final venda = _buscarVenda(historico, item.pedidoId);
                            return _ItemPedidoRota(
                              posicao: entry.key + 1,
                              venda: venda,
                              custoAlocado: item.custoAlocado,
                              podeVerFinancas: podeVerFinancas,
                              currencyFormat: currencyFormat,
                              onRemover: rota.planejada ? () => _removerPedido(rota, item.pedidoId) : null,
                              arrastavel: false,
                              mostrarPosicao: pedidosDaRota.length > 1,
                            );
                          }),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          // Wrap em vez de Row: com "Ver no mapa" +
                          // "Adicionar pedidos" + "Iniciar rota" ao mesmo
                          // tempo (rota planejada já reordenada manualmente,
                          // por exemplo), 3 botões numa linha só estourava a
                          // largura da tela em celular — aqui o que não
                          // couber quebra pra uma 2ª linha em vez de sumir
                          // cortado.
                          child: Wrap(
                            alignment: WrapAlignment.end,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              if (rota.polylineEstimada != null)
                                TextButton.icon(
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => RotaMapaScreen(
                                        rota: rota,
                                        vendas: pedidosDaRota.map((item) => _buscarVenda(historico, item.pedidoId)).toList(),
                                      ),
                                    ),
                                  ),
                                  icon: const Icon(Icons.map_outlined, size: 18),
                                  label: const Text('Ver no mapa'),
                                ),
                              if (rota.planejada) ...[
                                TextButton(
                                  onPressed: () => _adicionarPedidos(rota),
                                  child: const Text('Adicionar pedidos'),
                                ),
                                ElevatedButton(
                                  onPressed: () => _iniciarRota(rota),
                                  child: const Text('Iniciar rota'),
                                ),
                              ] else if (rota.emAndamento)
                                ElevatedButton(
                                  onPressed: () => _finalizarRota(rota),
                                  child: const Text('Finalizar rota'),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Uma linha de pedido dentro da rota — usado tanto no modo estático
/// (rota concluída, ou só 1 pedido) quanto dentro do ReorderableListView
/// (drag-and-drop pra reordenar manualmente).
class _ItemPedidoRota extends StatelessWidget {
  final int posicao;
  final Venda? venda;
  final double? custoAlocado;
  final bool podeVerFinancas;
  final NumberFormat currencyFormat;
  final VoidCallback? onRemover;
  final bool arrastavel;
  final bool mostrarPosicao;

  const _ItemPedidoRota({
    super.key,
    required this.posicao,
    required this.venda,
    required this.custoAlocado,
    required this.podeVerFinancas,
    required this.currencyFormat,
    required this.onRemover,
    required this.arrastavel,
    this.mostrarPosicao = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      // Ordem de visita — reflete a rota otimizada (menor distância real)
      // assim que "Iniciar rota" calcula ela, ou o reordenamento manual
      // mais recente; antes disso é só a ordem que os pedidos foram
      // adicionados.
      leading: mostrarPosicao
          ? CircleAvatar(radius: 12, child: Text('$posicao', style: const TextStyle(fontSize: 12)))
          : null,
      title: Text(
        venda != null ? '#${venda!.numeroSequencial ?? '-'} — ${venda!.cliente.nome}' : 'Pedido não encontrado',
      ),
      subtitle: Text(
        [
          if (venda != null) StatusPedido.rotulo(venda!.status),
          if (podeVerFinancas && custoAlocado != null) 'Custo entrega: ${currencyFormat.format(custoAlocado)}',
        ].join(' • '),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onRemover != null) IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onRemover),
          if (arrastavel) const Icon(Icons.drag_handle, size: 20),
        ],
      ),
    );
  }
}
