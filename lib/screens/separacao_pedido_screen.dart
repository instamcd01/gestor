import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/produto.dart';
import '../models/venda.dart';
import '../repositories/ifood_merchant_repository.dart';
import '../repositories/produto_repository.dart';
import '../repositories/separacao_pedido_repository.dart';
import '../utils/busca_utils.dart';
import '../widgets/aviso_banner.dart';

/// Separação de pedido de Mercado na iFood (Picking API) — trocar ou
/// remover um item que faltou na hora de separar o carrinho.
///
/// Cada ação é gravada em `marketplace_separacao_acoes` (staged) e aplicada
/// de forma assíncrona pelo n8n — o app nunca fala com a iFood diretamente,
/// e nunca assume que uma ação deu certo só porque o registro foi salvo.
/// `_acoes` é recarregado (`_atualizarAcoes`) logo após cada ação e a cada
/// 2s enquanto alguma ainda estiver `pendente`, pra mostrar o resultado
/// real (aplicada/erro) assim que o n8n confirmar.
class SeparacaoPedidoScreen extends StatefulWidget {
  final Venda venda;

  const SeparacaoPedidoScreen({super.key, required this.venda});

  @override
  State<SeparacaoPedidoScreen> createState() => _SeparacaoPedidoScreenState();
}

class _SeparacaoPedidoScreenState extends State<SeparacaoPedidoScreen> {
  final _repository = SeparacaoPedidoRepository();
  final _produtoRepository = ProdutoRepository();

  late String? _status;
  List<Map<String, dynamic>> _acoes = [];
  Map<String, dynamic>? _confirmacao;
  int _tentativasConfirmacao = 0;
  Timer? _pollAcoesTimer;
  Timer? _pollConfirmacaoTimer;
  Timer? _pollChamadasTimer;
  List<Map<String, dynamic>> _chamadas = [];
  bool _processando = false;
  List<Produto> _catalogo = [];

  bool get _ehIfood => widget.venda.canalVenda == 'ifood';

  final _ifoodRepository = IfoodMerchantRepository();
  RespostaIfood? _virtualBag;
  bool _consultandoBag = false;

  /// GET virtual-bag na hora: o pedido como o iFood tem agora (itens e
  /// quantidades), pra conferir antes de separar e depois de finalizar.
  Future<void> _consultarVirtualBag() async {
    setState(() => _consultandoBag = true);
    final r = await _ifoodRepository.consultarPedido(widget.venda.marketplacePedidoId!);
    if (mounted) setState(() { _virtualBag = r; _consultandoBag = false; });
    _atualizarChamadas();
  }

  /// Chamadas à API do iFood deste pedido — a "tela de logs" que o iFood
  /// pede no vídeo de homologação do Picking. Atualiza a cada 3 s enquanto a
  /// tela está aberta (o n8n grava o resultado de forma assíncrona).
  Future<void> _atualizarChamadas() async {
    final id = widget.venda.marketplacePedidoId;
    if (id == null || !_ehIfood) return;
    try {
      final chamadas = await _repository.buscarChamadas(id);
      if (mounted) setState(() => _chamadas = chamadas);
    } catch (_) {
      // Silencioso — a próxima volta do timer tenta de novo.
    }
  }

  String _hora(String? iso) {
    final d = DateTime.tryParse(iso ?? '')?.toLocal();
    if (d == null) return '--:--:--';
    String dd(int v) => v.toString().padLeft(2, '0');
    return '${dd(d.hour)}:${dd(d.minute)}:${dd(d.second)}';
  }

  Color _corMetodo(String m) => switch (m) {
        'GET' => Colors.blue,
        'POST' => Colors.green,
        'PATCH' => Colors.orange,
        'DELETE' => Colors.red,
        _ => Colors.grey,
      };

  Widget _cardChamadas() {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.receipt_long_outlined, size: 18),
            const SizedBox(width: 6),
            const Expanded(child: Text('Chamadas à API do iFood', style: TextStyle(fontWeight: FontWeight.w600))),
            Text('${_chamadas.length}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
          const SizedBox(height: 6),
          if (_chamadas.isEmpty)
            const Text('Nenhuma chamada ainda neste pedido.', style: TextStyle(fontSize: 12, color: Colors.grey))
          else
            ..._chamadas.map((c) {
              final metodo = c['metodo'] as String? ?? '?';
              final ok = c['sucesso'] == true;
              final status = c['http_status'] as int?;
              final resultado = ok ? (status != null ? '$status OK' : 'Sucesso') : (status != null ? '$status ERRO' : 'Erro');
              final detalhe = c['detalhe'] as String?;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 62, child: Text(_hora(c['created_at'] as String?), style: const TextStyle(fontFamily: 'monospace', fontSize: 11))),
                  Container(
                    width: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(color: _corMetodo(metodo).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                    child: Text(metodo, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _corMetodo(metodo))),
                  ),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SelectableText(c['endpoint'] as String? ?? '', style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                      if (detalhe != null && detalhe.isNotEmpty)
                        Text(detalhe, style: TextStyle(fontSize: 11, color: ok ? Colors.grey : Colors.red), maxLines: 3, overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                  const SizedBox(width: 6),
                  Text(resultado, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ok ? Colors.green : Colors.red)),
                ]),
              );
            }),
        ]),
      ),
    );
  }

  /// Acha a lista de itens dentro da resposta da virtual bag, onde quer
  /// que ela esteja (bag.items / items / orders[].items).
  List<Map> _itensDaBag(dynamic d) {
    if (d is Map) {
      for (final k in ['items', 'bag', 'orders', 'order']) {
        final v = d[k];
        if (k == 'items' && v is List) return v.whereType<Map>().toList();
        final achou = _itensDaBag(v);
        if (achou.isNotEmpty) return achou;
      }
    } else if (d is List) {
      for (final x in d) {
        final achou = _itensDaBag(x);
        if (achou.isNotEmpty) return achou;
      }
    }
    return const [];
  }

  Widget _cardVirtualBag() {
    final r = _virtualBag;
    final hora = r == null ? '' : '${r.em.day.toString().padLeft(2, '0')}/${r.em.month.toString().padLeft(2, '0')} '
        '${r.em.hour.toString().padLeft(2, '0')}:${r.em.minute.toString().padLeft(2, '0')}:${r.em.second.toString().padLeft(2, '0')}';
    final itens = r == null ? const <Map>[] : _itensDaBag(r.dados);
    String corpo = '';
    if (r != null) {
      try {
        corpo = const JsonEncoder.withIndent('  ').convert(r.dados);
      } catch (_) {
        corpo = '${r.dados}';
      }
    }
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          OutlinedButton.icon(
            onPressed: _consultandoBag ? null : _consultarVirtualBag,
            icon: _consultandoBag
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.manage_search),
            label: const Text('Consultar pedido no iFood (virtual bag)'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 44)),
          ),
          if (r != null) ...[
            const SizedBox(height: 8),
            Text(r.ok ? 'Pedido no iFood agora ($hora):' : 'O iFood respondeu ${r.status} ($hora): ${r.erro ?? ''}',
                style: TextStyle(fontWeight: FontWeight.w600, color: r.ok ? null : Colors.red)),
            ...itens.map((i) => Text('• ${i['quantity'] ?? i['quantidade'] ?? '?'}x ${i['name'] ?? i['description'] ?? i['ean'] ?? '-'}',
                style: const TextStyle(fontSize: 13))),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Resposta completa (GET /orders/{id}/virtual-bag)', style: TextStyle(fontSize: 12)),
              children: [
                SelectableText(corpo.length > 6000 ? '${corpo.substring(0, 6000)} …' : corpo,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
              ],
            ),
          ],
        ]),
      ),
    );
  }

  /// Motivo real quando o iFood recusou finalizar (gravado pelo n8n).
  String? _erroFinalizacao;

  /// Pedido iFood pago em DINHEIRO na entrega não pode ser editado: o iFood
  /// aceita alterar/remover um a um mas recusa tudo no endSeparation ("A
  /// forma de pagamento escolhida pelo cliente não permite a edição do
  /// pedido") — confirmado no ensaio de homologação 02/10.
  bool get _edicaoBloqueadaPorPagamento =>
      _ehIfood && widget.venda.statusPagamento != 'pago' && widget.venda.metodoPagamento == 'Dinheiro';

  /// Outros pagamentos na entrega (cartão na maquininha) ainda não foram
  /// testados — libera, mas avisa.
  bool get _edicaoPodeSerRecusada =>
      _ehIfood && widget.venda.statusPagamento != 'pago' && !_edicaoBloqueadaPorPagamento;

  @override
  void initState() {
    super.initState();
    _status = widget.venda.separacaoStatus;
    if (_status != null) _atualizarAcoes();
    if (_status == 'finalizada') _atualizarConfirmacao();
    if (_ehIfood) {
      _atualizarChamadas();
      _pollChamadasTimer = Timer.periodic(const Duration(seconds: 3), (_) => _atualizarChamadas());
    }
  }

  @override
  void dispose() {
    _pollAcoesTimer?.cancel();
    _pollConfirmacaoTimer?.cancel();
    _pollChamadasTimer?.cancel();
    super.dispose();
  }

  Future<void> _atualizarAcoes() async {
    try {
      final acoes = await _repository.buscarAcoes(widget.venda.marketplacePedidoId!);
      if (!mounted) return;
      setState(() => _acoes = acoes);
      _pollAcoesTimer?.cancel();
      final temPendente = acoes.any((a) => (a['status'] as String? ?? 'pendente') == 'pendente');
      if (temPendente) _pollAcoesTimer = Timer(const Duration(seconds: 2), _atualizarAcoes);
    } catch (_) {
      // Silencioso — a próxima ação ou o refresh manual tenta de novo.
    }
  }

  /// A consulta pós-separação que confirma os itens roda no n8n logo depois
  /// de finalizar; tenta ler o resultado por até ~16s (8 tentativas de 2s)
  /// antes de desistir e deixar só o "aguardando".
  Future<void> _atualizarConfirmacao() async {
    try {
      final resultado = await _repository.buscarConfirmacaoPosSeparacao(widget.venda.marketplacePedidoId!);
      if (!mounted) return;
      // iFood recusou o endSeparation: o n8n voltou pra 'separando' com o
      // motivo — a tela tinha assumido 'finalizada', desfaz e mostra.
      final erro = resultado?['separacao_erro'] as String?;
      if (resultado?['separacao_status'] == 'separando' && erro != null && erro.isNotEmpty) {
        _pollConfirmacaoTimer?.cancel();
        setState(() {
          _status = 'separando';
          _erroFinalizacao = erro;
        });
        return;
      }
      setState(() => _confirmacao = resultado);
      _tentativasConfirmacao++;
      _pollConfirmacaoTimer?.cancel();
      if (resultado?['itens_confirmados_ifood'] == null && _tentativasConfirmacao < 8) {
        _pollConfirmacaoTimer = Timer(const Duration(seconds: 2), _atualizarConfirmacao);
      }
    } catch (_) {
      // Silencioso — mesma lógica de _atualizarAcoes.
    }
  }

  Map<String, dynamic>? _acaoDoItem(String itemPedidoId) {
    for (final a in _acoes.reversed) {
      if (a['item_pedido_id'] == itemPedidoId) return a;
    }
    return null;
  }

  List<Map<String, dynamic>> get _acoesAdicionar => _acoes.where((a) => a['tipo_acao'] == 'adicionar').toList();

  Future<void> _iniciar() async {
    setState(() => _processando = true);
    try {
      await _repository.iniciar(widget.venda.marketplacePedidoId!);
      setState(() => _status = 'separando');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível iniciar a separação.')));
      }
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _removerItem(String itemPedidoId) async {
    setState(() => _processando = true);
    try {
      await _repository.removerItem(marketplacePedidoId: widget.venda.marketplacePedidoId!, itemPedidoId: itemPedidoId);
      await _atualizarAcoes();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível remover o item.')));
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<bool> _carregarCatalogo() async {
    if (_catalogo.isNotEmpty) return true;
    try {
      _catalogo = await _produtoRepository.listar();
      return true;
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível carregar o catálogo.')));
      return false;
    }
  }

  Future<void> _substituirItem(ItemVenda item) async {
    if (!await _carregarCatalogo()) return;
    if (!mounted) return;

    final buscaController = TextEditingController();
    Produto? escolhido;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final busca = buscaController.text.trim();
          final filtrados = busca.isEmpty
              ? _catalogo.take(20).toList()
              : _catalogo.where((p) => contemTodasPalavras(p.nome, busca)).take(20).toList();
          return AlertDialog(
            title: Text('Substituir "${item.produto.nome}"'),
            content: SizedBox(
              width: double.maxFinite,
              height: 360,
              child: Column(
                children: [
                  if (item.sugestoesSubstituicao != null && item.sugestoesSubstituicao!.isNotEmpty) ...[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Sugestões da iFood', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 32,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: item.sugestoesSubstituicao!.map((s) {
                          final nome = s['name']?.toString() ?? '';
                          return Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ActionChip(
                              label: Text(nome, style: const TextStyle(fontSize: 12)),
                              onPressed: () {
                                buscaController.text = nome;
                                setDialogState(() {});
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: buscaController,
                    decoration: const InputDecoration(labelText: 'Buscar produto', prefixIcon: Icon(Icons.search)),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtrados.length,
                      itemBuilder: (ctx, i) {
                        final p = filtrados[i];
                        return RadioListTile<String>(
                          title: Text(p.nome),
                          subtitle: Text('R\$ ${p.preco.toStringAsFixed(2)}'),
                          value: p.id ?? p.nome,
                          groupValue: escolhido?.id ?? escolhido?.nome,
                          onChanged: (_) => setDialogState(() => escolhido = p),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              FilledButton(onPressed: escolhido == null ? null : () => Navigator.pop(ctx, true), child: const Text('Substituir')),
            ],
          );
        },
      ),
    );
    if (confirmado != true || escolhido == null || item.id == null) return;

    setState(() => _processando = true);
    try {
      await _repository.substituirItem(
        marketplacePedidoId: widget.venda.marketplacePedidoId!,
        itemPedidoId: item.id!,
        produtoSubstitutoId: escolhido!.id!,
        quantidade: item.quantidade.toDouble(),
      );
      await _atualizarAcoes();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível substituir o item.')));
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _modificarQuantidade(ItemVenda item) async {
    if (item.id == null) return;
    final controller = TextEditingController(text: item.quantidade.toString());
    final novaQuantidade = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Alterar quantidade de "${item.produto.nome}"'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Nova quantidade',
            helperText: _ehIfood
                ? 'Só dá pra reduzir (pedido original: ${item.quantidade}x) — o iFood não aceita aumentar nem adicionar itens.'
                : 'Só dá pra reduzir (pedido original: ${item.quantidade}x) — pra pedir mais, use "Adicionar item".',
            helperMaxLines: 2,
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, double.tryParse(controller.text.replaceAll(',', '.'))),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (novaQuantidade == null || novaQuantidade <= 0) return;
    if (novaQuantidade > item.quantidade && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_ehIfood
              ? 'O iFood não permite aumentar a quantidade de um item na separação.'
              : 'Não dá pra aumentar a quantidade aqui — use "Adicionar item" pra isso.'),
        ),
      );
      return;
    }

    setState(() => _processando = true);
    try {
      await _repository.modificarItem(
        marketplacePedidoId: widget.venda.marketplacePedidoId!,
        itemPedidoId: item.id!,
        quantidade: novaQuantidade,
      );
      await _atualizarAcoes();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível alterar a quantidade.')));
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  /// "Separei completo": confirma ao iFood o item com a quantidade do pedido
  /// (PATCH com a mesma quantidade) — o checklist do Picking pede um item
  /// confirmado sem mudança, além do alterado e do removido.
  Future<void> _confirmarCompleto(ItemVenda item) async {
    if (item.id == null) return;
    setState(() => _processando = true);
    try {
      await _repository.modificarItem(
        marketplacePedidoId: widget.venda.marketplacePedidoId!,
        itemPedidoId: item.id!,
        quantidade: item.quantidade.toDouble(),
        confirmacaoCompleta: true,
      );
      await _atualizarAcoes();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível confirmar o item.')));
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _adicionarItem() async {
    if (!await _carregarCatalogo()) return;
    if (!mounted) return;

    final buscaController = TextEditingController();
    final quantidadeController = TextEditingController(text: '1');
    Produto? escolhido;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final busca = buscaController.text.trim();
          final filtrados = busca.isEmpty
              ? _catalogo.take(20).toList()
              : _catalogo.where((p) => contemTodasPalavras(p.nome, busca)).take(20).toList();
          return AlertDialog(
            title: const Text('Adicionar item ao pedido'),
            content: SizedBox(
              width: double.maxFinite,
              height: 400,
              child: Column(
                children: [
                  TextField(
                    controller: buscaController,
                    decoration: const InputDecoration(labelText: 'Buscar produto', prefixIcon: Icon(Icons.search)),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtrados.length,
                      itemBuilder: (ctx, i) {
                        final p = filtrados[i];
                        return RadioListTile<String>(
                          title: Text(p.nome),
                          subtitle: Text('R\$ ${p.preco.toStringAsFixed(2)}'),
                          value: p.id ?? p.nome,
                          groupValue: escolhido?.id ?? escolhido?.nome,
                          onChanged: (_) => setDialogState(() => escolhido = p),
                        );
                      },
                    ),
                  ),
                  TextField(
                    controller: quantidadeController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Quantidade'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
              FilledButton(onPressed: escolhido == null ? null : () => Navigator.pop(ctx, true), child: const Text('Adicionar')),
            ],
          );
        },
      ),
    );
    final quantidade = double.tryParse(quantidadeController.text.replaceAll(',', '.'));
    if (confirmado != true || escolhido == null || quantidade == null || quantidade <= 0) return;

    setState(() => _processando = true);
    try {
      await _repository.adicionarItem(
        marketplacePedidoId: widget.venda.marketplacePedidoId!,
        produtoId: escolhido!.id!,
        quantidade: quantidade,
      );
      await _atualizarAcoes();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível adicionar o item.')));
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _finalizar() async {
    // Não deixa finalizar com troca/remoção ainda a caminho do iFood: depois do
    // endSeparation o iFood não aceita mais mudança e o item iria no pedido.
    await _atualizarAcoes();
    if (!mounted) return;
    final pendentes = _acoes.where((a) => (a['status'] as String? ?? 'pendente') == 'pendente').length;
    if (pendentes > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(pendentes == 1
            ? 'Ainda tem 1 alteração indo pro iFood. Espere ela confirmar pra finalizar.'
            : 'Ainda tem $pendentes alterações indo pro iFood. Espere confirmarem pra finalizar.'),
      ));
      return;
    }
    final comErro = _acoes.where((a) => a['status'] == 'erro').length;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar separação'),
        content: Text(comErro > 0
            ? '$comErro alteração(ões) não chegaram ao iFood e NÃO vão valer. Faça de novo antes, ou finalize assim mesmo.'
            : 'Isso envia todas as trocas/remoções pra iFood definitivamente. Confirmar?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Finalizar')),
        ],
      ),
    );
    if (confirmado != true) return;

    setState(() => _processando = true);
    try {
      await _repository.finalizar(widget.venda.marketplacePedidoId!);
      if (mounted) {
        setState(() {
          _status = 'finalizada';
          _erroFinalizacao = null;
          _tentativasConfirmacao = 0;
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Separação finalizada.')));
        _atualizarConfirmacao();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível finalizar.')));
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final itens = widget.venda.itens;

    return Scaffold(
      appBar: AppBar(title: const Text('Separação do pedido')),
      body: Stack(
        children: [
          ListView(
            padding: const EdgeInsets.all(12),
            children: [
              if (widget.venda.politicaSubstituicao == 'STORE_REMOVE_ITEMS')
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: AvisoBanner(
                    tipo: TipoAviso.erro,
                    negrito: true,
                    texto: 'Cliente NÃO autoriza substituição — só remova itens em falta, não troque por outro produto.',
                  ),
                )
              else if (widget.venda.politicaSubstituicao != null)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: AvisoBanner(
                    tipo: TipoAviso.sucesso,
                    texto: 'Cliente autoriza substituição de item em falta.',
                  ),
                ),
              if (_edicaoBloqueadaPorPagamento)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: AvisoBanner(
                    tipo: TipoAviso.erro,
                    negrito: true,
                    texto: 'Pedido pago em dinheiro na entrega: o iFood não permite alterar, substituir ou '
                        'remover itens. Separe como está e finalize — se faltar algo, fale com o cliente ou cancele.',
                  ),
                )
              else if (_edicaoPodeSerRecusada)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: AvisoBanner(
                    tipo: TipoAviso.alerta,
                    texto: 'Pagamento na entrega: o iFood pode recusar edições ao finalizar. '
                        'Se recusar, o motivo aparece aqui.',
                  ),
                ),
              if (_erroFinalizacao != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: AvisoBanner(
                    tipo: TipoAviso.erro,
                    negrito: true,
                    texto: 'O iFood recusou finalizar: $_erroFinalizacao',
                  ),
                ),
              if (_ehIfood) _cardVirtualBag(),
              if (_ehIfood) _cardChamadas(),
              if (_status == null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: FilledButton(
                    onPressed: _processando ? null : _iniciar,
                    style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                    child: const Text('Iniciar separação'),
                  ),
                )
              else ...[
                if (_status == 'finalizada') ...[
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: AvisoBanner(tipo: TipoAviso.sucesso, texto: 'Separação finalizada'),
                  ),
                  _cardConfirmacaoPosSeparacao(),
                ],
                ...itens.map((item) => _itemCard(item)),
                ..._acoesAdicionar.map(_itemAdicionadoCard),
                if (_status == 'separando') ...[
                  const SizedBox(height: 8),
                  // Picking do iFood só aceita adicionar item em pedido White
                  // Label (doc + resposta real ITEM_ADD_NOT_ALLOWED, 17/09);
                  // no marketplace iFood o botão só gerava erro.
                  if (!_ehIfood)
                    OutlinedButton.icon(
                      onPressed: _processando ? null : _adicionarItem,
                      icon: const Icon(Icons.add),
                      label: const Text('Adicionar item ao pedido'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 44)),
                    ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: _processando ? null : _finalizar,
                    style: FilledButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                    child: const Text('Finalizar separação'),
                  ),
                ],
              ],
            ],
          ),
          if (_processando) Container(color: Colors.black26, child: const Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }

  /// Confirmação real da iFood (não o que o app assumiu) — só existe depois
  /// de finalizar, alimentada por `marketplace_pedidos.itens_confirmados_ifood`
  /// (gravado pelo n8n a partir da consulta automática pós-separação).
  Widget _cardConfirmacaoPosSeparacao() {
    final itensConfirmados = _confirmacao?['itens_confirmados_ifood'] as List?;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: Colors.green.withValues(alpha: 0.06),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Confirmado pela iFood após a separação', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 6),
              if (itensConfirmados == null)
                const Row(
                  children: [
                    SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Aguardando confirmação da iFood...', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                )
              else
                ...itensConfirmados.map((raw) {
                  final it = Map<String, dynamic>.from(raw as Map);
                  final nome = it['name']?.toString() ?? '';
                  final quantidade = it['quantity'];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text('• ${quantidade}x $nome', style: const TextStyle(fontSize: 12)),
                  );
                }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _itemCard(ItemVenda item) {
    final acao = item.id != null ? _acaoDoItem(item.id!) : null;
    final status = acao?['status'] as String?;
    final tipoAcao = acao?['tipo_acao'] as String?;
    final removidoAplicado = tipoAcao == 'remover' && status == 'aplicada';
    final confirmadoCompleto = tipoAcao == 'modificar' && acao?['confirmacao_completa'] == true;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.produto.nome,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      decoration: removidoAplicado ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  Text(
                    tipoAcao == 'modificar' && status == 'aplicada' && !confirmadoCompleto
                        ? '${acao?['quantidade']}x (era ${item.quantidade}x)'
                        : '${item.quantidade}x',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  if (item.observacaoCliente != null && item.observacaoCliente!.isNotEmpty)
                    Text('"${item.observacaoCliente}"',
                        style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.orange)),
                  if (acao != null) _statusAcaoTexto(acao, confirmadoCompleto: confirmadoCompleto),
                ],
              ),
            ),
            // Ação com erro não chegou ao iFood: libera os botões pra fazer de novo.
            if (_status == 'separando' && (acao == null || status == 'erro') && item.id != null && !_edicaoBloqueadaPorPagamento)
              Row(
                children: [
                  if (_ehIfood)
                    IconButton(
                      icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                      tooltip: 'Separei completo',
                      onPressed: _processando ? null : () => _confirmarCompleto(item),
                    ),
                  IconButton(
                    icon: const Icon(Icons.edit_outlined),
                    tooltip: 'Alterar quantidade',
                    onPressed: _processando ? null : () => _modificarQuantidade(item),
                  ),
                  IconButton(
                    icon: const Icon(Icons.swap_horiz),
                    tooltip: 'Substituir',
                    onPressed: _processando ? null : () => _substituirItem(item),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                    tooltip: 'Remover',
                    onPressed: _processando ? null : () => _removerItem(item.id!),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Texto real do estado da ação — nunca assume sucesso: `pendente` é só
  /// intenção registrada, `aplicada`/`erro` é o que o n8n confirmou de volta
  /// da iFood (com a mensagem real do erro, quando houver).
  Widget _statusAcaoTexto(Map<String, dynamic> acao, {bool confirmadoCompleto = false}) {
    final status = acao['status'] as String? ?? 'pendente';
    if (status == 'pendente') {
      return const Padding(
        padding: EdgeInsets.only(top: 2),
        child: Row(
          children: [
            SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 6),
            Text('Enviando pra iFood...', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      );
    }
    if (status == 'erro') {
      return Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          'Erro: ${acao['erro'] ?? 'não foi possível aplicar'}',
          style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
        ),
      );
    }
    final tipo = acao['tipo_acao'] as String?;
    final produtoNome = (acao['produtos'] as Map?)?['nome']?.toString();
    final rotulo = switch (tipo) {
      'remover' => 'Removido ✓',
      'substituir' => 'Substituído por: ${produtoNome ?? '?'} ✓',
      'modificar' => confirmadoCompleto ? 'Separado completo ✓' : 'Quantidade alterada ✓',
      'adicionar' => 'Adicionado ao pedido ✓',
      _ => 'Aplicado ✓',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(rotulo, style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  Widget _itemAdicionadoCard(Map<String, dynamic> acao) {
    final produtoNome = (acao['produtos'] as Map?)?['nome']?.toString() ?? '?';
    final quantidade = acao['quantidade'];
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: Colors.blue.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(produtoNome, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('${quantidade}x', style: const TextStyle(fontSize: 12, color: Colors.grey)),
            _statusAcaoTexto({...acao, 'tipo_acao': 'adicionar'}),
          ],
        ),
      ),
    );
  }
}
