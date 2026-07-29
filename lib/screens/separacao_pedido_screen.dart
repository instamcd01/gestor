import 'package:flutter/material.dart';

import '../models/produto.dart';
import '../models/venda.dart';
import '../repositories/produto_repository.dart';
import '../repositories/separacao_pedido_repository.dart';
import '../widgets/aviso_banner.dart';

enum _AcaoItem { removido, substituido }

/// Separação de pedido de Mercado na iFood (Picking API) — trocar ou
/// remover um item que faltou na hora de separar o carrinho.
///
/// IMPORTANTE: Picking tem homologação própria na iFood, separada do resto
/// da integração — pode não estar liberado pra essa loja mesmo com
/// credenciais válidas. As ações aqui são staged (registradas em
/// marketplace_separacao_acoes e aplicadas na hora pelo n8n), só ficam
/// definitivas do lado da iFood quando a separação é finalizada.
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
  final Map<String, _AcaoItem> _acoes = {};
  final Map<String, Produto> _substitutos = {};
  bool _processando = false;
  List<Produto> _catalogo = [];

  @override
  void initState() {
    super.initState();
    _status = widget.venda.separacaoStatus;
  }

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
      setState(() => _acoes[itemPedidoId] = _AcaoItem.removido);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível remover o item.')));
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _substituirItem(ItemVenda item) async {
    if (_catalogo.isEmpty) {
      try {
        _catalogo = await _produtoRepository.listar();
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível carregar o catálogo.')));
        return;
      }
    }
    if (!mounted) return;

    final buscaController = TextEditingController();
    Produto? escolhido;
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final busca = buscaController.text.trim().toLowerCase();
          final filtrados = busca.isEmpty
              ? _catalogo.take(20).toList()
              : _catalogo.where((p) => p.nome.toLowerCase().contains(busca)).take(20).toList();
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
      setState(() {
        _acoes[item.id!] = _AcaoItem.substituido;
        _substitutos[item.id!] = escolhido!;
      });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Não foi possível substituir o item.')));
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
        setState(() => _status = 'finalizada');
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Separação finalizada.')));
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
              const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: AvisoBanner(
                  tipo: TipoAviso.alerta,
                  texto: 'Módulo de Picking da iFood tem liberação separada — se as ações abaixo derem erro, pode ser que '
                      'esse recurso ainda não esteja habilitado pra essa loja.',
                ),
              ),
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
                if (_status == 'finalizada')
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: AvisoBanner(tipo: TipoAviso.sucesso, texto: 'Separação finalizada'),
                  ),
                ...itens.map((item) => _itemCard(item)),
                if (_status == 'separando') ...[
                  const SizedBox(height: 16),
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

  Widget _itemCard(ItemVenda item) {
    final acao = item.id != null ? _acoes[item.id] : null;
    final substituto = item.id != null ? _substitutos[item.id] : null;

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
                      decoration: acao == _AcaoItem.removido ? TextDecoration.lineThrough : null,
                    ),
                  ),
                  Text('${item.quantidade}x', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  if (item.observacaoCliente != null && item.observacaoCliente!.isNotEmpty)
                    Text('"${item.observacaoCliente}"',
                        style: const TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.orange)),
                  if (acao == _AcaoItem.removido)
                    const Text('Removido', style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold)),
                  if (acao == _AcaoItem.substituido && substituto != null)
                    Text('Substituído por: ${substituto.nome}',
                        style: const TextStyle(color: Colors.blue, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            if (_status == 'separando' && acao == null && item.id != null)
              Row(
                children: [
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
}
