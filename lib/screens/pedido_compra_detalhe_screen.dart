import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/pedido_compra.dart';
import '../providers/pedido_compra_provider.dart';
import '../repositories/pedido_compra_repository.dart';
import '../utils/telefone_utils.dart';
import 'conferencia_espelho_screen.dart';
import 'confirmar_recebimento_screen.dart';
import 'importar_nota_fiscal_screen.dart';

class PedidoCompraDetalheScreen extends StatefulWidget {
  final String pedidoId;

  const PedidoCompraDetalheScreen({super.key, required this.pedidoId});

  @override
  State<PedidoCompraDetalheScreen> createState() => _PedidoCompraDetalheScreenState();
}

class _PedidoCompraDetalheScreenState extends State<PedidoCompraDetalheScreen> {
  final _repository = PedidoCompraRepository();
  final _boundaryKey = GlobalKey();

  PedidoCompra? _pedido;
  bool _carregando = true;
  bool _salvandoItens = false;
  bool _compartilhando = false;

  // Edição de itens (só usada em rascunho) — controllers por item, mantidos
  // vivos entre rebuilds pela chave `item.id ?? index`.
  final Map<String, TextEditingController> _controllersQuantidade = {};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    for (final c in _controllersQuantidade.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    try {
      final pedido = await _repository.buscarPorId(widget.pedidoId);
      if (!mounted) return;
      setState(() {
        _pedido = pedido;
        _carregando = false;
        for (var i = 0; i < pedido.itens.length; i++) {
          final chave = pedido.itens[i].id ?? 'novo_$i';
          _controllersQuantidade[chave] ??= TextEditingController();
          _controllersQuantidade[chave]!.text = pedido.itens[i].quantidadePedida.toString();
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao carregar pedido: $e')));
    }
  }

  Future<void> _salvarItens() async {
    final pedido = _pedido;
    if (pedido == null) return;
    setState(() => _salvandoItens = true);
    try {
      final itensAtualizados = pedido.itens.asMap().entries.map((entry) {
        final chave = entry.value.id ?? 'novo_${entry.key}';
        final qtd = int.tryParse(_controllersQuantidade[chave]?.text ?? '') ?? entry.value.quantidadePedida;
        return entry.value.copyWith(quantidadePedida: qtd);
      }).toList();

      await context.read<PedidoCompraProvider>().substituirItens(pedido.id!, itensAtualizados);
      await _carregar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Itens atualizados')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar itens: $e')));
    } finally {
      if (mounted) setState(() => _salvandoItens = false);
    }
  }

  void _removerItem(int index) {
    final pedido = _pedido;
    if (pedido == null) return;
    setState(() {
      final novosItens = List<ItemPedidoCompra>.from(pedido.itens)..removeAt(index);
      _pedido = PedidoCompra(
        id: pedido.id,
        fornecedor: pedido.fornecedor,
        numeroSequencial: pedido.numeroSequencial,
        status: pedido.status,
        valorTotal: pedido.valorTotal,
        observacoes: pedido.observacoes,
        itens: novosItens,
      );
    });
  }

  /// Sem valor de propósito — quem informa o preço atual é o fornecedor,
  /// pra depois dar pra comparar com o que estava cadastrado. Preço só
  /// aparece na tela interna do pedido, nunca no que é enviado a ele.
  String _textoPedidoFormatado(PedidoCompra pedido) {
    final buffer = StringBuffer();
    buffer.writeln('*Pedido de compra${pedido.numeroSequencial != null ? ' #${pedido.numeroSequencial}' : ''}*');
    buffer.writeln('Fornecedor: ${pedido.fornecedor.nome}');
    buffer.writeln('');
    for (final item in pedido.itens) {
      buffer.writeln('• ${item.produtoNome} — ${item.quantidadePedida}un');
    }
    if (pedido.observacoes?.isNotEmpty == true) {
      buffer.writeln('');
      buffer.writeln('Obs: ${pedido.observacoes}');
    }
    return buffer.toString();
  }

  Future<void> _abrirWhatsApp() async {
    final pedido = _pedido;
    if (pedido == null) return;
    if (pedido.fornecedor.telefone.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este fornecedor não tem telefone cadastrado')),
      );
      return;
    }
    final texto = Uri.encodeComponent(_textoPedidoFormatado(pedido));
    final url = Uri.parse('${linkWhatsApp(pedido.fornecedor.telefone)}?text=$texto');
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível abrir o WhatsApp: $e')));
    }
  }

  Future<void> _compartilharImagem() async {
    setState(() => _compartilhando = true);
    try {
      final boundary = _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final imagem = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await imagem.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final nomeArquivo = 'pedido_compra_${_pedido?.numeroSequencial ?? DateTime.now().millisecondsSinceEpoch}.png';

      await Share.shareXFiles(
        [XFile.fromData(pngBytes, name: nomeArquivo, mimeType: 'image/png')],
        text: 'Pedido de compra — ${_pedido?.fornecedor.nome ?? ''}',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível gerar a imagem: $e')));
    } finally {
      if (mounted) setState(() => _compartilhando = false);
    }
  }

  Future<void> _marcarComoEnviado() async {
    final pedido = _pedido;
    if (pedido == null) return;
    try {
      await context.read<PedidoCompraProvider>().marcarComoEnviado(pedido.id!);
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao marcar como enviado: $e')));
    }
  }

  Future<void> _cancelar() async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar pedido'),
        content: const Text('Tem certeza que deseja cancelar este pedido de compra?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Voltar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Cancelar pedido')),
        ],
      ),
    );
    if (confirmou != true || _pedido == null) return;
    try {
      await context.read<PedidoCompraProvider>().cancelar(_pedido!.id!);
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao cancelar: $e')));
    }
  }

  Future<void> _irParaConferencia() async {
    final pedido = _pedido;
    if (pedido == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ConferenciaEspelhoScreen(pedidoId: pedido.id!)),
    );
    _carregar();
  }

  Future<void> _irParaConfirmarRecebimento() async {
    final pedido = _pedido;
    if (pedido == null) return;
    final recebeu = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ConfirmarRecebimentoScreen(pedido: pedido)),
    );
    if (recebeu == true) _carregar();
  }

  Future<void> _irParaImportarNfe() async {
    final pedido = _pedido;
    if (pedido == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ImportarNotaFiscalScreen(pedidoCompra: pedido)),
    );
    _carregar();
  }

  @override
  Widget build(BuildContext context) {
    final pedido = _pedido;
    return Scaffold(
      appBar: AppBar(
        title: Text(pedido != null ? 'Pedido #${pedido.numeroSequencial ?? '—'}' : 'Pedido de compra'),
      ),
      body: _carregando || pedido == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _carregar,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _CabecalhoPedido(pedido: pedido),
                  const SizedBox(height: 16),
                  Text('Itens', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (var i = 0; i < pedido.itens.length; i++)
                    _LinhaItemPedido(
                      item: pedido.itens[i],
                      editavel: pedido.status == StatusPedidoCompra.rascunho,
                      controller: _controllersQuantidade[pedido.itens[i].id ?? 'novo_$i']!,
                      onRemover: pedido.status == StatusPedidoCompra.rascunho ? () => _removerItem(i) : null,
                      onMudou: () => setState(() {}),
                    ),
                  if (pedido.status == StatusPedidoCompra.rascunho) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _salvandoItens ? null : _salvarItens,
                      icon: _salvandoItens
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save_outlined),
                      label: const Text('Salvar alterações nos itens'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (pedido.status == StatusPedidoCompra.rascunho) _SecaoEnvio(
                    onWhatsApp: _abrirWhatsApp,
                    onCompartilhar: _compartilharImagem,
                    onMarcarEnviado: _marcarComoEnviado,
                    compartilhando: _compartilhando,
                  ),
                  if (pedido.status == StatusPedidoCompra.enviado)
                    Card(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('Pedido enviado ao fornecedor.'),
                            const SizedBox(height: 4),
                            const Text('Quando o fornecedor mandar o espelho de confirmação, registre aqui.'),
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: _irParaConferencia,
                              icon: const Icon(Icons.fact_check_outlined),
                              label: const Text('Conferir espelho do fornecedor'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (pedido.status == StatusPedidoCompra.confirmado || pedido.status == StatusPedidoCompra.recebido)
                    _ResumoConferencia(pedido: pedido),
                  if (pedido.status == StatusPedidoCompra.confirmado) ...[
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _irParaImportarNfe,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Já tenho a NF-e — importar XML e confirmar recebimento'),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Use isso sempre que tiver a nota fiscal — reaproveita o mesmo fluxo de "Importar Nota Fiscal", com fornecedor/vínculo já preenchidos.',
                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _irParaConfirmarRecebimento,
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: const Text('Ainda não tenho a NF-e (registrar manualmente)'),
                    ),
                    Text(
                      'Só use se a mercadoria já chegou mas a nota ainda não. Quando a NF-e chegar, NÃO importe ela separadamente — isso duplicaria o estoque.',
                      style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.error),
                    ),
                  ],
                  if (pedido.status != StatusPedidoCompra.cancelado && pedido.status != StatusPedidoCompra.recebido) ...[
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _cancelar,
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: const Text('Cancelar pedido'),
                    ),
                  ],
                  // Widget invisível (fora da tela) só pra gerar a imagem compartilhável.
                  Offstage(
                    offstage: true,
                    child: RepaintBoundary(
                      key: _boundaryKey,
                      child: _CardPedidoParaImagem(pedido: pedido),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _CabecalhoPedido extends StatelessWidget {
  final PedidoCompra pedido;

  const _CabecalhoPedido({required this.pedido});

  /// Fundo+texto do badge de status — inverte a faixa de cor conforme o
  /// tema (claro: fundo claro/texto escuro; escuro: fundo escuro/texto
  /// claro). Fixar só `.shade100` como fundo (sem levar o tema em conta)
  /// deixava o badge ilegível no tema escuro: fundo claro isolado num
  /// card escuro, texto sem cor herdando a cor clara padrão do app.
  ({Color bg, Color fg}) _coresStatus(BuildContext context, StatusPedidoCompra status) {
    if (status == StatusPedidoCompra.rascunho) {
      final colorScheme = Theme.of(context).colorScheme;
      return (bg: colorScheme.surfaceContainerHighest, fg: colorScheme.onSurfaceVariant);
    }
    final MaterialColor cor = switch (status) {
      StatusPedidoCompra.enviado => Colors.blue,
      StatusPedidoCompra.confirmado => Colors.orange,
      StatusPedidoCompra.recebido => Colors.green,
      StatusPedidoCompra.cancelado => Colors.red,
      StatusPedidoCompra.rascunho => Colors.grey,
    };
    final escuro = Theme.of(context).brightness == Brightness.dark;
    return escuro ? (bg: cor.shade900, fg: cor.shade100) : (bg: cor.shade100, fg: cor.shade900);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(pedido.fornecedor.nome, style: Theme.of(context).textTheme.titleLarge)),
                Builder(builder: (context) {
                  final cores = _coresStatus(context, pedido.status);
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: cores.bg, borderRadius: BorderRadius.circular(16)),
                    child: Text(
                      pedido.status.label,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: cores.fg),
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 8),
            Text('Total: R\$ ${pedido.valorTotal.toStringAsFixed(2)}'),
            if (pedido.fornecedor.valorMinimoPedido != null)
              Text(
                pedido.valorTotal >= pedido.fornecedor.valorMinimoPedido!
                    ? 'Mínimo de R\$ ${pedido.fornecedor.valorMinimoPedido!.toStringAsFixed(2)} atingido'
                    : 'Abaixo do mínimo de R\$ ${pedido.fornecedor.valorMinimoPedido!.toStringAsFixed(2)}',
                style: TextStyle(
                  color: pedido.valorTotal >= pedido.fornecedor.valorMinimoPedido!
                      ? Colors.green.shade700
                      : Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            if (pedido.fornecedor.prazoEntregaDias != null)
              Text('Prazo de entrega: ${pedido.fornecedor.prazoEntregaDias} dias', style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _LinhaItemPedido extends StatelessWidget {
  final ItemPedidoCompra item;
  final bool editavel;
  final TextEditingController controller;
  final VoidCallback? onRemover;
  final VoidCallback onMudou;

  const _LinhaItemPedido({
    required this.item,
    required this.editavel,
    required this.controller,
    required this.onRemover,
    required this.onMudou,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.produtoNome),
                  Text('R\$${item.custoUnitario.toStringAsFixed(2)}/un', style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            SizedBox(
              width: 60,
              child: editavel
                  ? TextField(
                      controller: controller,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(isDense: true),
                      onChanged: (_) => onMudou(),
                    )
                  : Text('${item.quantidadePedida}un', textAlign: TextAlign.center),
            ),
            SizedBox(
              width: 70,
              child: Text('R\$${item.subtotalPedido.toStringAsFixed(2)}', textAlign: TextAlign.right),
            ),
            if (onRemover != null)
              IconButton(icon: const Icon(Icons.close, size: 18), onPressed: onRemover),
          ],
        ),
      ),
    );
  }
}

class _SecaoEnvio extends StatelessWidget {
  final VoidCallback onWhatsApp;
  final VoidCallback onCompartilhar;
  final VoidCallback onMarcarEnviado;
  final bool compartilhando;

  const _SecaoEnvio({
    required this.onWhatsApp,
    required this.onCompartilhar,
    required this.onMarcarEnviado,
    required this.compartilhando,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Enviar pedido', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'O WhatsApp só abre com o texto pronto — pra anexar a imagem/PDF, use "Compartilhar imagem" e escolha o WhatsApp na tela de compartilhamento do celular.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onWhatsApp,
                    icon: const Icon(Icons.chat_outlined),
                    label: const Text('WhatsApp (texto)'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: compartilhando ? null : onCompartilhar,
                    icon: compartilhando
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.image_outlined),
                    label: const Text('Compartilhar imagem'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: onMarcarEnviado,
              icon: const Icon(Icons.check),
              label: const Text('Marcar como enviado'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResumoConferencia extends StatelessWidget {
  final PedidoCompra pedido;

  const _ResumoConferencia({required this.pedido});

  @override
  Widget build(BuildContext context) {
    final divergentes = pedido.itens.where((i) => i.divergente).toList();
    final colorScheme = Theme.of(context).colorScheme;
    // Card de aviso: usa errorContainer/onErrorContainer (adapta sozinho
    // pro tema claro/escuro) em vez de Colors.orange.shade50 fixo — esse
    // fundo claro fixo com texto sem cor explícita ficava ilegível no
    // tema escuro (herdava a cor de texto clara padrão do app).
    final corTexto = divergentes.isEmpty ? null : colorScheme.onErrorContainer;
    return Card(
      color: divergentes.isEmpty ? null : colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Conferência do espelho', style: Theme.of(context).textTheme.titleSmall?.copyWith(color: corTexto)),
            const SizedBox(height: 8),
            if (divergentes.isEmpty)
              const Text('Tudo bateu com o que foi pedido.')
            else ...[
              Text(
                '${divergentes.length} item(ns) com divergência:',
                style: TextStyle(fontWeight: FontWeight.bold, color: corTexto),
              ),
              for (final item in divergentes)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    item.produtoSubstitutoId != null
                        ? '• ${item.produtoNome}: veio "${item.produtoSubstitutoNome}" no lugar'
                        : '• ${item.produtoNome}: pedido ${item.quantidadePedida}un, confirmado ${item.quantidadeConfirmada}un',
                    style: TextStyle(color: corTexto),
                  ),
                ),
            ],
            if (pedido.valorTotalConfirmado != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Total confirmado: R\$ ${pedido.valorTotalConfirmado!.toStringAsFixed(2)}',
                  style: TextStyle(color: corTexto),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Card compacto usado só pra virar imagem compartilhável (offstage) —
/// separado da lista editável de itens pra não carregar campos de edição
/// na imagem enviada ao fornecedor.
class _CardPedidoParaImagem extends StatelessWidget {
  final PedidoCompra pedido;

  const _CardPedidoParaImagem({required this.pedido});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 380,
      padding: const EdgeInsets.all(20),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Pedido de compra${pedido.numeroSequencial != null ? ' #${pedido.numeroSequencial}' : ''}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
          ),
          Text('Fornecedor: ${pedido.fornecedor.nome}', style: const TextStyle(color: Colors.black87)),
          const Divider(color: Colors.black26),
          for (final item in pedido.itens)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(child: Text(item.produtoNome, style: const TextStyle(color: Colors.black))),
                  Text('${item.quantidadePedida}un', style: const TextStyle(color: Colors.black)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
