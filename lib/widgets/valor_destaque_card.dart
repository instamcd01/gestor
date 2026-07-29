import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Cartão de valor em destaque (rótulo + número grande), usado em "Saldo do
/// período", "Total de entradas" etc. Mesma ideia do `AvisoBanner` — a cor
/// semântica (verde/vermelho) é misturada com a superfície do tema ATUAL em
/// vez de um tom pastel fixo (ex: `Colors.green[50]`), que ficava opaco e
/// claro demais no tema escuro; o valor em si usa um tom que se ajusta ao
/// brilho do tema (`AppTheme.tomAdaptavel`) em vez de sempre o mesmo shade.
class ValorDestaqueCard extends StatelessWidget {
  final String rotulo;
  final String valor;
  final String? subtitulo;
  final bool positivo;

  const ValorDestaqueCard({
    super.key,
    required this.rotulo,
    required this.valor,
    this.subtitulo,
    this.positivo = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final MaterialColor corBase = positivo ? Colors.green : Colors.red;
    final fundo = Color.alphaBlend(corBase.withValues(alpha: 0.15), colorScheme.surface);
    final borda = Color.alphaBlend(corBase.withValues(alpha: 0.4), colorScheme.surface);
    final corValor = AppTheme.tomAdaptavel(corBase, theme.brightness);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borda),
      ),
      child: Column(
        children: [
          Text(rotulo, style: TextStyle(color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(valor, style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: corValor)),
          if (subtitulo != null) ...[
            const SizedBox(height: 2),
            Text(subtitulo!, style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant)),
          ],
        ],
      ),
    );
  }
}
