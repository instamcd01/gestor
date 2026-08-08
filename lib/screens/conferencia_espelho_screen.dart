import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../models/pedido_compra.dart';
import '../models/produto.dart';
import '../providers/auth_provider.dart';
import '../providers/pedido_compra_provider.dart';
import '../providers/produto_provider.dart';
import '../repositories/pedido_compra_repository.dart';
import '../widgets/busca_produto_sheet.dart';

class _ItemConferencia {
  final ItemPedidoCompra original;
  final TextEditingController confirmadoController;
  final TextEditingController observacaoController;
  String? produtoSubstitutoId;
  String? produtoSubstitutoNome;

  _ItemConferencia(this.original)
      : confirmadoController = TextEditingController(
          text: (original.quantidadeConfirmada ?? original.quantidadePedida).toString(),
        ),
        observacaoController = TextEditingController(text: original.observacao ?? '');

  bool get divergente {
    final confirmado = int.tryParse(confirmadoController.text) ?? original.quantidadePedida;
    return produtoSubstitutoId != null || confirmado != original.quantidadePedida;
  }

  ItemPedidoCompra paraSalvar() {
    return original.copyWith(
      quantidadeConfirmada: int.tryParse(confirmadoController.text) ?? original.quantidadePedida,
      quantidadeConfirmadaDefinir: true,
      produtoSubstitutoId: produtoSubstitutoId,
      produtoSubstitutoNome: produtoSubstitutoNome,
      produtoSubstitutoDefinir: true,
      observacao: observacaoController.text.trim().isEmpty ? null : observacaoController.text.trim(),
    );
  }

  void dispose() {
    confirmadoController.dispose();
    observacaoController.dispose();
  }
}

/// Conferência do espelho enviado pelo fornecedor: registra quantas fotos
/// forem necessárias (pedido grande costuma vir em mais de uma imagem) e a
/// quantidade que realmente foi confirmada por item — cobrindo não só
/// ruptura (veio menos) mas qualquer erro do fornecedor (veio mais, veio
/// produto errado, ou chegou algo que nem tinha sido pedido).
class ConferenciaEspelhoScreen extends StatefulWidget {
  final String pedidoId;

  const ConferenciaEspelhoScreen({super.key, required this.pedidoId});

  @override
  State<ConferenciaEspelhoScreen> createState() => _ConferenciaEspelhoScreenState();
}

class _ConferenciaEspelhoScreenState extends State<ConferenciaEspelhoScreen> {
  final _repository = PedidoCompraRepository();
  PedidoCompra? _pedido;
  List<_ItemConferencia> _itens = [];
  final List<AnexoEspelho> _anexos = [];
  bool _carregando = true;
  bool _enviandoAnexo = false;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    for (final item in _itens) {
      item.dispose();
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
        _itens = pedido.itens.map((i) => _ItemConferencia(i)).toList();
        _anexos
          ..clear()
          ..addAll(pedido.anexosEspelho);
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao carregar pedido: $e')));
    }
  }

  Future<void> _adicionarFotos() async {
    List<XFile> arquivos;
    try {
      arquivos = await ImagePicker().pickMultiImage();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao selecionar fotos: $e')));
      return;
    }
    if (arquivos.isEmpty) return;

    setState(() => _enviandoAnexo = true);
    try {
      final empresaId = context.read<AuthProvider>().empresaId!;
      for (final arquivo in arquivos) {
        final bytes = await arquivo.readAsBytes();
        final nomeArquivo = arquivo.name;
        final path = '$empresaId/${widget.pedidoId}/${DateTime.now().millisecondsSinceEpoch}_$nomeArquivo';
        await supabase.storage.from('pedidos-compra').uploadBinary(path, bytes);
        final url = supabase.storage.from('pedidos-compra').getPublicUrl(path);
        if (!mounted) return;
        setState(() {
          _anexos.add(AnexoEspelho(url: url, tipo: 'imagem', nomeArquivo: nomeArquivo, criadoEm: DateTime.now()));
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao enviar foto: $e')));
    } finally {
      if (mounted) setState(() => _enviandoAnexo = false);
    }
  }

  Future<void> _adicionarPdf() async {
    final resultado = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
    if (resultado == null || resultado.files.single.bytes == null || !mounted) return;

    setState(() => _enviandoAnexo = true);
    try {
      final empresaId = context.read<AuthProvider>().empresaId!;
      final arquivo = resultado.files.single;
      final path = '$empresaId/${widget.pedidoId}/${DateTime.now().millisecondsSinceEpoch}_${arquivo.name}';
      await supabase.storage.from('pedidos-compra').uploadBinary(
            path,
            arquivo.bytes!,
            fileOptions: const FileOptions(contentType: 'application/pdf'),
          );
      final url = supabase.storage.from('pedidos-compra').getPublicUrl(path);
      if (!mounted) return;
      setState(() {
        _anexos.add(AnexoEspelho(url: url, tipo: 'pdf', nomeArquivo: arquivo.name, criadoEm: DateTime.now()));
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao enviar PDF: $e')));
    } finally {
      if (mounted) setState(() => _enviandoAnexo = false);
    }
  }

  void _removerAnexo(int index) {
    setState(() => _anexos.removeAt(index));
  }

  Future<void> _marcarSubstituto(_ItemConferencia item) async {
    final produtos = context.read<ProdutoProvider>().produtos.where((p) => p.ativo && p.id != null).toList()
      ..sort((a, b) => a.nome.compareTo(b.nome));

    final produto = await showModalBottomSheet<Produto>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BuscaProdutoSheet(produtos: produtos),
    );
    if (produto == null) return;
    setState(() {
      item.produtoSubstitutoId = produto.id;
      item.produtoSubstitutoNome = produto.nome;
    });
  }

  Future<void> _adicionarItemNaoPedido() async {
    final produtos = context.read<ProdutoProvider>().produtos.where((p) => p.ativo && p.id != null).toList()
      ..sort((a, b) => a.nome.compareTo(b.nome));

    final produto = await showModalBottomSheet<Produto>(
      context: context,
      isScrollControlled: true,
      builder: (_) => BuscaProdutoSheet(produtos: produtos),
    );
    if (produto == null) return;

    setState(() {
      _itens.add(_ItemConferencia(ItemPedidoCompra(
        produtoId: produto.id!,
        produtoNome: produto.nome,
        quantidadePedida: 0,
        quantidadeConfirmada: 1,
        custoUnitario: produto.custo,
        origem: OrigemItemPedidoCompra.conferencia,
      ))
        ..confirmadoController.text = '1');
    });
  }

  Future<void> _salvarConferencia() async {
    final pedido = _pedido;
    if (pedido == null) return;

    setState(() => _salvando = true);
    try {
      final provider = context.read<PedidoCompraProvider>();
      final itensParaSalvar = _itens.map((i) => i.paraSalvar()).toList();
      await provider.substituirItens(pedido.id!, itensParaSalvar);
      await provider.confirmarConferencia(pedido.id!, anexos: _anexos);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar conferência: $e')));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Conferência do Espelho')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text('Anexos do espelho', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Envie quantas fotos ou PDFs forem necessários — um pedido grande costuma vir em mais de uma imagem.',
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _anexos.length; i++) _ChipAnexo(anexo: _anexos[i], onRemover: () => _removerAnexo(i)),
                    ActionChip(
                      avatar: _enviandoAnexo
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.add_photo_alternate_outlined, size: 18),
                      label: const Text('Fotos'),
                      onPressed: _enviandoAnexo ? null : _adicionarFotos,
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: const Text('PDF'),
                      onPressed: _enviandoAnexo ? null : _adicionarPdf,
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('Itens pedidos', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  'Confirme o que o fornecedor realmente vai mandar — pode ser diferente do pedido (a mais, a menos, ou produto trocado).',
                  style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                for (final item in _itens) _LinhaConferencia(item: item, onMarcarSubstituto: () => _marcarSubstituto(item)),
                TextButton.icon(
                  onPressed: _adicionarItemNaoPedido,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Registrar item que chegou sem ter sido pedido'),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _salvando ? null : _salvarConferencia,
                  icon: _salvando
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: Text(_salvando ? 'Salvando...' : 'Salvar conferência'),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                ),
              ],
            ),
    );
  }
}

class _ChipAnexo extends StatelessWidget {
  final AnexoEspelho anexo;
  final VoidCallback onRemover;

  const _ChipAnexo({required this.anexo, required this.onRemover});

  @override
  Widget build(BuildContext context) {
    return InputChip(
      avatar: Icon(anexo.tipo == 'pdf' ? Icons.picture_as_pdf_outlined : Icons.image_outlined, size: 18),
      label: Text(anexo.nomeArquivo, overflow: TextOverflow.ellipsis),
      onDeleted: onRemover,
    );
  }
}

class _LinhaConferencia extends StatefulWidget {
  final _ItemConferencia item;
  final VoidCallback onMarcarSubstituto;

  const _LinhaConferencia({required this.item, required this.onMarcarSubstituto});

  @override
  State<_LinhaConferencia> createState() => _LinhaConferenciaState();
}

class _LinhaConferenciaState extends State<_LinhaConferencia> {
  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final colorScheme = Theme.of(context).colorScheme;
    final naoFoiPedido = item.original.quantidadePedida == 0;
    // errorContainer/onErrorContainer em vez de Colors.orange.shade50 fixo —
    // esse fundo claro isolado ficava ilegível no tema escuro porque o
    // texto não tinha cor explícita (herdava a cor clara padrão do app).
    final corTexto = item.divergente ? colorScheme.onErrorContainer : null;

    return Card(
      color: item.divergente ? colorScheme.errorContainer : null,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.original.produtoNome,
                    style: TextStyle(fontWeight: FontWeight.w600, color: corTexto),
                  ),
                ),
                if (naoFoiPedido)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'não pedido',
                      style: TextStyle(fontSize: 10, color: colorScheme.onSecondaryContainer),
                    ),
                  ),
              ],
            ),
            if (!naoFoiPedido)
              Text(
                'Pedido: ${item.original.quantidadePedida}un',
                style: TextStyle(fontSize: 12, color: corTexto ?? colorScheme.onSurfaceVariant),
              ),
            const SizedBox(height: 6),
            Row(
              children: [
                SizedBox(
                  width: 140,
                  child: TextField(
                    controller: item.confirmadoController,
                    decoration: const InputDecoration(labelText: 'Confirmado', isDense: true),
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: item.produtoSubstitutoNome != null
                      ? Chip(
                          label: Text('Veio: ${item.produtoSubstitutoNome}', overflow: TextOverflow.ellipsis),
                          onDeleted: () => setState(() {
                            item.produtoSubstitutoId = null;
                            item.produtoSubstitutoNome = null;
                          }),
                        )
                      : TextButton(
                          onPressed: widget.onMarcarSubstituto,
                          child: const Text('Veio outro produto?'),
                        ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            TextField(
              controller: item.observacaoController,
              decoration: const InputDecoration(labelText: 'Observação (opcional)', isDense: true),
            ),
          ],
        ),
      ),
    );
  }
}

