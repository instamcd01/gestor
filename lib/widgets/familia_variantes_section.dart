import 'package:flutter/material.dart';

import '../models/produto.dart';
import '../utils/variante_label_utils.dart';
import 'form_section.dart';

/// Seção "Família de variantes" em editar_produto_screen.dart — só aparece
/// quando o produto já faz parte de uma família (aprovado via sugestão de
/// variante). Mostra o eixo, o rótulo deste produto (editável) e a lista
/// das demais variantes da mesma família, além do botão pra desfazer o
/// vínculo. Antes desta seção não havia nenhum jeito de ver ou editar isso
/// no app depois que a sugestão era aprovada.
class FamiliaVariantesSection extends StatelessWidget {
  final Produto produtoAtual;
  final List<Produto> familia;
  final TextEditingController varianteLabelController;
  final bool desvinculando;
  final ValueChanged<Produto> onAbrirVariante;
  final VoidCallback onDesvincular;

  const FamiliaVariantesSection({
    super.key,
    required this.produtoAtual,
    required this.familia,
    required this.varianteLabelController,
    required this.desvinculando,
    required this.onAbrirVariante,
    required this.onDesvincular,
  });

  @override
  Widget build(BuildContext context) {
    final irmaos = familia.where((p) => p.id != produtoAtual.id).toList();
    final tipo = produtoAtual.tipoVariacao ?? '';

    return FormSection(
      titulo: 'Família de variantes',
      children: [
        Text(
          'Eixo: ${rotuloTipoVariacao(tipo)}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        TextFormField(
          controller: varianteLabelController,
          decoration: const InputDecoration(
            labelText: 'Opção deste produto',
            helperText: 'Valor mostrado no seletor do site (ex: "10kg", "Frango")',
          ),
        ),
        if (irmaos.isEmpty)
          const Text('Nenhuma outra variante encontrada — o vínculo aponta pra um produto que não existe mais.')
        else ...[
          const Text('Outras opções desta família:', style: TextStyle(fontWeight: FontWeight.w600)),
          Column(
            children: [
              for (final irmao in irmaos)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: irmao.id == produtoAtual.produtoPaiId || irmao.produtoPaiId == null
                      ? const Icon(Icons.star_outline, size: 20)
                      : const Icon(Icons.subdirectory_arrow_right, size: 20),
                  title: Text(irmao.nome, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    '${irmao.varianteLabel?.isNotEmpty == true ? irmao.varianteLabel : "sem rótulo"} • '
                    'R\$ ${irmao.preco.toStringAsFixed(2)}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onAbrirVariante(irmao),
                ),
            ],
          ),
        ],
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
          icon: desvinculando
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.link_off),
          label: const Text('Remover da família'),
          onPressed: desvinculando ? null : onDesvincular,
        ),
      ],
    );
  }
}
