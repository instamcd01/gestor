import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Entregador por oferta na Fila de Pedidos (25/11): em qual rota cada pedido está, quem pegou, até
/// quando sai e o botão "Entregar ao motoboy" — é a loja que começa a rota (antes o motoboy tocava
/// "Saí" de onde estivesse e o cliente recebia "saiu pra entrega" sem o pedido ter saído).
class RotaOfertaInfo {
  final String rotaId;
  final String status; // ofertada | aceita | em_andamento | sem_entregador
  final String? entregador;
  final double? valor;
  final DateTime? prazoSaida;
  final bool chegou;
  final int n;

  RotaOfertaInfo({
    required this.rotaId,
    required this.status,
    this.entregador,
    this.valor,
    this.prazoSaida,
    this.chegou = false,
    this.n = 1,
  });

  bool get aguardandoSaida => status == 'aceita';
}

/// Rotas de oferta abertas, por pedido. Atualiza a cada 20 s enquanto alguém escuta.
class RotasOfertaFila extends ValueNotifier<Map<String, RotaOfertaInfo>> {
  RotasOfertaFila._() : super(const {});
  static final instancia = RotasOfertaFila._();

  Timer? _timer;
  int _ouvintes = 0;

  void comecar() {
    _ouvintes++;
    if (_timer != null) return;
    atualizar();
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => atualizar());
  }

  void parar() {
    _ouvintes--;
    if (_ouvintes <= 0) {
      _ouvintes = 0;
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> atualizar() async {
    try {
      final rows = await Supabase.instance.client
          .from('rota_pedidos')
          .select('pedido_id, rota:rotas_entrega!inner(id, status, origem, valor_entregador, prazo_saida, '
              'chegou_loja_em, n_pedidos, entregador:entregadores(nome))')
          .eq('rota.origem', 'oferta')
          .inFilter('rota.status', ['ofertada', 'aceita', 'em_andamento', 'sem_entregador']);
      final mapa = <String, RotaOfertaInfo>{};
      for (final r in rows as List) {
        final rota = r['rota'] as Map<String, dynamic>;
        final ent = rota['entregador'] as Map<String, dynamic>?;
        mapa[r['pedido_id'] as String] = RotaOfertaInfo(
          rotaId: rota['id'] as String,
          status: rota['status'] as String,
          entregador: (ent?['nome'] as String?)?.split(' ').first,
          valor: (rota['valor_entregador'] as num?)?.toDouble(),
          prazoSaida: rota['prazo_saida'] == null ? null : DateTime.tryParse(rota['prazo_saida'] as String)?.toLocal(),
          chegou: rota['chegou_loja_em'] != null,
          n: (rota['n_pedidos'] as num?)?.toInt() ?? 1,
        );
      }
      value = mapa;
    } catch (e) {
      debugPrint('Erro ao carregar rotas de oferta: $e');
    }
  }

  /// "Entregar ao motoboy": começa a rota (RPC entrega_oferta_loja_entregou). Devolve o erro, se houver.
  Future<String?> entregarAoMotoboy(String rotaId) async {
    try {
      final r = await Supabase.instance.client.rpc('entrega_oferta_loja_entregou', params: {'p_rota_id': rotaId})
          as Map<String, dynamic>?;
      await atualizar();
      return r?['ok'] == true ? null : (r?['mensagem']?.toString() ?? 'Não deu pra começar a rota.');
    } catch (e) {
      return 'Não deu pra começar a rota: $e';
    }
  }
}

/// Selo do pedido na Fila: "🛵 LUCAS · sair 20:52 · R$ 13,00 · chegou".
class SeloRotaOferta extends StatelessWidget {
  final RotaOfertaInfo info;
  const SeloRotaOferta({super.key, required this.info});

  @override
  Widget build(BuildContext context) {
    final moeda = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');
    final hora = info.prazoSaida == null ? null : DateFormat('HH:mm').format(info.prazoSaida!);
    final (texto, cor) = switch (info.status) {
      'ofertada' => ('Motoboy: aguardando aceite${hora == null ? '' : ' · sair $hora'}', Colors.blueGrey),
      'aceita' => (
          '${info.entregador ?? 'Motoboy'}${info.chegou ? ' chegou' : ' vindo'}'
              '${hora == null ? '' : ' · sair $hora'}${info.valor == null ? '' : ' · ${moeda.format(info.valor)}'}'
              '${info.n > 1 ? ' · ${info.n} pedidos' : ''}',
          info.chegou ? Colors.green.shade700 : Colors.orange.shade800
        ),
      'em_andamento' => ('${info.entregador ?? 'Motoboy'} em rota', Colors.blue.shade700),
      'sem_entregador' => ('Sem motoboy: a loja entrega', Colors.red.shade700),
      _ => (info.status, Colors.grey),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: cor.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.two_wheeler, size: 15, color: cor),
          const SizedBox(width: 5),
          Flexible(
            child: Text(texto,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: cor),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }
}

/// Botão "Entregar ao motoboy" (só quando a rota foi aceita e ainda não saiu).
class BotaoEntregarMotoboy extends StatefulWidget {
  final RotaOfertaInfo info;
  final bool compacto;
  const BotaoEntregarMotoboy({super.key, required this.info, this.compacto = false});

  @override
  State<BotaoEntregarMotoboy> createState() => _BotaoEntregarMotoboyState();
}

class _BotaoEntregarMotoboyState extends State<BotaoEntregarMotoboy> {
  bool _enviando = false;

  Future<void> _entregar() async {
    final mensageiro = ScaffoldMessenger.of(context);
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Entregar ao motoboy'),
        content: Text(
          'Confirma que ${widget.info.entregador ?? 'o motoboy'} pegou '
          '${widget.info.n == 1 ? 'o pedido' : 'os ${widget.info.n} pedidos da rota'}? '
          'A rota começa e os clientes recebem "saiu para entrega".',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Entreguei')),
        ],
      ),
    );
    if (confirmou != true) return;
    setState(() => _enviando = true);
    final erro = await RotasOfertaFila.instancia.entregarAoMotoboy(widget.info.rotaId);
    if (mounted) setState(() => _enviando = false);
    mensageiro.showSnackBar(SnackBar(content: Text(erro ?? 'Rota começou. Boa entrega!')));
  }

  @override
  Widget build(BuildContext context) {
    final rotulo = Text(_enviando ? 'Começando…' : 'Entregar ao motoboy');
    return widget.compacto
        ? FilledButton.tonalIcon(
            onPressed: _enviando ? null : _entregar, icon: const Icon(Icons.two_wheeler, size: 18), label: rotulo)
        : FilledButton.icon(
            onPressed: _enviando ? null : _entregar, icon: const Icon(Icons.two_wheeler, size: 18), label: rotulo);
  }
}
