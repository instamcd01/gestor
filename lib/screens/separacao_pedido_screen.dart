import 'dart:async';

import 'package:flutter/material.dart';

import '../models/produto.dart';
import '../models/venda.dart';
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
  bool _processando = false;
  List<Produto> _catalogo = [];

  @override
  void initState() {
    super.initState();
    _status = widget.venda.separacaoStatus;
    if (_status != null) _atualizarAcoes();
    if (_status == 'finalizada') _atualizarConfirmacao();
  }

  @override
  void dispose() {
    _pollAcoesTimer?.cancel();
    _pollConfirmacaoTimer?.cancel();
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
            helperText: 'Só dá pra reduzir (pedido original: ${item.quantidade}x) — pra pedir mais, use "Adicionar item".',
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
        const SnackBar(content: Text('A iFood não permite aumentar a quantidade aqui — use "Adicionar item" pra isso.')),
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
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar separação'),
        content: const Text('Isso envia todas as trocas/remoções pra iFood definitivamente. Confirmar?'),
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
                    tipoAcao == 'modificar' && status == 'aplicada'
                        ? '${acao?['quantidade']}x (era ${item.quantidade}x)'
                        : '${item.quantidade}x',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  if (item.observacaoCliente != null && item.observacaoCliente!.isNotEmpty)
                    Text('"${item.observacaoCliente}"',
                        style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.orange)),
                  if (acao != null) _statusAcaoTexto(acao),
                ],
              ),
            ),
            if (_status == 'separando' && acao == null && item.id != null)
              Row(
                children: [
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
  Widget _statusAcaoTexto(Map<String, dynamic> acao) {
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
      'modificar' => 'Quantidade alterada ✓',
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
