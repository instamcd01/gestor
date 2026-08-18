import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

import '../models/produto_midia.dart';
import '../providers/produto_provider.dart';
import '../repositories/produto_midia_repository.dart';
import '../utils/empresa_atual.dart';
import '../utils/upload_imagem_produto.dart';
import 'cortar_imagem_screen.dart';

const _maxImagens = 6;

/// Tela dedicada de galeria de um produto: até 6 imagens (com recorte,
/// reordenação por arrastar e exclusão) + vídeos por link (com player
/// embutido quando é um link do YouTube reconhecido).
class GerenciarMidiasProdutoScreen extends StatefulWidget {
  final String produtoId;

  const GerenciarMidiasProdutoScreen({super.key, required this.produtoId});

  @override
  State<GerenciarMidiasProdutoScreen> createState() => _GerenciarMidiasProdutoScreenState();
}

class _GerenciarMidiasProdutoScreenState extends State<GerenciarMidiasProdutoScreen> {
  final _repo = ProdutoMidiaRepository();
  final Map<String, YoutubePlayerController> _playerControllers = {};

  List<ProdutoMidia> _imagens = [];
  List<ProdutoMidia> _videos = [];
  bool _carregando = true;
  bool _processando = false;
  String? _empresaId;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    for (final controller in _playerControllers.values) {
      controller.close();
    }
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      _empresaId ??= await obterEmpresaIdAtual();
      final midias = await _repo.listar(widget.produtoId);
      if (!mounted) return;
      setState(() {
        _imagens = midias.where((m) => m.isImagem).toList()
          ..sort((a, b) => a.ordem.compareTo(b.ordem));
        _videos = midias.where((m) => m.isVideo).toList()
          ..sort((a, b) => a.ordem.compareTo(b.ordem));
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao carregar mídias: $e')),
      );
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _adicionarImagem() async {
    if (_imagens.length >= _maxImagens) return;

    final picker = ImagePicker();
    XFile? arquivo;
    try {
      arquivo = await picker.pickImage(source: ImageSource.gallery);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao selecionar imagem: $e')),
      );
      return;
    }
    if (arquivo == null) return;

    final bytesOriginais = await arquivo.readAsBytes();
    if (!mounted) return;

    final bytesRecortados = await Navigator.of(context).push<Uint8List>(
      MaterialPageRoute(builder: (_) => CortarImagemScreen(imagem: bytesOriginais)),
    );
    if (bytesRecortados == null || !mounted) return;

    if (_empresaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Empresa não identificada.')),
      );
      return;
    }

    final produto = context.read<ProdutoProvider>().getProdutoPorId(widget.produtoId);
    if (produto == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Produto não encontrado.')),
      );
      return;
    }

    setState(() => _processando = true);
    try {
      final url = await uploadImagemProduto(
        bytes: bytesRecortados,
        empresaId: _empresaId!,
        produtoId: widget.produtoId,
        nomeProduto: produto.nome,
        codigoBarras: produto.codigoBarras,
        fabricante: produto.fabricante,
        marca: produto.empresa,
        ordem: _imagens.length + 1,
      );
      await _repo.inserir(
        produtoId: widget.produtoId,
        empresaId: _empresaId!,
        tipo: 'imagem',
        url: url,
        ordem: _imagens.length + 1,
      );
      await _carregar();
      _atualizarCacheDeProdutos();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao enviar imagem: $e')),
      );
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _recortarImagemExistente(ProdutoMidia midia) async {
    setState(() => _processando = true);
    try {
      final resposta = await http.get(Uri.parse(midia.url));
      if (resposta.statusCode != 200) {
        throw Exception('Não foi possível carregar a imagem atual.');
      }
      if (!mounted) return;

      final bytesRecortados = await Navigator.of(context).push<Uint8List>(
        MaterialPageRoute(builder: (_) => CortarImagemScreen(imagem: resposta.bodyBytes)),
      );
      if (bytesRecortados == null || !mounted) return;

      if (_empresaId == null) {
        throw Exception('Empresa não identificada.');
      }
      final produto = context.read<ProdutoProvider>().getProdutoPorId(widget.produtoId);
      if (produto == null) {
        throw Exception('Produto não encontrado.');
      }

      final novaUrl = await uploadImagemProduto(
        bytes: bytesRecortados,
        empresaId: _empresaId!,
        produtoId: widget.produtoId,
        nomeProduto: produto.nome,
        codigoBarras: produto.codigoBarras,
        fabricante: produto.fabricante,
        marca: produto.empresa,
        ordem: midia.ordem,
      );
      await _repo.atualizarUrl(midia.id, novaUrl);
      await _carregar();
      _atualizarCacheDeProdutos();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao recortar imagem: $e')),
      );
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _removerImagem(ProdutoMidia midia) async {
    setState(() => _processando = true);
    try {
      await _repo.remover(midia.id);
      final restantes = _imagens.where((m) => m.id != midia.id).map((m) => m.id).toList();
      if (restantes.isNotEmpty) {
        await _repo.reordenar(restantes);
      }
      await _carregar();
      _atualizarCacheDeProdutos();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao remover imagem: $e')),
      );
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  // Adicionar/recortar/remover imagem grava direto no banco (via trigger
  // que sincroniza produto_midias -> produtos.imagem_url), sem passar pelo
  // ProdutoProvider — sem isso, a lista em memória usada pela aba "Sem
  // imagem" e por outras telas fica desatualizada até um refresh manual
  // (achado real: produto some da lista ao ganhar foto errada, mas não
  // volta pra lista depois de excluir a foto, porque o cache continua
  // achando que ele já tem imagem). Dispara em segundo plano, sem esperar —
  // esta tela não depende do resultado.
  void _atualizarCacheDeProdutos() {
    if (!mounted) return;
    context.read<ProdutoProvider>().carregarProdutos();
  }

  Future<void> _reordenarImagens(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final novaLista = List<ProdutoMidia>.from(_imagens);
    final item = novaLista.removeAt(oldIndex);
    novaLista.insert(newIndex, item);
    setState(() => _imagens = novaLista);
    try {
      await _repo.reordenar(novaLista.map((m) => m.id).toList());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao reordenar: $e')),
      );
      await _carregar();
    }
  }

  Future<void> _adicionarVideo() async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      // Sem autofocus + sem fechar tocando fora: com o teclado aberto (via
      // autofocus) e o diálogo fechando por barrier-dismiss no mesmo frame,
      // bate num bug conhecido do framework do Flutter (assert
      // `_dependents.isEmpty` ao desativar o Overlay/IME) — só os botões
      // fecham o diálogo agora.
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Adicionar vídeo'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Link do vídeo',
            hintText: 'https://www.youtube.com/watch?v=...',
          ),
          keyboardType: TextInputType.url,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
    if (!mounted || url == null || url.isEmpty || _empresaId == null) return;

    setState(() => _processando = true);
    try {
      await _repo.inserir(
        produtoId: widget.produtoId,
        empresaId: _empresaId!,
        tipo: 'video',
        url: url,
        ordem: _videos.length + 1,
      );
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao adicionar vídeo: $e')),
      );
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _removerVideo(ProdutoMidia midia) async {
    _playerControllers.remove(midia.id)?.close();
    setState(() => _processando = true);
    try {
      await _repo.remover(midia.id);
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao remover vídeo: $e')),
      );
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  // youtube_player_flutter só dá suporte real a Android/iOS/macOS/Web (é
  // baseado em WebView) — em Windows/Linux não existe implementação e o
  // player quebraria em runtime, então caímos pro link externo nesses casos.
  bool get _suportaPlayerEmbutido {
    if (kIsWeb) return true;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  void _abrirImagemEmTelaCheia(String url) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
        body: Center(
          child: InteractiveViewer(
            child: Image.network(
              url,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image, color: Colors.white, size: 64),
            ),
          ),
        ),
      ),
    ));
  }

  Widget _buildImagemTile(ColorScheme colorScheme, ProdutoMidia midia) {
    return Padding(
      key: ValueKey(midia.id),
      padding: const EdgeInsets.only(right: 8),
      child: Stack(
        children: [
          GestureDetector(
            onTap: () => _abrirImagemEmTelaCheia(midia.url),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                midia.url,
                width: 110,
                height: 110,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  width: 110,
                  height: 110,
                  color: colorScheme.surfaceContainerHighest,
                  child: Icon(Icons.image, color: colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: Row(
              children: [
                _miniIconButton(Icons.crop, 'Recortar', () => _recortarImagemExistente(midia)),
                const SizedBox(width: 2),
                _miniIconButton(Icons.delete_outline, 'Remover', () => _removerImagem(midia)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniIconButton(IconData icon, String tooltip, VoidCallback onPressed) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, size: 16, color: Colors.white),
        padding: const EdgeInsets.all(4),
        constraints: const BoxConstraints(),
        onPressed: _processando ? null : onPressed,
      ),
    );
  }

  Widget _buildVideoTile(ProdutoMidia midia) {
    final videoId = YoutubePlayerController.convertUrlToId(midia.url);
    final embutivel = videoId != null && _suportaPlayerEmbutido;

    Widget conteudo;
    if (embutivel) {
      final controller = _playerControllers.putIfAbsent(
        midia.id,
        () => YoutubePlayerController.fromVideoId(videoId: videoId, autoPlay: false),
      );
      conteudo = YoutubePlayer(controller: controller);
    } else {
      conteudo = ListTile(
        leading: const Icon(Icons.ondemand_video),
        title: Text(midia.url, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          videoId == null
              ? 'Link não reconhecido como YouTube — abra externamente'
              : 'Pré-visualização não disponível nesta plataforma',
        ),
        trailing: IconButton(
          icon: const Icon(Icons.open_in_new),
          tooltip: 'Abrir vídeo',
          onPressed: () => launchUrl(Uri.parse(midia.url), mode: LaunchMode.externalApplication),
        ),
      );
    }

    return Card(
      key: ValueKey(midia.id),
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          conteudo,
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Remover'),
              onPressed: _processando ? null : () => _removerVideo(midia),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Imagens e vídeos'),
        actions: [
          if (_processando)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Imagens (${_imagens.length}/$_maxImagens)',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Adicionar'),
                      onPressed:
                          _imagens.length >= _maxImagens || _processando ? null : _adicionarImagem,
                    ),
                  ],
                ),
                const Text(
                  'Segure e arraste pra reordenar. A primeira é a capa do produto.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                if (_imagens.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'Nenhuma imagem cadastrada ainda.',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  )
                else
                  SizedBox(
                    height: 110,
                    child: ReorderableListView(
                      scrollDirection: Axis.horizontal,
                      onReorder: _reordenarImagens,
                      children: [for (final midia in _imagens) _buildImagemTile(colorScheme, midia)],
                    ),
                  ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Vídeos', style: Theme.of(context).textTheme.titleMedium),
                    TextButton.icon(
                      icon: const Icon(Icons.video_call_outlined),
                      label: const Text('Adicionar'),
                      onPressed: _processando ? null : _adicionarVideo,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_videos.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'Nenhum vídeo cadastrado ainda.',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  )
                else
                  for (final midia in _videos) _buildVideoTile(midia),
              ],
            ),
    );
  }
}
