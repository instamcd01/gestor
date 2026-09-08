import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

/// Tela de recorte reutilizada tanto ao adicionar uma imagem nova quanto ao
/// re-recortar uma já cadastrada (nesse segundo caso, os bytes já vêm
/// baixados da URL atual). Retorna os bytes recortados via `Navigator.pop`,
/// ou null se o usuário cancelar.
class CortarImagemScreen extends StatefulWidget {
  final Uint8List imagem;

  /// Quando informado, trava o recorte nessa proporção (ex: 2.0 = 2:1) em
  /// vez de deixar livre — usado pra banner, onde o carrossel do site
  /// sempre corta pra uma faixa larga (16:9 no celular, 21:9 no desktop) e
  /// um recorte de formato errado ficaria mal enquadrado nos dois.
  final double? aspectRatio;

  /// Proporção real da imagem (largura/altura), quando quem chamou já
  /// decodificou a imagem antes (ex: `prepararImagemParaRecorte`) e já sabe
  /// esse valor — evita decodificar a mesma imagem de novo só pra descobrir
  /// a proporção, e principalmente evita que essa 2ª decodificação divirja
  /// da 1ª (achado real: o resultado batia diferente em algum caso,
  /// deixando o recorte inicial menor que a imagem inteira — sintoma de
  /// "abre já cortado no centro"). Se não informado, decodifica a própria
  /// `imagem` recebida pra descobrir (comportamento de antes).
  final double? proporcaoConhecida;

  const CortarImagemScreen({
    super.key,
    required this.imagem,
    this.aspectRatio,
    this.proporcaoConhecida,
  });

  @override
  State<CortarImagemScreen> createState() => _CortarImagemScreenState();
}

class _CortarImagemScreenState extends State<CortarImagemScreen> {
  final _controller = CropController();
  bool _processando = false;
  double? _proporcaoImagem;

  @override
  void initState() {
    super.initState();
    if (widget.proporcaoConhecida != null) {
      _proporcaoImagem = widget.proporcaoConhecida;
    } else {
      _carregarProporcao();
    }
  }

  /// O pacote `crop_your_image` inicia o recorte como um quadrado (aspect
  /// ratio 1.0) por padrão quando nenhum `aspectRatio` é passado — pra uma
  /// foto retangular isso deixa o recorte inicial menor que a imagem
  /// inteira, obrigando a arrastar até o máximo manualmente. Descobrir a
  /// proporção real da imagem e passá-la só pro tamanho inicial (não pro
  /// `Crop.aspectRatio`, que travaria o recorte nessa proporção) resolve:
  /// começa cobrindo a imagem inteira, mas o usuário ainda pode arrastar
  /// livremente pra qualquer formato depois.
  Future<void> _carregarProporcao() async {
    final codec = await ui.instantiateImageCodec(widget.imagem);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() {
      _proporcaoImagem = frame.image.width / frame.image.height;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Recortar imagem'),
        actions: [
          _processando
              ? const Padding(
                  padding: EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.check),
                  tooltip: 'Confirmar recorte',
                  onPressed: () {
                    setState(() => _processando = true);
                    _controller.crop();
                  },
                ),
        ],
      ),
      body: _proporcaoImagem == null
          ? const Center(child: CircularProgressIndicator())
          : Crop(
              image: widget.imagem,
              controller: _controller,
              interactive: true,
              aspectRatio: widget.aspectRatio,
              initialRectBuilder: InitialRectBuilder.withSizeAndRatio(
                size: 1,
                aspectRatio: widget.aspectRatio ?? _proporcaoImagem,
              ),
              onCropped: (result) {
                if (!mounted) return;
                switch (result) {
                  case CropSuccess(:final croppedImage):
                    Navigator.of(context).pop(croppedImage);
                  case CropFailure():
                    setState(() => _processando = false);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Erro ao recortar a imagem. Tente novamente.')),
                    );
                }
              },
            ),
    );
  }
}
