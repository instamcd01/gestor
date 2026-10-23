import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/conteudo_guia.dart';
import '../repositories/conteudo_guia_repository.dart';
import '../widgets/estado_erro_lista.dart';

/// Aba "Dicas" de `CatalogoOnlineHubScreen` — guias educativos do site
/// (`/dicas`). Os rascunhos chegam sozinhos: a Edge Function
/// `guias-rascunho` lê o Instagram da loja a cada 15 min e transforma Reel
/// educativo em rascunho (e junta a "parte 2" no mesmo). Aqui o dono revisa,
/// corrige o texto e publica — nada vai pro site sem esse toque.
class DicasSiteScreen extends StatefulWidget {
  const DicasSiteScreen({super.key});

  @override
  State<DicasSiteScreen> createState() => _DicasSiteScreenState();
}

class _DicasSiteScreenState extends State<DicasSiteScreen> {
  final _repo = ConteudoGuiaRepository();
  List<ConteudoGuia>? _guias;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final guias = await _repo.listar();
      if (!mounted) return;
      setState(() {
        _guias = guias;
        _erro = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _erro = 'Não foi possível carregar as dicas: $e');
    }
  }

  Future<void> _abrir(ConteudoGuia guia) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => DicaDetalheScreen(guia: guia)));
    _carregar();
  }

  @override
  Widget build(BuildContext context) {
    if (_erro != null) return EstadoErroLista(mensagem: _erro!, onTentarNovamente: _carregar);
    final guias = _guias;
    if (guias == null) return const Center(child: CircularProgressIndicator());

    final rascunhos = guias.where((g) => g.rascunho).toList();
    final publicados = guias.where((g) => !g.rascunho).toList();

    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Cada Reel educativo que a loja posta vira um rascunho de página no site, com o vídeo, um texto '
            'explicando e perguntas relacionadas. Confira o texto e publique: é isso que traz cliente pelo Google.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          _Secao(titulo: 'Esperando aprovação', vazio: 'Nenhum rascunho agora.', guias: rascunhos, onTap: _abrir),
          const SizedBox(height: 16),
          _Secao(titulo: 'No site', vazio: 'Nenhuma dica publicada ainda.', guias: publicados, onTap: _abrir),
        ],
      ),
    );
  }
}

class _Secao extends StatelessWidget {
  final String titulo;
  final String vazio;
  final List<ConteudoGuia> guias;
  final void Function(ConteudoGuia) onTap;

  const _Secao({required this.titulo, required this.vazio, required this.guias, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$titulo (${guias.length})', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (guias.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(vazio, style: Theme.of(context).textTheme.bodySmall),
          ),
        for (final guia in guias)
          Card(
            child: ListTile(
              leading: guia.capaUrl == null
                  ? const Icon(Icons.article_outlined)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: CachedNetworkImage(imageUrl: guia.capaUrl!, width: 36, height: 64, fit: BoxFit.cover),
                    ),
              title: Text(guia.titulo),
              subtitle: Text(
                [
                  if (guia.serie != null) guia.serie!,
                  '${guia.videos.length} vídeo${guia.videos.length == 1 ? '' : 's'}',
                  DateFormat('dd/MM').format((guia.publicadoEm ?? guia.criadoEm).toLocal()),
                ].join(' · '),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => onTap(guia),
            ),
          ),
      ],
    );
  }
}

/// Revisão de uma dica: mostra o texto como vai pro site, deixa corrigir
/// qualquer trecho (toque no trecho) e publicar / tirar do site.
class DicaDetalheScreen extends StatefulWidget {
  final ConteudoGuia guia;

  const DicaDetalheScreen({super.key, required this.guia});

  @override
  State<DicaDetalheScreen> createState() => _DicaDetalheScreenState();
}

class _DicaDetalheScreenState extends State<DicaDetalheScreen> {
  final _repo = ConteudoGuiaRepository();
  late String _titulo = widget.guia.titulo;
  late String _resumo = widget.guia.resumo;
  late String? _respostaCurta = widget.guia.respostaCurta;
  late final List<Map<String, dynamic>> _corpo = widget.guia.corpo.map(Map<String, dynamic>.from).toList();
  late final List<Map<String, dynamic>> _perguntas = widget.guia.perguntas.map(Map<String, dynamic>.from).toList();
  late bool _rascunho = widget.guia.rascunho;
  bool _salvando = false;

  Future<String?> _editarTexto(String rotulo, String atual, {String? ajuda}) {
    final controle = TextEditingController(text: atual);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(rotulo),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controle,
            autofocus: true,
            maxLines: null,
            minLines: 2,
            decoration: InputDecoration(helperText: ajuda, helperMaxLines: 2),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, controle.text.trim()), child: const Text('Salvar')),
        ],
      ),
    );
  }

  Future<void> _salvar(Map<String, dynamic> campos, {String? aviso}) async {
    setState(() => _salvando = true);
    try {
      await _repo.atualizar(widget.guia.id, campos);
      if (!mounted) return;
      if (aviso != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(aviso)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível salvar: $e')));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _editarTitulo() async {
    final novo = await _editarTexto('Título', _titulo, ajuda: 'A pergunta que a pessoa digitaria no Google.');
    if (novo == null || novo.isEmpty) return;
    setState(() => _titulo = novo);
    await _salvar({'titulo': novo});
  }

  Future<void> _editarResumo() async {
    final novo = await _editarTexto('Resumo (aparece no Google)', _resumo, ajuda: 'Até 155 letras.');
    if (novo == null || novo.isEmpty) return;
    setState(() => _resumo = novo);
    await _salvar({'resumo': novo});
  }

  Future<void> _editarRespostaCurta() async {
    final novo = await _editarTexto('Resposta rápida', _respostaCurta ?? '');
    if (novo == null) return;
    setState(() => _respostaCurta = novo.isEmpty ? null : novo);
    await _salvar({'resposta_curta': _respostaCurta});
  }

  Future<void> _editarBloco(int i) async {
    final bloco = _corpo[i];
    final ehLista = bloco['texto'] == null;
    final atual = ehLista ? (bloco['itens'] as List).join('\n') : bloco['texto'] as String;
    final novo = await _editarTexto(
      ehLista ? 'Itens (um por linha)' : 'Trecho',
      atual,
      ajuda: ehLista ? 'Cada linha vira um item. Linha vazia é ignorada.' : null,
    );
    if (novo == null || novo.isEmpty) return;
    setState(() {
      _corpo[i] = ehLista
          ? {...bloco, 'itens': novo.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList()}
          : {...bloco, 'texto': novo};
    });
    await _salvar({'corpo': _corpo});
  }

  Future<void> _editarPergunta(int i) async {
    final p = _perguntas[i];
    final pergunta = await _editarTexto('Pergunta', p['pergunta'] as String);
    if (pergunta == null || pergunta.isEmpty || !mounted) return;
    final resposta = await _editarTexto('Resposta', p['resposta'] as String);
    if (resposta == null || resposta.isEmpty) return;
    setState(() => _perguntas[i] = {'pergunta': pergunta, 'resposta': resposta});
    await _salvar({'perguntas': _perguntas});
  }

  Future<void> _alternarPublicacao() async {
    final publicar = _rascunho;
    setState(() => _rascunho = !publicar);
    await _salvar(
      {'status': publicar ? 'publicado' : 'rascunho'},
      aviso: publicar ? 'Publicada! Aparece no site em até 1 minuto.' : 'Tirada do site.',
    );
  }

  Future<void> _excluir() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descartar rascunho?'),
        content: const Text('O vídeo continua no Instagram; só a página do site é descartada.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Descartar')),
        ],
      ),
    );
    if (confirmar != true) return;
    try {
      await _repo.excluir(widget.guia.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível descartar: $e')));
    }
  }

  Widget _editavel({required Widget child, required VoidCallback onTap}) => InkWell(
        onTap: _salvando ? null : onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: child),
      );

  Widget _bloco(int i) {
    final b = _corpo[i];
    final tema = Theme.of(context).textTheme;
    final Widget conteudo;
    switch (b['tipo']) {
      case 'h2':
        conteudo = Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(b['texto'] as String, style: tema.titleMedium),
        );
      case 'lista':
      case 'passos':
        final itens = (b['itens'] as List).cast<String>();
        conteudo = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var n = 0; n < itens.length; n++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('${b['tipo'] == 'passos' ? '${n + 1}.' : '•'} ${itens[n]}'),
              ),
          ],
        );
      default:
        conteudo = Text(b['texto'] as String? ?? '');
    }
    return _editavel(onTap: () => _editarBloco(i), child: conteudo);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_rascunho ? 'Rascunho' : 'No site'),
        actions: [
          if (_rascunho)
            IconButton(
              tooltip: 'Descartar rascunho',
              icon: const Icon(Icons.delete_outline),
              onPressed: _salvando ? null : _excluir,
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: ElevatedButton.icon(
            onPressed: _salvando ? null : _alternarPublicacao,
            icon: Icon(_rascunho ? Icons.publish : Icons.visibility_off_outlined),
            label: Text(_rascunho ? 'Publicar no site' : 'Tirar do site'),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Toque em qualquer trecho pra corrigir.', style: tema.bodySmall),
          const SizedBox(height: 12),
          _editavel(onTap: _editarTitulo, child: Text(_titulo, style: tema.headlineSmall)),
          _editavel(
            onTap: _editarResumo,
            child: Text('No Google: $_resumo', style: tema.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _editavel(
                onTap: _editarRespostaCurta,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('RESPOSTA RÁPIDA', style: tema.labelSmall),
                    const SizedBox(height: 4),
                    Text(_respostaCurta ?? '(sem resposta rápida — toque pra escrever)'),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          for (final video in widget.guia.videos)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.play_circle_outline),
              title: Text(video['titulo'] as String? ?? 'Vídeo'),
              subtitle: const Text('Toque pra assistir'),
              onTap: () => launchUrl(Uri.parse(video['url'] as String), mode: LaunchMode.externalApplication),
            ),
          const Divider(),
          for (var i = 0; i < _corpo.length; i++) _bloco(i),
          if (_perguntas.isNotEmpty) ...[
            const Divider(),
            Text('Perguntas relacionadas', style: tema.titleMedium),
            for (var i = 0; i < _perguntas.length; i++)
              _editavel(
                onTap: () => _editarPergunta(i),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_perguntas[i]['pergunta'] as String, style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text(_perguntas[i]['resposta'] as String),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
