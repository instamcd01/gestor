import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/banner_home.dart';
import '../providers/auth_provider.dart';
import '../providers/banner_home_provider.dart';
import '../repositories/banner_home_repository.dart';
import '../widgets/estado_erro_lista.dart';
import '../widgets/form_section.dart';
import 'cortar_imagem_screen.dart';

/// Proporção do recorte: 21:9, a mesma que o carrossel do site usa em
/// desktop (banner-carousel.tsx) — recortar nessa proporção faz o banner
/// caber em desktop sem cortar NADA. Não existe proporção que sirva pras
/// duas telas ao mesmo tempo (desktop usa 21:9, celular usa 16:9, ver
/// comentário no `banner-carousel.tsx`) — a saída é cortar pro maior dos
/// dois (21:9) e manter o conteúdo importante dentro de uma "área de
/// segurança" central de 16:9, que é exatamente o que aparece inteiro no
/// celular (o site sempre recorta a partir do centro). Testado com uma
/// imagem 2:1 (1774×887) antes disso: cortava lateral no celular (16:9 é
/// mais estreito que 2:1) E cortava topo/base no desktop (21:9 é mais
/// largo que 2:1) — a proporção antiga de meio-termo cortava dos dois
/// jeitos ao mesmo tempo em vez de eliminar o corte de algum dos dois.
const _proporcaoBanner = 21 / 9;

/// Largura da "área de segurança" central (proporção 16:9 na mesma altura
/// do canvas) — o que aparece 100% visível no celular. Resto do banner
/// (as faixas nas duas bordas) só some em telas estreitas.
const _larguraMinimaRecomendada = 1600;

/// Largura total recomendada do canvas (21:9 na mesma altura da área de
/// segurança, 1600×900 → 2100×900) — o que aparece 100% visível em
/// desktop.
const _larguraTotalRecomendada = 2100;

/// Banner rotativo da home do site — Configurações > Catálogo Online.
/// Lojista escolhe fotos ou vídeos, reordena por arrastar, ativa/desativa
/// sem excluir. Consumido pelo site via `catalogo_banners_publico`.
class BannersLojaScreen extends StatefulWidget {
  const BannersLojaScreen({super.key});

  @override
  State<BannersLojaScreen> createState() => _BannersLojaScreenState();
}

class _BannersLojaScreenState extends State<BannersLojaScreen> {
  @override
  void initState() {
    super.initState();
    Provider.of<BannerHomeProvider>(context, listen: false).carregar();
  }

  Future<void> _adicionarFoto() async {
    XFile? arquivo;
    try {
      arquivo = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 95);
    } catch (e) {
      _mostrarErro('Erro ao selecionar imagem: $e');
      return;
    }
    if (arquivo == null || !mounted) return;

    final bytesOriginais = await arquivo.readAsBytes();
    if (!mounted) return;
    final bytesRecortados = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(builder: (_) => CortarImagemScreen(imagem: bytesOriginais, aspectRatio: _proporcaoBanner)),
    );
    if (bytesRecortados == null || !mounted) return; // cancelou o recorte

    final largura = img.decodeImage(bytesRecortados)?.width ?? 0;
    if (largura > 0 && largura < _larguraTotalRecomendada) {
      final continuar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Imagem em baixa resolução'),
          content: Text(
            'Essa imagem tem ${largura}px de largura depois do recorte. Pra boa qualidade em telas grandes, '
            'o ideal é pelo menos ${_larguraTotalRecomendada}px (proporção 21:9, ex: $_larguraTotalRecomendada×900). '
            'Pode continuar mesmo assim, mas pode ficar borrada em desktop.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Escolher outra')),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Continuar assim mesmo')),
          ],
        ),
      );
      if (continuar != true || !mounted) return;
    }

    await _enviarEAbrirFormulario(bytes: bytesRecortados, tipo: 'imagem');
  }

  Future<void> _adicionarVideo() async {
    XFile? arquivo;
    try {
      arquivo = await ImagePicker().pickVideo(source: ImageSource.gallery);
    } catch (e) {
      _mostrarErro('Erro ao selecionar vídeo: $e');
      return;
    }
    if (arquivo == null || !mounted) return;
    await _enviarEAbrirFormulario(
      bytes: await arquivo.readAsBytes(),
      tipo: 'video',
      nomeArquivoOriginal: arquivo.name,
    );
  }

  Future<void> _enviarEAbrirFormulario({
    required Uint8List bytes,
    required String tipo,
    String? nomeArquivoOriginal,
  }) async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final repository = BannerHomeRepository();
      final url = tipo == 'video'
          ? await repository.uploadVideo(
              bytes: bytes,
              empresaId: empresaId,
              nomeArquivoOriginal: nomeArquivoOriginal ?? 'video.mp4',
            )
          : await repository.uploadImagem(bytes: bytes, empresaId: empresaId);

      if (!mounted) return;
      Navigator.pop(context); // fecha o spinner

      // Novo banner entra no fim da fila — sem isso, todo banner novo
      // nascia com ordem=0 (o valor padrão do model) e ficava empatado
      // com os que já existiam, uma ordem arbitrária no carrossel.
      final proximaOrdem = context.read<BannerHomeProvider>().banners.length;

      final salvou = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => _BannerFormScreen(bannerNovo: BannerHome(tipo: tipo, url: url, ordem: proximaOrdem)),
        ),
      );
      if (salvou == true && mounted) {
        context.read<BannerHomeProvider>().carregar();
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      _mostrarErro('Erro ao enviar arquivo: $e');
    }
  }

  Future<void> _editar(BannerHome banner) async {
    final salvou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => _BannerFormScreen(bannerExistente: banner)),
    );
    if (salvou == true && mounted) {
      context.read<BannerHomeProvider>().carregar();
    }
  }

  Future<void> _excluir(BannerHome banner) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover banner'),
        content: const Text('Tem certeza que deseja remover esse banner do carrossel da home?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remover')),
        ],
      ),
    );
    if (confirmou != true || banner.id == null) return;
    try {
      await context.read<BannerHomeProvider>().excluir(banner.id!);
    } catch (e) {
      _mostrarErro('Erro ao remover: $e');
    }
  }

  void _mostrarErro(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  void _abrirMenuAdicionar() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('Foto'),
              onTap: () {
                Navigator.pop(ctx);
                _adicionarFoto();
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Vídeo'),
              onTap: () {
                Navigator.pop(ctx);
                _adicionarVideo();
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<BannerHomeProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Banners da Home'),
        actions: [
          IconButton(icon: const Icon(Icons.add), tooltip: 'Adicionar banner', onPressed: _abrirMenuAdicionar),
        ],
      ),
      body: provider.carregando
          ? const Center(child: CircularProgressIndicator())
          : provider.erro != null
              ? EstadoErroLista(mensagem: provider.erro!, onTentarNovamente: provider.carregar)
              : Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Aparecem em ordem no carrossel da home do site. Arraste pra reordenar. Sem nenhum banner '
                        'ativo, o site mostra o banner padrão. Fotos: o site corta em proporções diferentes no '
                        'celular (16:9) e no computador (21:9) — pra imagem nenhuma ficar cortada de verdade, envie '
                        'no tamanho total $_larguraTotalRecomendada×${_larguraTotalRecomendada * 9 ~/ 21}px '
                        '(proporção 21:9, o que aparece inteiro no computador) e mantenha texto/produto/logo dentro '
                        'de uma faixa central de ${_larguraMinimaRecomendada}px de largura na mesma altura '
                        '(proporção 16:9) — é essa faixa central que aparece inteira no celular; as bordas '
                        '(≈${(_larguraTotalRecomendada - _larguraMinimaRecomendada) ~/ 2}px de cada lado) só aparecem '
                        'em telas largas. Você recorta pro tamanho total (21:9) na hora de adicionar. Vídeos: grave '
                        'na mesma proporção (21:9) se possível — o site nunca corta o vídeo, então uma proporção '
                        'muito diferente (ex: vertical de celular) aparece com barras desfocadas nas bordas. Vídeo '
                        'sempre começa mudo (regra do navegador), com botão pra ativar o som.',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                    if (provider.banners.isEmpty)
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.image_outlined, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              const SizedBox(height: 16),
                              const Text('Nenhum banner cadastrado ainda'),
                              const SizedBox(height: 4),
                              Text(
                                'Toque no "+" pra adicionar uma foto ou vídeo.',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ReorderableListView(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          onReorder: (oldIndex, newIndex) => context.read<BannerHomeProvider>().reordenar(oldIndex, newIndex),
                          children: [
                            for (final banner in provider.banners)
                              _CardBanner(
                                key: ValueKey(banner.id),
                                banner: banner,
                                onEditar: () => _editar(banner),
                                onExcluir: () => _excluir(banner),
                                onAtivoMudou: (ativo) => context.read<BannerHomeProvider>().atualizar(
                                      BannerHome(
                                        id: banner.id,
                                        tipo: banner.tipo,
                                        url: banner.url,
                                        urlThumbnail: banner.urlThumbnail,
                                        titulo: banner.titulo,
                                        linkDestino: banner.linkDestino,
                                        ordem: banner.ordem,
                                        ativo: ativo,
                                      ),
                                    ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }
}

class _CardBanner extends StatelessWidget {
  final BannerHome banner;
  final VoidCallback onEditar;
  final VoidCallback onExcluir;
  final ValueChanged<bool> onAtivoMudou;

  const _CardBanner({
    super.key,
    required this.banner,
    required this.onEditar,
    required this.onExcluir,
    required this.onAtivoMudou,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onEditar,
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 56,
            height: 56,
            child: banner.isVideo
                ? Container(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.videocam_outlined),
                  )
                : Image.network(
                    banner.url,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
                  ),
          ),
        ),
        title: Text(banner.titulo?.isNotEmpty == true ? banner.titulo! : (banner.isVideo ? 'Vídeo' : 'Foto')),
        subtitle: Text(banner.linkDestino?.isNotEmpty == true ? 'Link: ${banner.linkDestino}' : 'Sem link'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(value: banner.ativo, onChanged: onAtivoMudou),
            IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: onExcluir),
            const Icon(Icons.drag_handle),
          ],
        ),
      ),
    );
  }
}

class _BannerFormScreen extends StatefulWidget {
  final BannerHome? bannerExistente;
  final BannerHome? bannerNovo;

  const _BannerFormScreen({this.bannerExistente, this.bannerNovo});

  @override
  State<_BannerFormScreen> createState() => _BannerFormScreenState();
}

class _BannerFormScreenState extends State<_BannerFormScreen> {
  late final TextEditingController _tituloController;
  late final TextEditingController _linkController;
  late String _url;
  bool _ativo = true;
  bool _salvando = false;
  bool _recortando = false;

  BannerHome get _base => widget.bannerExistente ?? widget.bannerNovo!;
  bool get _editando => widget.bannerExistente != null;

  @override
  void initState() {
    super.initState();
    _tituloController = TextEditingController(text: _base.titulo ?? '');
    _linkController = TextEditingController(text: _base.linkDestino ?? '');
    _ativo = _base.ativo;
    _url = _base.url;
  }

  /// Baixa a imagem atual, deixa recortar de novo e reenvia — usado tanto
  /// pra ajustar o enquadramento de um banner já publicado quanto pros 3
  /// primeiros banners cadastrados antes dessa tela ter recorte.
  Future<void> _recortarNovamente() async {
    setState(() => _recortando = true);
    try {
      final resposta = await http.get(Uri.parse(_url));
      if (resposta.statusCode != 200) throw Exception('Não foi possível baixar a imagem atual');
      if (!mounted) return;

      final recortado = await Navigator.push<Uint8List>(
        context,
        MaterialPageRoute(
          builder: (_) => CortarImagemScreen(imagem: resposta.bodyBytes, aspectRatio: _proporcaoBanner),
        ),
      );
      if (recortado == null || !mounted) return;

      final empresaId = context.read<AuthProvider>().empresaId;
      if (empresaId == null) return;
      final novaUrl = await BannerHomeRepository().uploadImagem(bytes: recortado, empresaId: empresaId);
      if (!mounted) return;
      setState(() => _url = novaUrl);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao recortar: $e')));
    } finally {
      if (mounted) setState(() => _recortando = false);
    }
  }

  @override
  void dispose() {
    _tituloController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    final banner = BannerHome(
      id: _base.id,
      tipo: _base.tipo,
      url: _url,
      urlThumbnail: _base.urlThumbnail,
      titulo: _tituloController.text.trim().isEmpty ? null : _tituloController.text.trim(),
      linkDestino: _linkController.text.trim().isEmpty ? null : _linkController.text.trim(),
      ordem: _base.ordem,
      ativo: _ativo,
    );

    try {
      final provider = context.read<BannerHomeProvider>();
      if (_editando) {
        await provider.atualizar(banner);
      } else {
        await provider.adicionar(banner);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar banner: $e')));
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar Banner' : 'Novo Banner')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: _proporcaoBanner,
                child: _base.isVideo
                    ? Container(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: const Center(child: Icon(Icons.videocam_outlined, size: 40)),
                      )
                    : Image.network(_url, fit: BoxFit.cover),
              ),
            ),
            if (!_base.isVideo) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _recortando ? null : _recortarNovamente,
                icon: _recortando
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.crop),
                label: Text(_recortando ? 'Recortando...' : 'Recortar novamente'),
              ),
              const SizedBox(height: 4),
              Text(
                'Dimensão ideal: pelo menos $_larguraTotalRecomendada×${_larguraTotalRecomendada * 9 ~/ 21}px '
                '(proporção 21:9) pra ficar nítido em telas grandes, com o conteúdo importante dentro de uma '
                'faixa central de ${_larguraMinimaRecomendada}px de largura (16:9) — é essa faixa que aparece '
                'inteira no celular.',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 16),
            FormSection(
              titulo: 'Detalhes',
              children: [
                TextFormField(
                  controller: _tituloController,
                  decoration: const InputDecoration(
                    labelText: 'Título sobreposto (Opcional)',
                    helperText: 'Texto exibido em cima do banner, ex: "Frete grátis essa semana"',
                    helperMaxLines: 2,
                  ),
                ),
                TextFormField(
                  controller: _linkController,
                  decoration: const InputDecoration(
                    labelText: 'Link ao clicar (Opcional)',
                    helperText: 'Ex: #produtos, ou o caminho de um produto específico. Vazio = não clicável.',
                    helperMaxLines: 2,
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ativo'),
                  subtitle: const Text('Desative pra tirar do carrossel sem excluir'),
                  value: _ativo,
                  onChanged: (v) => setState(() => _ativo = v),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _salvando ? null : _salvar,
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
              child: _salvando
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}
