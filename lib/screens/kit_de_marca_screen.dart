import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../models/marca_ativo.dart';
import '../providers/branding_provider.dart';
import '../widgets/aviso_banner.dart';
import '../widgets/form_section.dart';

const _tiposUnicos = ['logo_completa', 'logo_slogan', 'nome_loja_imagem'];
const _posicoes = ['site_header', 'site_sidebar', 'app_inicio', 'app_drawer', 'app_sidebar', 'app_login'];

/// Kit de marca da empresa — galeria de imagens (mascote com variações,
/// logo completa, logo com slogan, nome da loja em imagem) + onde cada uma
/// aparece (cabeçalho/sidebar do site, menu/sidebar do app). Só o dono vê
/// esse menu (gated em `configuracoes_screen.dart`), diferente de
/// "Aparência e Marca" (cor/tema), que dono e gerente editam.
class KitDeMarcaScreen extends StatefulWidget {
  const KitDeMarcaScreen({super.key});

  @override
  State<KitDeMarcaScreen> createState() => _KitDeMarcaScreenState();
}

class _KitDeMarcaScreenState extends State<KitDeMarcaScreen> {
  bool _enviando = false;

  Future<Uint8List?> _escolherImagem() async {
    try {
      final arquivo = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 100);
      if (arquivo == null) return null;
      return await arquivo.readAsBytes();
    } catch (e) {
      _mostrarErro('Erro ao selecionar imagem: $e');
      return null;
    }
  }

  Future<void> _enviarTipoUnico(String tipo) async {
    final bytes = await _escolherImagem();
    if (bytes == null || !mounted) return;

    setState(() => _enviando = true);
    try {
      await context.read<BrandingProvider>().enviarAtivoDeMarca(bytes: bytes, tipo: tipo);
    } catch (e) {
      _mostrarErro('Erro ao enviar: $e');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _removerAtivo(MarcaAtivo ativo) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover imagem'),
        content: const Text('Qualquer posição que esteja usando essa imagem volta a mostrar o nome da loja.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remover')),
        ],
      ),
    );
    if (confirmou != true || ativo.id == null || !mounted) return;
    try {
      await context.read<BrandingProvider>().excluirAtivoDeMarca(ativo.id!);
    } catch (e) {
      _mostrarErro('Erro ao remover: $e');
    }
  }

  Future<void> _adicionarMascote() async {
    final bytes = await _escolherImagem();
    if (bytes == null || !mounted) return;

    final rotulo = await _pedirRotulo();
    if (!mounted) return;

    setState(() => _enviando = true);
    try {
      await context.read<BrandingProvider>().enviarAtivoDeMarca(bytes: bytes, tipo: 'mascote', rotulo: rotulo);
    } catch (e) {
      _mostrarErro('Erro ao enviar: $e');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<String?> _pedirRotulo({String? inicial}) async {
    final controller = TextEditingController(text: inicial ?? '');
    final resultado = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nome dessa variação'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Rótulo (Opcional)',
            hintText: 'Ex: Sentado, Apontando, Comemorando',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return (resultado == null || resultado.isEmpty) ? null : resultado;
  }

  Future<void> _renomearMascote(MarcaAtivo ativo) async {
    final rotulo = await _pedirRotulo(inicial: ativo.rotulo);
    if (rotulo == null || ativo.id == null || !mounted) return;
    try {
      await context.read<BrandingProvider>().atualizarRotuloDeMarca(ativo.id!, rotulo);
    } catch (e) {
      _mostrarErro('Erro ao renomear: $e');
    }
  }

  Future<void> _escolherParaPosicao(String posicao) async {
    final branding = context.read<BrandingProvider>();
    final resultado = await showModalBottomSheet<_SelecaoAtivo>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _SeletorAtivoSheet(ativos: branding.ativosDeMarca),
    );
    if (resultado == null || !mounted) return;
    try {
      await branding.definirPosicaoDeMarca(
        posicao: posicao,
        modo: resultado.modo,
        ativoId: resultado.ativoId,
      );
    } catch (e) {
      _mostrarErro('Erro ao salvar: $e');
    }
  }

  void _mostrarErro(String mensagem) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  @override
  Widget build(BuildContext context) {
    final branding = context.watch<BrandingProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Kit de Marca')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Envie as imagens da sua marca e escolha qual aparece em cada lugar do site e do app.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 20),

          FormSection(
            titulo: 'Imagens',
            children: [
              for (final tipo in _tiposUnicos)
                _LinhaAtivoUnico(
                  tipo: tipo,
                  ativo: branding.ativosDeMarcaPorTipo(tipo).isEmpty ? null : branding.ativosDeMarcaPorTipo(tipo).first,
                  enviando: _enviando,
                  onEnviar: () => _enviarTipoUnico(tipo),
                  onRemover: (a) => _removerAtivo(a),
                ),
            ],
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(child: Text('Mascote', style: Theme.of(context).textTheme.titleMedium)),
              TextButton.icon(
                onPressed: _enviando ? null : _adicionarMascote,
                icon: const Icon(Icons.add),
                label: const Text('Adicionar'),
              ),
            ],
          ),
          Text(
            'Várias poses/variações — escolha qual usar em cada posição abaixo.',
            style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          _GaleriaMascotes(
            ativos: branding.ativosDeMarcaPorTipo('mascote'),
            onExcluir: _removerAtivo,
            onRenomear: _renomearMascote,
          ),
          const SizedBox(height: 24),

          Text('Onde aparece', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const AvisoBanner(
            tipo: TipoAviso.alerta,
            texto: 'A tela de login é única pra todo o sistema (ainda não dá pra saber qual loja é antes '
                'de entrar) — por enquanto ela mostra a mesma imagem pra qualquer empresa que configurar essa '
                'posição. Não é um problema hoje, mas não escala se mais de uma loja usar esse recurso ao mesmo tempo.',
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  for (var i = 0; i < _posicoes.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    _LinhaPosicao(
                      posicao: _posicoes[i],
                      urlResolvida: branding.urlParaPosicao(_posicoes[i]),
                      onEscolher: () => _escolherParaPosicao(_posicoes[i]),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinhaAtivoUnico extends StatelessWidget {
  final String tipo;
  final MarcaAtivo? ativo;
  final bool enviando;
  final VoidCallback onEnviar;
  final ValueChanged<MarcaAtivo> onRemover;

  const _LinhaAtivoUnico({
    required this.tipo,
    required this.ativo,
    required this.enviando,
    required this.onEnviar,
    required this.onRemover,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _Miniatura(url: ativo?.url),
      title: Text(rotulosTipoMarcaAtivo[tipo] ?? tipo),
      subtitle: Text(ativo == null ? 'Não enviada' : 'Enviada'),
      trailing: Wrap(
        spacing: 4,
        children: [
          if (ativo != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remover',
              onPressed: enviando ? null : () => onRemover(ativo!),
            ),
          IconButton(
            icon: const Icon(Icons.upload_outlined),
            tooltip: ativo == null ? 'Enviar' : 'Trocar',
            onPressed: enviando ? null : onEnviar,
          ),
        ],
      ),
    );
  }
}

class _GaleriaMascotes extends StatelessWidget {
  final List<MarcaAtivo> ativos;
  final ValueChanged<MarcaAtivo> onExcluir;
  final ValueChanged<MarcaAtivo> onRenomear;

  const _GaleriaMascotes({required this.ativos, required this.onExcluir, required this.onRenomear});

  @override
  Widget build(BuildContext context) {
    if (ativos.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Nenhum mascote enviado ainda',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: ativos.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 0.85,
      ),
      itemBuilder: (context, index) {
        final ativo = ativos[index];
        return GestureDetector(
          onTap: () => onRenomear(ativo),
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: _Miniatura(url: ativo.url, grande: true)),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () => onExcluir(ativo),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                ativo.rotulo?.isNotEmpty == true ? ativo.rotulo! : 'Sem nome',
                style: const TextStyle(fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LinhaPosicao extends StatelessWidget {
  final String posicao;
  final String? urlResolvida;
  final VoidCallback onEscolher;

  const _LinhaPosicao({
    required this.posicao,
    required this.urlResolvida,
    required this.onEscolher,
  });

  @override
  Widget build(BuildContext context) {
    final mostraTexto = urlResolvida == null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: mostraTexto
          ? CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Icon(Icons.text_fields, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
            )
          : _Miniatura(url: urlResolvida),
      title: Text(rotulosPosicao[posicao] ?? posicao),
      subtitle: Text(mostraTexto ? 'Nome da loja (texto)' : 'Imagem'),
      trailing: TextButton(onPressed: onEscolher, child: const Text('Alterar')),
      onTap: onEscolher,
    );
  }
}

class _Miniatura extends StatelessWidget {
  final String? url;
  final bool grande;

  const _Miniatura({required this.url, this.grande = false});

  @override
  Widget build(BuildContext context) {
    final tamanho = grande ? null : 44.0;
    return Container(
      width: tamanho,
      height: tamanho,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: url == null
          ? Icon(Icons.image_outlined, size: grande ? 28 : 18, color: Theme.of(context).colorScheme.onSurfaceVariant)
          : ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Image.network(
                  url!,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined),
                ),
              ),
            ),
    );
  }
}

class _SelecaoAtivo {
  final String modo;
  final String? ativoId;
  const _SelecaoAtivo({required this.modo, this.ativoId});
}

class _SeletorAtivoSheet extends StatelessWidget {
  final List<MarcaAtivo> ativos;

  const _SeletorAtivoSheet({required this.ativos});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Escolher o que aparece', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.text_fields),
              title: const Text('Nome da loja (texto)'),
              onTap: () => Navigator.pop(context, const _SelecaoAtivo(modo: 'texto')),
            ),
            if (ativos.isNotEmpty) const Divider(),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: ativos.length,
                itemBuilder: (context, index) {
                  final ativo = ativos[index];
                  final rotuloTipo = rotulosTipoMarcaAtivo[ativo.tipo] ?? ativo.tipo;
                  final titulo = ativo.tipo == 'mascote' && ativo.rotulo?.isNotEmpty == true
                      ? 'Mascote: ${ativo.rotulo}'
                      : rotuloTipo;
                  return ListTile(
                    leading: _Miniatura(url: ativo.url),
                    title: Text(titulo),
                    onTap: () => Navigator.pop(context, _SelecaoAtivo(modo: 'imagem', ativoId: ativo.id)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
