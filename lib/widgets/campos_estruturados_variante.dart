import 'package:flutter/material.dart';

import '../config/supabase_config.dart';
import 'form_section.dart';

/// Busca, pra cada categoria, quais dos 7 campos estruturados opcionais
/// (fora `nome_comercial`, que sempre aparece) fazem sentido mostrar no
/// formulário — ex: Ração usa fase/porte/sabor, Farmácia usa dose/
/// composição/apresentação. Carrega tudo de uma vez (mapa categoria ->
/// campos) em vez de uma consulta por categoria, mesmo padrão de
/// categorias/fabricantes já usado nas telas de cadastro/edição.
///
/// Categoria sem nenhuma linha em `categoria_campos_estruturados` volta
/// como ausente do mapa — quem consome trata isso como "mostrar todos os
/// campos" (fallback seguro pra categoria nova/não configurada ainda).
Future<Map<String, Set<String>>> carregarCamposEstruturadosPorCategoria() async {
  final linhas = await supabase.from('categoria_campos_estruturados').select('categoria, campo');
  final mapa = <String, Set<String>>{};
  for (final linha in (linhas as List)) {
    final categoria = linha['categoria'] as String;
    final campo = linha['campo'] as String;
    (mapa[categoria] ??= {}).add(campo);
  }
  return mapa;
}

/// Campos estruturados de variante (nome comercial, espécie, fase, porte,
/// sabor, dose, composição, apresentação) — usados em cadastro/edição de
/// produto. Reaproveitado entre CadastroProdutoScreen e EditarProdutoScreen
/// pra não duplicar os 8 campos + a lógica de aviso do nome automático.
///
/// Todos os campos são opcionais. Quando "Nome comercial" é preenchido, o
/// trigger `gerar_nome_produto_estruturado` do banco recompõe o campo
/// "Nome do Produto" automaticamente ao salvar (a menos que
/// `nomeManualOverride` esteja marcado) — ver
/// docs/superpowers/specs/2026-08-03-variantes-produto-design.md.
class CamposEstruturadosVariante extends StatelessWidget {
  final TextEditingController nomeComercialController;
  final TextEditingController especieController;
  final TextEditingController faseController;
  final TextEditingController porteController;
  final TextEditingController saborController;
  final TextEditingController doseController;
  final TextEditingController composicaoController;
  final TextEditingController apresentacaoController;
  final bool nomeManualOverride;
  final ValueChanged<bool> onNomeManualOverrideChanged;

  /// Quais dos 7 campos opcionais mostrar (`"especie"`, `"fase"`, `"porte"`,
  /// `"sabor"`, `"dose"`, `"composicao"`, `"apresentacao"`) — `null` mostra
  /// todos (categoria ainda não configurada em `categoria_campos_estruturados`).
  final Set<String>? camposVisiveis;

  const CamposEstruturadosVariante({
    super.key,
    required this.nomeComercialController,
    required this.especieController,
    required this.faseController,
    required this.porteController,
    required this.saborController,
    required this.doseController,
    required this.composicaoController,
    required this.apresentacaoController,
    required this.nomeManualOverride,
    required this.onNomeManualOverrideChanged,
    this.camposVisiveis,
  });

  bool _visivel(String campo) => camposVisiveis == null || camposVisiveis!.contains(campo);

  /// Agrupa os campos visíveis em pares (Row de 2) — o último fica sozinho
  /// (ocupando a linha inteira) quando o total for ímpar.
  List<Widget> _linhasEmPares(List<MapEntry<String, Widget>> campos) {
    final visiveis = campos.where((c) => _visivel(c.key)).map((c) => c.value).toList();
    final linhas = <Widget>[];
    for (var i = 0; i < visiveis.length; i += 2) {
      if (i + 1 < visiveis.length) {
        linhas.add(Row(
          children: [
            Expanded(child: visiveis[i]),
            const SizedBox(width: 8),
            Expanded(child: visiveis[i + 1]),
          ],
        ));
      } else {
        linhas.add(visiveis[i]);
      }
    }
    return linhas;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final campos = [
      MapEntry('especie', TextFormField(
        controller: especieController,
        decoration: const InputDecoration(labelText: 'Espécie'),
      )),
      MapEntry('fase', TextFormField(
        controller: faseController,
        decoration: const InputDecoration(labelText: 'Fase'),
      )),
      MapEntry('porte', TextFormField(
        controller: porteController,
        decoration: const InputDecoration(labelText: 'Porte'),
      )),
      MapEntry('sabor', TextFormField(
        controller: saborController,
        decoration: const InputDecoration(labelText: 'Sabor'),
      )),
      MapEntry('dose', TextFormField(
        controller: doseController,
        decoration: const InputDecoration(labelText: 'Dose'),
      )),
      MapEntry('apresentacao', TextFormField(
        controller: apresentacaoController,
        decoration: const InputDecoration(labelText: 'Apresentação'),
      )),
      MapEntry('composicao', TextFormField(
        controller: composicaoController,
        decoration: const InputDecoration(
          labelText: 'Composição/princípio ativo',
          helperText: 'Mostrado entre parênteses no nome gerado',
        ),
      )),
    ];

    return FormSection(
      titulo: 'Cadastro estruturado de variante (opcional)',
      children: [
        Text(
          'Preencha se este produto tem outras opções de peso, dose ou sabor '
          '(ex: a mesma ração em pesos diferentes). Ajuda o sistema a sugerir '
          'o agrupamento delas no site automaticamente. Se "Nome comercial" '
          'for preenchido, o "Nome do Produto" acima é gerado automaticamente '
          'a partir destes campos ao salvar — a menos que "Editar nome '
          'manualmente" esteja marcado abaixo.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        TextFormField(
          controller: nomeComercialController,
          decoration: const InputDecoration(
            labelText: 'Nome comercial',
            helperText: 'Ex: "Agemoxi", "Golden Fórmula" — nome da linha/marca do produto',
          ),
        ),
        ..._linhasEmPares(campos),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Editar nome manualmente'),
          subtitle: const Text('Mantém o "Nome do Produto" digitado, sem gerar automaticamente'),
          value: nomeManualOverride,
          onChanged: onNomeManualOverrideChanged,
        ),
      ],
    );
  }
}
