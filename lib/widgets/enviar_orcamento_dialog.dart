import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../providers/branding_provider.dart';
import '../providers/carrinho_provider.dart';
import 'orcamento_imagem_widget.dart';

const _urlEnvio = 'https://n8n.lukz.com.br/webhook/orcamento-whatsapp-87d65e3578a20292a4748bf6060a1193';

/// Linhas do orçamento a partir do carrinho. Preço cortado só quando o preço de
/// catálogo é mesmo maior que o cobrado (promoção ou kit).
List<ItemOrcamentoImagem> itensDoOrcamento(List<ItemCarrinho> itens, Map<String, Uint8List?> fotos) => [
      for (final item in itens)
        ItemOrcamentoImagem(
          nome: item.produto.nome,
          quantidade: item.quantidade,
          precoUnitario: item.precoUnitario,
          precoCheio: item.produto.preco > item.precoUnitario ? item.produto.preco : null,
          foto: fotos[item.produto.id ?? ''],
        ),
    ];

/// Texto pra quem está vendendo, a partir da recusa do envio.
String textoMotivoOrcamento(String? motivo, {String? erro}) => switch (motivo) {
      'fora_da_janela' =>
        'Este cliente não falou com a loja nas últimas 24 horas, e o WhatsApp só libera imagem nesse período. Salve a imagem e mande pelo celular.',
      'sem_whatsapp' => 'O WhatsApp da loja não está conectado. Salve a imagem e mande pelo celular.',
      'meta' => 'O WhatsApp recusou o envio${erro == null ? '' : ': $erro'}',
      'cliente_invalido' => 'Não encontrei este cliente na loja.',
      _ => 'Não foi possível enviar agora. Tente de novo em instantes.',
    };

/// Mostra a imagem como o cliente vai receber e envia só depois da confirmação.
Future<void> mostrarEnviarOrcamento(BuildContext context, CarrinhoProvider carrinho) {
  return showDialog<void>(context: context, builder: (_) => _EnviarOrcamentoDialog(carrinho: carrinho));
}

class _EnviarOrcamentoDialog extends StatefulWidget {
  final CarrinhoProvider carrinho;
  const _EnviarOrcamentoDialog({required this.carrinho});

  @override
  State<_EnviarOrcamentoDialog> createState() => _EnviarOrcamentoDialogState();
}

class _EnviarOrcamentoDialogState extends State<_EnviarOrcamentoDialog> {
  final _chaveImagem = GlobalKey();
  final _fotos = <String, Uint8List?>{};
  Uint8List? _logo;
  bool _carregando = true;
  bool _enviando = false;
  bool _salvando = false;
  Map<String, dynamic>? _consulta;
  String? _erro;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _preparar());
  }

  Future<Uint8List?> _baixar(String url) async {
    if (url.isEmpty) return null;
    try {
      final r = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 8));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) return null;
      // Testa a decodificação aqui: foto corrompida quebraria a imagem inteira.
      if (mounted) await precacheImage(MemoryImage(r.bodyBytes), context, onError: (_, __) {});
      return r.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  Future<void> _preparar() async {
    final branding = context.read<BrandingProvider>();
    final logos = branding.ativosDeMarcaPorTipo('logo_completa');
    final cliente = widget.carrinho.clienteSelecionado;

    await Future.wait([
      for (final item in widget.carrinho.itens)
        _baixar(item.produto.imagemUrlExibicao).then((b) => _fotos[item.produto.id ?? ''] = b),
      if (logos.isNotEmpty) _baixar(logos.first.url).then((b) => _logo = b),
      if (cliente != null)
        Supabase.instance.client.rpc('whatsapp_orcamento_preparar', params: {
          'p_cliente_id': cliente.idCliente,
          'p_imagem_url': null,
        }).then((r) => _consulta = Map<String, dynamic>.from(r as Map)).catchError((Object e) {
          debugPrint('Erro ao consultar envio do orçamento: $e');
          _consulta = {'ok': false, 'motivo': 'erro'};
          return _consulta!;
        }),
    ]);
    if (mounted) setState(() => _carregando = false);
  }

  Future<Uint8List> _gerarPng() async {
    final caixa = _chaveImagem.currentContext!.findRenderObject() as RenderRepaintBoundary;
    final imagem = await caixa.toImage(pixelRatio: 2);
    final dados = await imagem.toByteData(format: ui.ImageByteFormat.png);
    return dados!.buffer.asUint8List();
  }

  Future<void> _enviar() async {
    final mensageiro = ScaffoldMessenger.of(context);
    final navegador = Navigator.of(context);
    final nome = widget.carrinho.clienteSelecionado?.nome ?? 'o cliente';
    final sessao = Supabase.instance.client.auth.currentSession;
    if (sessao == null) {
      setState(() => _erro = 'Sessão expirada. Entre de novo.');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      final png = await _gerarPng();
      final caminho = '${_consulta!['empresa_id']}/${const Uuid().v4()}.png';
      final storage = Supabase.instance.client.storage.from('orcamentos');
      await storage.uploadBinary(caminho, png, fileOptions: const FileOptions(contentType: 'image/png'));

      final resposta = await http
          .post(
            Uri.parse(_urlEnvio),
            headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer ${sessao.accessToken}'},
            body: jsonEncode({
              'cliente_id': widget.carrinho.clienteSelecionado!.idCliente,
              'imagem_url': storage.getPublicUrl(caminho),
            }),
          )
          .timeout(const Duration(seconds: 30));
      final corpo = resposta.statusCode == 200 ? jsonDecode(resposta.body) as Map<String, dynamic> : const <String, dynamic>{};
      if (corpo['ok'] == true) {
        navegador.pop();
        mensageiro.showSnackBar(SnackBar(content: Text('Orçamento enviado pra $nome.')));
        return;
      }
      setState(() => _erro = textoMotivoOrcamento(corpo['motivo']?.toString(), erro: corpo['erro']?.toString()));
    } catch (e) {
      debugPrint('Erro ao enviar orçamento: $e');
      if (mounted) setState(() => _erro = textoMotivoOrcamento(null));
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _salvar() async {
    setState(() => _salvando = true);
    try {
      final png = await _gerarPng();
      const nome = 'orcamento.png';
      // Desktop: o painel de compartilhar do sistema abre sem destino pro Gestor.
      if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        await FilePicker.platform.saveFile(
          dialogTitle: 'Salvar imagem do orçamento',
          fileName: nome,
          type: FileType.custom,
          allowedExtensions: const ['png'],
          bytes: png,
        );
      } else {
        await Share.shareXFiles([XFile.fromData(png, name: nome, mimeType: 'image/png')]);
      }
    } catch (e) {
      debugPrint('Erro ao salvar orçamento: $e');
      if (mounted) setState(() => _erro = 'Não foi possível salvar a imagem.');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final carrinho = widget.carrinho;
    final zona = carrinho.zonaEntregaSelecionada;
    final podeEnviar = _consulta?['ok'] == true;
    final aviso = _erro ?? (!_carregando && !podeEnviar ? textoMotivoOrcamento(_consulta?['motivo']?.toString()) : null);
    final ocupado = _enviando || _salvando;

    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Orçamento para ${carrinho.clienteSelecionado?.nome ?? 'o cliente'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    icon: const Icon(Icons.close),
                    onPressed: ocupado ? null : () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: _carregando
                  ? const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.topCenter,
                        child: RepaintBoundary(
                          key: _chaveImagem,
                          child: OrcamentoImagemWidget(
                            nomeLoja: context.read<BrandingProvider>().nomeEmpresa,
                            corPrimaria: context.read<BrandingProvider>().corPrimaria,
                            logo: _logo,
                            data: DateTime.now(),
                            itens: itensDoOrcamento(carrinho.itens, _fotos),
                            desconto: carrinho.desconto,
                            retirada: zona == null,
                            entrega: carrinho.valorEntregaCalculado,
                            entregaCheia: zona?.valor,
                            minimoFreteGratis: zona?.valorMinimoFreteGratis,
                          ),
                        ),
                      ),
                    ),
            ),
            if (aviso != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Text(aviso, style: TextStyle(fontSize: 13, color: colorScheme.error)),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _carregando || ocupado ? null : _salvar,
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                      child: Text(_salvando ? 'Salvando...' : 'Salvar imagem', maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _carregando || ocupado || !podeEnviar ? null : _enviar,
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                      child: Text(_enviando ? 'Enviando...' : 'Enviar no WhatsApp', maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
