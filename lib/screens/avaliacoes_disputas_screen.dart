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

  /// Contraproposta usando uma das alternativas que a própria iFood ofereceu
  /// (reembolso/benefício/tempo extra) — shape de `disputa.alternativas` não
  /// confirmado ao vivo, leitura defensiva com múltiplos nomes de campo.
  Future<void> _proporAlternativa(DisputaMarketplace disputa) async {
    Map<String, dynamic>? escolhida;
    final valorController = TextEditingController();
    final minutosController = TextEditingController();

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
                    onChanged: (_) => setDialogState(() => escolhida = alt),
                  );
                }),
                if (escolhida != null) ...[
                  const SizedBox(height: 8),
                  if ((escolhida!['type'] ?? escolhida!['tipo']) == 'ADDITIONAL_TIME')
                    TextField(
                      controller: minutosController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Minutos extras'),
                    )
                  else
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
            FilledButton(onPressed: escolhida == null ? null : () => Navigator.pop(ctx, true), child: const Text('Propor')),
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
        minutos: int.tryParse(minutosController.text),
      );
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Alternativa proposta.')));
      await _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível propor a alternativa.')));
      }
    }
  }

  Future<void> _responderDisputa(DisputaMarketplace disputa, {required bool aceitar}) async {
    String? motivo;
    if (!aceitar) {
      final controller = TextEditingController();
      final confirmado = await showDialog<bool>(
        context: context,
        // Sem autofocus + sem fechar tocando fora: com o teclado aberto (via
        // autofocus) e o diálogo fechando por barrier-dismiss no mesmo frame,
        // bate num bug conhecido do framework do Flutter (assert
        // `_dependents.isEmpty` ao desativar o Overlay/IME) — só os botões
        // fecham o diálogo agora.
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Rejeitar disputa'),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(hintText: 'Motivo (opcional)'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Rejeitar')),
          ],
        ),
      );
      if (confirmado != true) return;
      motivo = controller.text.trim().isEmpty ? null : controller.text.trim();
    } else {
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Aceitar disputa'),
          content: Text(disputa.mensagem ?? 'Confirma aceitar essa contestação?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Aceitar')),
          ],
        ),
      );
      if (confirmado != true) return;
    }

    try {
      await _disputaRepository.responder(disputa.id, aceitar: aceitar, motivo: motivo);
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
            const SizedBox(height: 6),
            Text(
              disputa.prazoExpiracao != null
                  ? 'Prazo: ${dateFormat.format(disputa.prazoExpiracao!)}'
                  : 'Recebida em ${dateFormat.format(disputa.createdAt)}',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            if (disputa.status == 'erro' && disputa.erroResposta != null) ...[
              const SizedBox(height: 6),
              Text(disputa.erroResposta!, style: const TextStyle(fontSize: 12, color: Colors.red)),
            ],
            if (disputa.pendente) ...[
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
