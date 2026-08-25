import 'package:flutter/material.dart';

/// Cartão compacto de métrica (ícone + rótulo + valor + subtítulo opcional)
/// usado nas seções do painel Início. Sem breakpoint próprio — tem largura
/// fixa e reflui naturalmente dentro de um `Wrap` em qualquer tamanho de tela.
class MetricCard extends StatelessWidget {
  final IconData icone;
  final String titulo;
  final String valor;
  final String? subtitulo;
  final Color? corIcone;
  final Color? corSubtitulo;
  final VoidCallback? onTap;

  const MetricCard({
    super.key,
    required this.icone,
    required this.titulo,
    required this.valor,
    this.subtitulo,
    this.corIcone,
    this.corSubtitulo,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cor = corIcone ?? colorScheme.primary;

    return SizedBox(
      width: 190,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: cor.withValues(alpha: 0.12), shape: BoxShape.circle),
                      child: Icon(icone, size: 18, color: cor),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  valor,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (subtitulo != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitulo!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: corSubtitulo ?? colorScheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Grade responsiva de `MetricCard`s: calcula quantas colunas cabem (dado
/// uma largura mínima por cartão) e estica cada um pra preencher a linha
/// toda — ao contrário de um `Wrap` puro, não sobra um vão vazio depois do
/// último cartão de cada linha. A largura calculada aqui vence a largura
/// fixa própria do `MetricCard` (que só se aplica quando ele não está
/// encaixado numa restrição de largura mais específica como esta).
class MetricGrid extends StatelessWidget {
  final List<MetricCard> cartoes;
  final double larguraMinima;

  const MetricGrid({super.key, required this.cartoes, this.larguraMinima = 190});

  @override
  Widget build(BuildContext context) {
    const espacamento = 12.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final colunas = ((constraints.maxWidth + espacamento) / (larguraMinima + espacamento))
            .floor()
            .clamp(1, cartoes.length);
        final larguraCartao = (constraints.maxWidth - (colunas - 1) * espacamento) / colunas;

        return Wrap(
          spacing: espacamento,
          runSpacing: espacamento,
          children: [
            for (final cartao in cartoes) SizedBox(width: larguraCartao, child: cartao),
          ],
        );
      },
    );
  }
}
