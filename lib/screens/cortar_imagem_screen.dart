import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';

/// Tela de recorte reutilizada tanto ao adicionar uma imagem nova quanto ao
/// re-recortar uma já cadastrada (nesse segundo caso, os bytes já vêm
/// baixados da URL atual). Retorna os bytes recortados via `Navigator.pop`,
/// ou null se o usuário cancelar.
class CortarImagemScreen extends StatefulWidget {
  final Uint8List imagem;

  const CortarImagemScreen({super.key, required this.imagem});

  @override
  State<CortarImagemScreen> createState() => _CortarImagemScreenState();
}

class _CortarImagemScreenState extends State<CortarImagemScreen> {
  final _controller = CropController();
  bool _processando = false;

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
      body: Crop(
        image: widget.imagem,
        controller: _controller,
        interactive: true,
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
