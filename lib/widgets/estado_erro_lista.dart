import 'package:flutter/material.dart';

import 'aviso_banner.dart';

/// Estado de erro pra dentro de um `Expanded`/`Center`, no lugar de uma
/// tela que carregou uma lista (padrão repetido em várias telas: até
/// 2026-08-06, o campo `erro` de vários providers era setado mas nunca
/// lido em lugar nenhum -- o usuário via a lista simplesmente vazia, sem
/// saber que uma chamada tinha falhado, indistinguível de "não há nada
/// cadastrado ainda".
class EstadoErroLista extends StatelessWidget {
  final String mensagem;
  final Future<void> Function() onTentarNovamente;

  const EstadoErroLista({super.key, required this.mensagem, required this.onTentarNovamente});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AvisoBanner(texto: mensagem, tipo: TipoAviso.erro),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onTentarNovamente,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}
