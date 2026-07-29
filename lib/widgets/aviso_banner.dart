import 'package:flutter/material.dart';

enum TipoAviso { info, alerta, sucesso, erro }

/// Banner de aviso/notícia (ícone + texto), usado no topo de várias telas
/// (Catálogo Online, Integrar Plataformas, Dashboard de Marketplace,
/// Separação de Pedido, ...). Substitui os `Container`s ad-hoc que cada tela
/// tinha, cada um com sua própria cor pastel fixa (ex: `Colors.blue[50]`) —
/// um tom opaco e claro demais, que ficava ilegível/estranho no tema escuro.
class AvisoBanner extends StatelessWidget {
  final String texto;
  final TipoAviso tipo;
  final IconData? icone;
  final bool negrito;

  const AvisoBanner({
    super.key,
    required this.texto,
    this.tipo = TipoAviso.info,
    this.icone,
    this.negrito = false,
  });

  Color _corBase() {
    switch (tipo) {
      case TipoAviso.info:
        return Colors.blue;
      case TipoAviso.alerta:
        return Colors.amber;
      case TipoAviso.sucesso:
        return Colors.green;
      case TipoAviso.erro:
        return Colors.red;
    }
  }

  IconData _iconePadrao() {
    switch (tipo) {
      case TipoAviso.info:
        return Icons.info_outline;
      case TipoAviso.alerta:
        return Icons.warning_amber_rounded;
      case TipoAviso.sucesso:
        return Icons.check_circle_outline;
      case TipoAviso.erro:
        return Icons.error_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cor = _corBase();
    final colorScheme = Theme.of(context).colorScheme;
    // Mistura a cor semântica com a cor de superfície do tema ATUAL, em vez
    // de um tom pastel fixo — assim o fundo/borda acompanham automaticamente
    // claro/escuro (mistura com branco no claro, com o cinza-escuro no
    // escuro), sem precisar de um valor por tema escolhido à mão.
    final fundo = Color.alphaBlend(cor.withValues(alpha: 0.15), colorScheme.surface);
    final borda = Color.alphaBlend(cor.withValues(alpha: 0.4), colorScheme.surface);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borda),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone ?? _iconePadrao(), color: cor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              texto,
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurface,
                fontWeight: negrito ? FontWeight.bold : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
