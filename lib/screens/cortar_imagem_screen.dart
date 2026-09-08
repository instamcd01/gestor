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

  /// Tamanho real da imagem (em pixels), quando quem chamou já decodificou
  /// a imagem antes (ex: `prepararImagemParaRecorte`) e já sabe esse valor —
  /// evita decodificar a mesma imagem de novo só pra descobrir o tamanho.
  /// Se não informado, decodifica a própria `imagem` recebida.
  final ui.Size? tamanhoConhecido;

  const CortarImagemScreen({
    super.key,
    required this.imagem,
    this.aspectRatio,
    this.tamanhoConhecido,
  });

  @override
  State<CortarImagemScreen> createState() => _CortarImagemScreenState();
}

class _CortarImagemScreenState extends State<CortarImagemScreen> {
  final _controller = CropController();
  bool _processando = false;
  ui.Size? _tamanhoImagem;

  @override
  void initState() {
    super.initState();
    if (widget.tamanhoConhecido != null) {
      _tamanhoImagem = widget.tamanhoConhecido;
    } else {
      _carregarTamanho();
    }
  }

  Future<void> _carregarTamanho() async {
    final codec = await ui.instantiateImageCodec(widget.imagem);
    final frame = await codec.getNextFrame();
    if (!mounted) return;
    setState(() {
      _tamanhoImagem = ui.Size(frame.image.width.toDouble(), frame.image.height.toDouble());
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
      body: _tamanhoImagem == null
          ? const Center(child: CircularProgressIndicator())
          : Crop(
              image: widget.imagem,
              controller: _controller,
              interactive: true,
              aspectRatio: widget.aspectRatio,
              // Confirmado no código-fonte do pacote (calculator.dart, v2.0.0):
              // `withSizeAndRatio` deriva uma dimensão do retângulo inicial a
              // partir da PROPORÇÃO passada, não das dimensões reais da
              // imagem — se essa proporção não bater com o que o pacote
              // calcula internamente pro retângulo renderizado, o recorte
              // inicial fica menor que a imagem inteira numa das dimensões
              // (o "tenho que expandir pro máximo toda vez" que o usuário
              // reportou). `withArea`, ao contrário, recebe a área DIRETO em
              // pixels da imagem original (doc do pacote: um Rect.fromLTWH
              // cobrindo do canto 0,0 até largura/altura da imagem cobre a
              // imagem inteira, sempre, "regardless of viewport size") — sem
              // nenhuma conta de proporção envolvida. Só usa isso quando NÃO
              // há aspectRatio travado (banner mantém o comportamento restrito
              // à proporção fixa via withSizeAndRatio).
              initialRectBuilder: widget.aspectRatio != null
                  ? InitialRectBuilder.withSizeAndRatio(size: 1, aspectRatio: widget.aspectRatio)
                  : InitialRectBuilder.withArea(
                      ImageBasedRect.fromLTWH(0, 0, _tamanhoImagem!.width, _tamanhoImagem!.height),
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
