import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/produto.dart';
import '../providers/produto_provider.dart';
import '../repositories/produto_midia_repository.dart';
import '../utils/busca_utils.dart';
import '../utils/empresa_atual.dart';
import '../utils/upload_imagem_produto.dart';
import 'cortar_imagem_screen.dart';

enum _StatusItemLote { pendente, enviando, sucesso, erro }

class _ItemImagemLote {
  _ItemImagemLote({required this.bytes});

  Uint8List bytes;
  Produto? produto;
  _StatusItemLote status = _StatusItemLote.pendente;
  String? erro;
}

/// Tela pra adicionar várias fotos de produto de uma vez: escolhe todas as
/// imagens primeiro, depois só vincula cada uma ao produto correspondente —
/// evita repetir cadastro → galeria → adicionar imagem, produto por
/// produto. Usa o mesmo processamento e a mesma convenção de nome de
/// arquivo (fabricante/código de barras) do upload individual, em
/// `uploadImagemProduto`.
class AdicionarImagensLoteScreen extends StatefulWidget {
  const AdicionarImagensLoteScreen({super.key, this.produtosPendentes});

  /// Fila de produtos sem imagem, na ordem em que devem receber as próximas
  /// fotos escolhidas — vem da aba "Sem imagem" da Análise de Produtos em
  /// massa, que já mostra a lista de produtos antes de pedir as fotos
  /// (inverte o fluxo padrão desta tela, que normalmente começa pelas
  /// fotos e só depois vincula produto por produto).
  final List<Produto>? produtosPendentes;

  @override
  State<AdicionarImagensLoteScreen> createState() => _AdicionarImagensLoteScreenState();
}

class _AdicionarImagensLoteScreenState extends State<AdicionarImagensLoteScreen> {
  final _repo = ProdutoMidiaRepository();
  final List<_ItemImagemLote> _itens = [];
  late List<Produto> _filaProdutos;
  bool _enviando = false;
  String? _empresaId;

  @override
  void initState() {
    super.initState();
    _filaProdutos = List.of(widget.produtosPendentes ?? const []);
  }

  Future<void> _adicionarImagens() async {
    List<XFile> arquivos;
    try {
      arquivos = await ImagePicker().pickMultiImage();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao selecionar imagens: $e')),
      );
      return;
    }
    if (arquivos.isEmpty) return;

    // O picker devolve os arquivos em ordem invertida à ordem em que foram
    // tocados na galeria nativa (observado tanto no Android quanto no iOS)
    // — sem inverter aqui, a 1ª foto escolhida virava a última da lista e
    // acabava vinculada ao último produto da fila, não ao primeiro.
    final arquivosNaOrdemEscolhida = arquivos.reversed.toList();

    final novos = <_ItemImagemLote>[];
    for (final arquivo in arquivosNaOrdemEscolhida) {
      final item = _ItemImagemLote(bytes: await arquivo.readAsBytes());
      // Vincula automaticamente na ordem da fila (quando veio de "Sem
      // imagem") — o usuário ainda pode trocar tocando no item depois.
      if (_filaProdutos.isNotEmpty) {
        item.produto = _filaProdutos.removeAt(0);
      }
      novos.add(item);
    }
    if (!mounted) return;
    setState(() => _itens.addAll(novos));
  }

  Future<void> _vincularProduto(_ItemImagemLote item) async {
    final produto = await showModalBottomSheet<Produto>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SeletorProdutoSheet(produtos: context.read<ProdutoProvider>().produtos),
    );
    if (produto == null || !mounted) return;
    setState(() => item.produto = produto);
  }

  Future<void> _recortarItem(_ItemImagemLote item) async {
    final resultado = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => CortarImagemScreen(imagem: item.bytes)),
    );
    if (resultado == null || !mounted) return;
    setState(() => item.bytes = resultado);
  }

  void _removerItem(_ItemImagemLote item) {
    setState(() => _itens.remove(item));
  }

  Future<void> _enviarTodos() async {
    final pendentes =
        _itens.where((i) => i.produto != null && i.status != _StatusItemLote.sucesso).toList();
    if (pendentes.isEmpty) return;

    setState(() => _enviando = true);
    _empresaId ??= await obterEmpresaIdAtual();
    if (_empresaId == null) {
      setState(() => _enviando = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Empresa não identificada.')),
      );
      return;
    }

    // Próxima ordem livre por produto: parte da contagem já salva no banco
    // e vai incrementando conforme processa mais de uma imagem do mesmo
    // produto dentro deste mesmo lote.
    final proximaOrdem = <String, int>{};

    for (final item in pendentes) {
      final produto = item.produto!;
      final produtoId = produto.id!;
      if (!mounted) return;
      setState(() => item.status = _StatusItemLote.enviando);
      try {
        if (!proximaOrdem.containsKey(produtoId)) {
          final existentes = await _repo.listar(produtoId);
          proximaOrdem[produtoId] = existentes.where((m) => m.isImagem).length + 1;
        }
        final ordem = proximaOrdem[produtoId]!;
        if (ordem > 6) {
          throw Exception('Produto já tem 6 imagens.');
        }

        final url = await uploadImagemProduto(
          bytes: item.bytes,
          empresaId: _empresaId!,
          produtoId: produtoId,
          nomeProduto: produto.nome,
          codigoBarras: produto.codigoBarras,
          fabricante: produto.fabricante,
          marca: produto.empresa,
          ordem: ordem,
        );
        await _repo.inserir(
          produtoId: produtoId,
          empresaId: _empresaId!,
          tipo: 'imagem',
          url: url,
          ordem: ordem,
        );
        proximaOrdem[produtoId] = ordem + 1;
        if (!mounted) return;
        setState(() => item.status = _StatusItemLote.sucesso);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          item.status = _StatusItemLote.erro;
          item.erro = e.toString();
        });
      }
    }

    if (!mounted) return;
    setState(() => _enviando = false);
    final sucesso = _itens.where((i) => i.status == _StatusItemLote.sucesso).length;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$sucesso de ${pendentes.length} imagens enviadas.')),
    );
    // Upload grava direto no banco (via repo), sem passar pelo
    // ProdutoProvider — sem isso, os produtos recém-cadastrados continuavam
    // aparecendo em "Sem imagem" até um refresh manual.
    if (sucesso > 0) context.read<ProdutoProvider>().carregarProdutos();
  }

  @override
  Widget build(BuildContext context) {
    final prontosParaEnviar =
        _itens.where((i) => i.produto != null && i.status != _StatusItemLote.sucesso).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Adicionar imagens em massa'),
        actions: [
          IconButton(
            tooltip: 'Escolher imagens',
            icon: const Icon(Icons.add_photo_alternate_outlined),
            onPressed: _enviando ? null : _adicionarImagens,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_filaProdutos.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Theme.of(context).colorScheme.primaryContainer,
              child: Text(
                'Faltam ${_filaProdutos.length} produto(s) sem foto vinculada — escolha mais imagens que elas serão vinculadas na ordem.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          Expanded(child: _buildLista()),
        ],
      ),
      bottomNavigationBar: _itens.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: FilledButton.icon(
                  onPressed: (_enviando || prontosParaEnviar == 0) ? null : _enviarTodos,
                  icon: _enviando
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_outlined),
                  label: Text(_enviando ? 'Enviando...' : 'Enviar $prontosParaEnviar imagem(ns)'),
                ),
              ),
            ),
    );
  }

  Widget _buildLista() {
    return _itens.isEmpty
          ? Center(
              child: TextButton.icon(
                onPressed: _adicionarImagens,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Escolher imagens'),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _itens.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = _itens[index];
                return _ItemLoteTile(
                  item: item,
                  onVincular: _enviando ? null : () => _vincularProduto(item),
                  onRecortar: _enviando ? null : () => _recortarItem(item),
                  onRemover: _enviando ? null : () => _removerItem(item),
                );
              },
            );
  }
}

class _ItemLoteTile extends StatelessWidget {
  const _ItemLoteTile({
    required this.item,
    required this.onVincular,
    required this.onRecortar,
    required this.onRemover,
  });

  final _ItemImagemLote item;
  final VoidCallback? onVincular;
  final VoidCallback? onRecortar;
  final VoidCallback? onRemover;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.memory(item.bytes, width: 56, height: 56, fit: BoxFit.cover),
      ),
      title: Text(
        item.produto?.nome ?? 'Toque para vincular a um produto',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: item.produto == null ? TextStyle(color: Theme.of(context).hintColor) : null,
      ),
      subtitle: item.status == _StatusItemLote.erro
          ? Text('Erro: ${item.erro}', style: const TextStyle(color: Colors.red))
          : item.produto != null
              ? Text('Cód. barras: ${item.produto!.codigoBarras}')
              : null,
      onTap: onVincular,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.status == _StatusItemLote.enviando)
            const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (item.status == _StatusItemLote.sucesso)
            const Icon(Icons.check_circle, color: Colors.green)
          else ...[
            IconButton(
              tooltip: 'Recortar',
              icon: const Icon(Icons.crop),
              onPressed: onRecortar,
            ),
            IconButton(
              tooltip: 'Remover',
              icon: const Icon(Icons.close),
              onPressed: onRemover,
            ),
          ],
        ],
      ),
    );
  }
}

class _SeletorProdutoSheet extends StatefulWidget {
  const _SeletorProdutoSheet({required this.produtos});

  final List<Produto> produtos;

  @override
  State<_SeletorProdutoSheet> createState() => _SeletorProdutoSheetState();
}

class _SeletorProdutoSheetState extends State<_SeletorProdutoSheet> {
  final _controller = TextEditingController();
  String _busca = '';

  @override
  Widget build(BuildContext context) {
    final filtrados = widget.produtos
        .where((p) => contemTodasPalavras(p.nome, _busca) || p.codigoBarras.toLowerCase().contains(normalizarBusca(_busca)))
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _controller,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Buscar por nome ou código de barras',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (v) => setState(() => _busca = v),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: filtrados.length,
                  itemBuilder: (context, index) {
                    final produto = filtrados[index];
                    return ListTile(
                      title: Text(produto.nome, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text('Cód. barras: ${produto.codigoBarras}'),
                      onTap: () => Navigator.of(context).pop(produto),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
