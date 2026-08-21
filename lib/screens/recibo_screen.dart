import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../config/supabase_config.dart';
import '../models/venda.dart';
import '../providers/auth_provider.dart';
import '../providers/branding_provider.dart';
import '../widgets/recibo_venda_widget.dart';

/// Mostra o recibo da venda pronto pra visualização e, se o vendedor
/// quiser, envio (WhatsApp, e-mail, etc — via share sheet do sistema).
/// O recibo é gerado como imagem (PNG), não PDF: abre direto em qualquer
/// app de conversa sem precisar de leitor de PDF.
class ReciboScreen extends StatefulWidget {
  final Venda venda;

  const ReciboScreen({super.key, required this.venda});

  @override
  State<ReciboScreen> createState() => _ReciboScreenState();
}

class _ReciboScreenState extends State<ReciboScreen> {
  final _boundaryKey = GlobalKey();

  bool _carregando = true;
  bool _compartilhando = false;

  String _nomeLoja = '';
  String _razaoSocial = '';
  String _cnpj = '';
  bool _mostrarCnpj = true;
  String _mensagemRodape = '';
  Uint8List? _logoBytes;
  Color _corPrimaria = const Color(0xFFF5821F);
  Color _corSecundaria = const Color(0xFFF5821F);

  @override
  void initState() {
    super.initState();
    _carregarConfig();
  }

  Future<void> _carregarConfig() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    // Cores/logo já carregadas no app inteiro pelo BrandingProvider — usa a
    // mesma identidade visual da loja em vez de buscar de novo.
    final branding = context.read<BrandingProvider>();
    _corPrimaria = branding.corPrimaria;
    _corSecundaria = branding.corSecundaria;

    if (empresaId == null) {
      if (mounted) setState(() => _carregando = false);
      return;
    }

    try {
      final data = await supabase
          .from('empresas')
          .select('nome, razao_social, cnpj, recibo_mensagem, recibo_mostrar_logo, recibo_mostrar_cnpj')
          .eq('id', empresaId)
          .single();

      _nomeLoja = data['nome']?.toString() ?? '';
      _razaoSocial = data['razao_social']?.toString() ?? '';
      _cnpj = data['cnpj']?.toString() ?? '';
      _mostrarCnpj = data['recibo_mostrar_cnpj'] as bool? ?? true;
      _mensagemRodape = data['recibo_mensagem']?.toString() ?? '';

      final mostrarLogo = data['recibo_mostrar_logo'] as bool? ?? true;
      // Recibo impresso não é uma "posição" configurável do Kit de Marca (não
      // faz sentido nele ser um texto/mascote) — usa direto a logo completa,
      // se tiver alguma cadastrada.
      final logosCompletas = branding.ativosDeMarcaPorTipo('logo_completa');
      final logoUrl = logosCompletas.isNotEmpty ? logosCompletas.first.url : '';
      if (mostrarLogo && logoUrl.isNotEmpty) {
        try {
          final resposta = await http.get(Uri.parse(logoUrl));
          if (resposta.statusCode == 200) _logoBytes = resposta.bodyBytes;
        } catch (e) {
          debugPrint('Erro ao baixar logo pro recibo: $e');
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar configuração do recibo: $e');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _compartilharRecibo() async {
    setState(() => _compartilhando = true);
    try {
      final boundary = _boundaryKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final imagem = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await imagem.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();

      final nomeArquivo = 'recibo_${widget.venda.idVenda ?? DateTime.now().millisecondsSinceEpoch}.png';

      await Share.shareXFiles(
        [XFile.fromData(pngBytes, name: nomeArquivo, mimeType: 'image/png')],
        text: 'Recibo da venda de ${widget.venda.cliente.nome}',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível gerar o recibo: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _compartilhando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recibo')),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: RepaintBoundary(
                  key: _boundaryKey,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 16, offset: const Offset(0, 6)),
                      ],
                    ),
                    child: ReciboVendaWidget(
                      venda: widget.venda,
                      nomeLoja: _nomeLoja,
                      razaoSocial: _razaoSocial,
                      cnpj: _cnpj,
                      mostrarCnpj: _mostrarCnpj,
                      mensagemRodape: _mensagemRodape,
                      logoBytes: _logoBytes,
                      corPrimaria: _corPrimaria,
                      corSecundaria: _corSecundaria,
                    ),
                  ),
                ),
              ),
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: ElevatedButton.icon(
            onPressed: _carregando || _compartilhando ? null : _compartilharRecibo,
            icon: _compartilhando
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.share),
            label: Text(_compartilhando ? 'Gerando...' : 'Compartilhar Recibo'),
            style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
          ),
        ),
      ),
    );
  }
}
