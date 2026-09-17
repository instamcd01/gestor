import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/avaliacao_marketplace.dart';
import '../models/disputa_marketplace.dart';
import '../repositories/avaliacao_marketplace_repository.dart';
import '../repositories/disputa_marketplace_repository.dart';

/// Painel de avaliações de clientes e disputas/contestações de cancelamento
/// vindas de marketplace (iFood). Duas abas porque são dois fluxos
/// independentes que compartilham o mesmo lugar natural no app: coisas que
/// vêm da iFood e esperam uma decisão humana da loja.
class AvaliacoesDisputasScreen extends StatefulWidget {
  const AvaliacoesDisputasScreen({super.key});

  @override
  State<AvaliacoesDisputasScreen> createState() => _AvaliacoesDisputasScreenState();
}

class _AvaliacoesDisputasScreenState extends State<AvaliacoesDisputasScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _avaliacaoRepository = AvaliacaoMarketplaceRepository();
  final _disputaRepository = DisputaMarketplaceRepository();

  bool _carregando = true;
  List<AvaliacaoMarketplace> _avaliacoes = [];
  List<DisputaMarketplace> _disputas = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _carregar();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final avaliacoes = await _avaliacaoRepository.listar();
      final disputas = await _disputaRepository.listar();
      if (mounted) {
        setState(() {
          _avaliacoes = avaliacoes;
          _disputas = disputas;
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar avaliações/disputas: $e');
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Não foi possível carregar os dados.')));
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _responderAvaliacao(AvaliacaoMarketplace avaliacao) async {
    final controller = TextEditingController();
    final resposta = await showDialog<String>(
      context: context,
      // Sem autofocus + sem fechar tocando fora: com o teclado aberto (via
      // autofocus) e o diálogo fechando por barrier-dismiss no mesmo frame,
      // bate num bug conhecido do framework do Flutter (assert
      // `_dependents.isEmpty` ao desativar o Overlay/IME) — só os botões
      // fecham o diálogo agora.
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Responder avaliação'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Escreva sua resposta ao cliente'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Enviar'),
          ),
        ],
      ),
    );
    if (resposta == null || resposta.isEmpty) return;

    try {
      await _avaliacaoRepository.responder(avaliacao.marketplacePedidoId, resposta);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Resposta enviada.')));
      }
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Não foi possível enviar a resposta.')));
      }
    }
  }

  static const _rotulosAlternativa = {
    'REFUND': 'Reembolso',
    'BENEFIT': 'Benefício',
    'ADDITIONAL_TIME': 'Tempo extra',
  };

  /// Rótulos dos códigos estruturados que a API da iFood aceita em `reason`
  /// (rejeitar: `negotiationReasons`; aceitar: `acceptCancellationReasons`,
  /// que varia por disputa — por isso o fallback humaniza qualquer código
  /// desconhecido em vez de esconder a opção).
  static const _rotulosMotivo = {
    'HIGH_STORE_DEMAND': 'Loja em alta demanda',
    'UNKNOWN_ISSUE': 'Motivo não especificado',
    'CUSTOMER_SATISFACTION': 'Satisfação do cliente',
    'INVENTORY_CHECK': 'Item indisponível / verificação de estoque',
    'SYSTEM_ISSUE': 'Problema no sistema',
    'STORE_SYSTEM_ISSUES': 'Problema no sistema da loja',
    'WRONG_ORDER': 'Pedido incorreto',
    'PRODUCT_QUALITY': 'Qualidade do produto',
    'LATE_DELIVERY': 'Entrega atrasada',
    'CUSTOMER_REQUEST': 'Solicitação do cliente',
    'STORE_INTERNAL_DIFFICULTIES': 'Dificuldades internas da loja',
    'LACK_OF_DRIVERS': 'Sem entregadores disponíveis',
    'OTHER_REASONS': 'Outros motivos',
    'OPERATIONAL_ISSUES': 'Problemas operacionais',
    'ORDER_OUT_FOR_DELIVERY': 'Pedido já saiu para entrega',
    'DRIVER_IS_ALREADY_AT_THE_ADDRESS': 'Entregador já está no endereço',
  };

  static const _motivosRejeitar = [
    'INVENTORY_CHECK',
    'WRONG_ORDER',
    'PRODUCT_QUALITY',
    'LATE_DELIVERY',
    'SYSTEM_ISSUE',
    'HIGH_STORE_DEMAND',
    'CUSTOMER_SATISFACTION',
    'CUSTOMER_REQUEST',
    'UNKNOWN_ISSUE',
  ];

  String _rotuloMotivo(String codigo) =>
      _rotulosMotivo[codigo] ?? codigo.replaceAll('_', ' ').toLowerCase();

  static const _rotulosTimeoutAction = {
    'ACCEPT_CANCELLATION': 'o cancelamento será ACEITO automaticamente',
    'REJECT_CANCELLATION': 'o cancelamento será REJEITADO automaticamente',
    'VOID': 'nenhuma ação automática vai acontecer',
  };

  /// Contraproposta usando uma das alternativas que a própria iFood ofereceu
  /// (reembolso/benefício/tempo extra) — shape de `disputa.alternativas` não
  /// confirmado ao vivo, leitura defensiva com múltiplos nomes de campo.
  /// Pra tempo extra, os minutos/motivos válidos vêm de dentro da própria
  /// alternativa (`metadata.allowedsAdditionalTimeInMinutes`/`...Reasons`) —
  /// nunca um valor livre, a API espera algo que a iFood já ofereceu.
  Future<void> _proporAlternativa(DisputaMarketplace disputa) async {
    Map<String, dynamic>? escolhida;
    final valorController = TextEditingController();
    int? minutosEscolhidos;
    String? motivoTempoExtra;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Propor alternativa'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...disputa.alternativas.map((a) {
                  final alt = Map<String, dynamic>.from(a as Map);
                  final tipo = (alt['type'] ?? alt['tipo'])?.toString() ?? '';
                  final id = (alt['id'] ?? alt['alternativeId'])?.toString() ?? '';
                  return RadioListTile<String>(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_rotulosAlternativa[tipo] ?? tipo),
                    value: id,
                    groupValue: (escolhida?['id'] ?? escolhida?['alternativeId'])?.toString(),
                    onChanged: (_) => setDialogState(() {
                      escolhida = alt;
                      minutosEscolhidos = null;
                      motivoTempoExtra = null;
                    }),
                  );
                }),
                if (escolhida != null) ...[
                  const SizedBox(height: 8),
                  if ((escolhida!['type'] ?? escolhida!['tipo']) == 'ADDITIONAL_TIME') ...[
                    Builder(builder: (context) {
                      final meta = Map<String, dynamic>.from(
                          (escolhida!['metadata'] as Map?) ?? const {});
                      final minutosPermitidos =
                          (meta['allowedsAdditionalTimeInMinutes'] as List?)?.map((e) => e as int).toList() ??
                              const <int>[];
                      final motivosPermitidos =
                          (meta['allowedsAdditionalTimeReasons'] as List?)?.map((e) => e.toString()).toList() ??
                              const <String>[];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (minutosPermitidos.isNotEmpty)
                            DropdownButtonFormField<int>(
                              initialValue: minutosEscolhidos,
                              decoration: const InputDecoration(labelText: 'Minutos extras'),
                              items: minutosPermitidos
                                  .map((m) => DropdownMenuItem(value: m, child: Text('$m minutos')))
                                  .toList(),
                              onChanged: (v) => setDialogState(() => minutosEscolhidos = v),
                            )
                          else
                            const Text(
                              'Essa disputa não informou opções de minutos — não dá pra propor tempo extra por aqui.',
                              style: TextStyle(color: Colors.red, fontSize: 12),
                            ),
                          const SizedBox(height: 8),
                          if (motivosPermitidos.isNotEmpty)
                            DropdownButtonFormField<String>(
                              initialValue: motivoTempoExtra,
                              decoration: const InputDecoration(labelText: 'Motivo'),
                              items: motivosPermitidos
                                  .map((m) => DropdownMenuItem(value: m, child: Text(_rotuloMotivo(m))))
                                  .toList(),
                              onChanged: (v) => setDialogState(() => motivoTempoExtra = v),
                            ),
                        ],
                      );
                    }),
                  ] else
                    TextField(
                      controller: valorController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(labelText: 'Valor (R\$)'),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: escolhida == null ||
                      ((escolhida!['type'] ?? escolhida!['tipo']) == 'ADDITIONAL_TIME' && minutosEscolhidos == null)
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Propor'),
            ),
          ],
        ),
      ),
    );
    if (confirmado != true || escolhida == null) return;

    final tipo = (escolhida!['type'] ?? escolhida!['tipo'])?.toString() ?? '';
    final id = (escolhida!['id'] ?? escolhida!['alternativeId'])?.toString() ?? '';

    try {
      await _disputaRepository.responderComAlternativa(
        disputa.id,
        alternativaIdExterno: id,
        tipo: tipo,
        valor: double.tryParse(valorController.text.replaceAll(',', '.')),
        minutos: minutosEscolhidos,
        motivo: motivoTempoExtra,
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alternativa proposta.')));
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível propor a alternativa.')));
      }
    }
  }

  /// Rejeitar exige um código de `negotiationReasons` (a API rejeita texto
  /// livre com 400 INVALID_REASON — achado real lendo a doc oficial da
  /// Plataforma de Negociação). Aceitar não exige nada, mas se a disputa
  /// informou `acceptReasons` válidos pra ela, oferece escolher um (fica em
  /// `reason`); o texto livre digitado sempre vai só pro `detailReason`.
  Future<void> _responderDisputa(DisputaMarketplace disputa, {required bool aceitar}) async {
    String? motivoCodigo;
    String? motivoTexto;

    if (!aceitar) {
      motivoCodigo = _motivosRejeitar.first;
      final controller = TextEditingController();
      final confirmado = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Rejeitar disputa'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: motivoCodigo,
                    decoration: const InputDecoration(labelText: 'Motivo (obrigatório pra iFood)'),
                    items: _motivosRejeitar
                        .map((m) => DropdownMenuItem(value: m, child: Text(_rotuloMotivo(m))))
                        .toList(),
                    onChanged: (v) => setDialogState(() => motivoCodigo = v),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    maxLines: 3,
                    decoration: const InputDecoration(hintText: 'Observação interna (opcional)'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Rejeitar')),
            ],
          ),
        ),
      );
      if (confirmado != true) return;
      motivoTexto = controller.text.trim().isEmpty ? null : controller.text.trim();
    } else {
      final controller = TextEditingController();
      final confirmado = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Aceitar disputa'),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(disputa.mensagem ?? 'Confirma aceitar essa contestação?'),
                  if (disputa.acceptReasons.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: motivoCodigo,
                      decoration: const InputDecoration(labelText: 'Motivo (opcional)'),
                      items: disputa.acceptReasons
                          .map((m) => DropdownMenuItem(value: m, child: Text(_rotuloMotivo(m))))
                          .toList(),
                      onChanged: (v) => setDialogState(() => motivoCodigo = v),
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextField(
                    controller: controller,
                    maxLines: 3,
                    maxLength: 250,
                    decoration: const InputDecoration(hintText: 'Observação pra iFood (opcional)'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aceitar')),
            ],
          ),
        ),
      );
      if (confirmado != true) return;
      motivoTexto = controller.text.trim().isEmpty ? null : controller.text.trim();
    }

    try {
      await _disputaRepository.responder(disputa.id, aceitar: aceitar, motivoCodigo: motivoCodigo, motivo: motivoTexto);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(aceitar ? 'Disputa aceita.' : 'Disputa rejeitada.')),
        );
      }
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Não foi possível registrar a resposta.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Avaliações e Disputas'),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: _carregar)],
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'Avaliações (${_avaliacoes.length})'),
            Tab(text: 'Disputas (${_disputas.where((d) => d.pendente).length})'),
          ],
        ),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [_abaAvaliacoes(), _abaDisputas()],
            ),
    );
  }

  Widget _abaAvaliacoes() {
    if (_avaliacoes.isEmpty) {
      return _vazio('Nenhuma avaliação sincronizada ainda.');
    }
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _avaliacoes.length,
        itemBuilder: (context, i) => _cardAvaliacao(_avaliacoes[i]),
      ),
    );
  }

  Widget _cardAvaliacao(AvaliacaoMarketplace avaliacao) {
    final dateFormat = DateFormat('dd/MM/yy HH:mm');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: List.generate(5, (i) {
                    final preenchida = i < avaliacao.nota.round();
                    return Icon(preenchida ? Icons.star : Icons.star_border, color: Colors.amber, size: 18);
                  }),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    '${avaliacao.marketplaceNome} · ${dateFormat.format(avaliacao.dataPedido)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
            if (avaliacao.comentario != null && avaliacao.comentario!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(avaliacao.comentario!),
            ],
            const SizedBox(height: 10),
            if (avaliacao.respondida) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sua resposta', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary)),
                    const SizedBox(height: 4),
                    Text(avaliacao.respostaLoja ?? ''),
                  ],
                ),
              ),
            ] else if (avaliacao.podeResponder)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _responderAvaliacao(avaliacao),
                  child: const Text('Responder'),
                ),
              )
            else
              Text(
                'Aguardando dados da avaliação sincronizarem.',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }

  Widget _abaDisputas() {
    if (_disputas.isEmpty) {
      return _vazio('Nenhuma disputa registrada.');
    }
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _disputas.length,
        itemBuilder: (context, i) => _cardDisputa(_disputas[i]),
      ),
    );
  }

  Widget _cardDisputa(DisputaMarketplace disputa) {
    final dateFormat = DateFormat('dd/MM/yy HH:mm');
    final (corStatus, rotuloStatus) = switch (disputa.status) {
      'aceita' => (Colors.green, 'Aceita'),
      'rejeitada' => (Colors.red, 'Rejeitada'),
      'erro' => (Colors.red, 'Erro ao enviar'),
      'alternativa' => (Colors.blue, 'Alternativa proposta'),
      _ => (disputa.expirada ? Colors.red : Colors.orange, disputa.expirada ? 'Expirada' : 'Pendente'),
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    disputa.tipo ?? 'Contestação',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: corStatus.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(100)),
                  child: Text(rotuloStatus, style: TextStyle(color: corStatus, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (disputa.mensagem != null) Text(disputa.mensagem!),
            if (disputa.itensContestados.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...disputa.itensContestados.map((raw) {
                final item = Map<String, dynamic>.from(raw as Map);
                final qtd = item['quantity'];
                final motivo = item['reason']?.toString();
                return Text(
                  '• ${qtd != null ? '${qtd}x ' : ''}item contestado'
                  '${motivo != null ? ' — $motivo' : ''}',
                  style: const TextStyle(fontSize: 12),
                );
              }),
            ],
            const SizedBox(height: 6),
            Text(
              disputa.prazoExpiracao != null
                  ? 'Prazo: ${dateFormat.format(disputa.prazoExpiracao!)}'
                  : 'Recebida em ${dateFormat.format(disputa.createdAt)}',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            if (disputa.pendente && !disputa.expirada && disputa.timeoutAction != null) ...[
              const SizedBox(height: 2),
              Text(
                'Se não responder a tempo: ${_rotulosTimeoutAction[disputa.timeoutAction] ?? disputa.timeoutAction}.',
                style: const TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ],
            if (disputa.status == 'erro' && disputa.erroResposta != null) ...[
              const SizedBox(height: 6),
              Text(disputa.erroResposta!, style: const TextStyle(fontSize: 12, color: Colors.red)),
            ],
            if (disputa.pendente && !disputa.expirada) ...[
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (disputa.temAlternativas)
                    TextButton(
                      onPressed: () => _proporAlternativa(disputa),
                      child: const Text('Propor alternativa'),
                    ),
                  OutlinedButton(
                    onPressed: () => _responderDisputa(disputa, aceitar: false),
                    child: const Text('Rejeitar'),
                  ),
                  FilledButton(
                    onPressed: () => _responderDisputa(disputa, aceitar: true),
                    child: const Text('Aceitar'),
                  ),
                ],
              ),
            ],
            if (disputa.status == 'alternativa') ...[
              const SizedBox(height: 6),
              Text(
                'Alternativa proposta, aguardando resposta da iFood (evento HANDSHAKE_SETTLEMENT).',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _vazio(String texto) {
    return Center(
      child: Text(texto, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }
}
