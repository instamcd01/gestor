import 'package:flutter/material.dart';

import '../config/supabase_config.dart';
import '../utils/busca_utils.dart';
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

/// Carrega, por categoria, os valores já usados em cada campo estruturado
/// — vira sugestão de autocompletar nos campos (ver `_CampoComSugestao`),
/// mesma ideia de "escolher entre o que já existe, ou digitar um valor
/// novo" já usada pra categoria/subcategoria, mas sem precisar de uma tela
/// de gerenciamento dedicada: esses 8 campos são texto livre, sem tabela
/// própria pra mesclar/reordenar como `categorias` tem — o valor digitado
/// e salvo no produto já vira sugestão pro próximo produto sozinho.
Future<Map<String, Map<String, List<String>>>> carregarValoresEstruturadosPorCategoria() async {
  final linhas = await supabase
      .from('produtos')
      .select('categoria, nome_comercial, especie, fase, porte, sabor, dose, composicao, apresentacao')
      .limit(5000);

  const campos = ['nome_comercial', 'especie', 'fase', 'porte', 'sabor', 'dose', 'composicao', 'apresentacao'];
  final porCategoria = <String, Map<String, Set<String>>>{};

  for (final linha in (linhas as List)) {
    final categoria = linha['categoria'] as String? ?? '';
    final porCampo = porCategoria.putIfAbsent(categoria, () => {for (final c in campos) c: <String>{}});
    for (final campo in campos) {
      final valor = (linha[campo] as String?)?.trim();
      if (valor != null && valor.isNotEmpty) porCampo[campo]!.add(valor);
    }
  }

  return porCategoria.map(
    (categoria, porCampo) => MapEntry(
      categoria,
      porCampo.map((campo, valores) => MapEntry(campo, valores.toList()..sort())),
    ),
  );
}

/// Campo de texto com sugestão dos valores já usados nesse campo/categoria
/// — tocar no campo já mostra a lista (não precisa digitar nada pra ver as
/// opções), filtra conforme digita (mesma normalização de acento/maiúscula
/// da busca de produtos), e digitar algo que não está na lista continua
/// funcionando normalmente — ver comentário de `carregarValoresEstruturadosPorCategoria`
/// sobre por que "adicionar" aqui é só digitar e salvar.
class _CampoComSugestao extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? helperText;
  final List<String> sugestoes;

  const _CampoComSugestao({
    required this.controller,
    required this.label,
    this.helperText,
    required this.sugestoes,
  });

  @override
  State<_CampoComSugestao> createState() => _CampoComSugestaoState();
}

class _CampoComSugestaoState extends State<_CampoComSugestao> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (value) {
        if (value.text.isEmpty) return widget.sugestoes;
        return widget.sugestoes.where((s) => contemTodasPalavras(s, value.text));
      },
      fieldViewBuilder: (context, textEditingController, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: textEditingController,
          focusNode: focusNode,
          decoration: InputDecoration(labelText: widget.label, helperText: widget.helperText),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final lista = options.toList();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220, maxWidth: 320),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: lista.length,
                itemBuilder: (context, index) {
                  final opcao = lista[index];
                  return ListTile(
                    dense: true,
                    title: Text(opcao),
                    onTap: () => onSelected(opcao),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
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

  /// Valores já usados em cada campo pra categoria atual (chave = mesmo
  /// nome de coluna usado em `camposVisiveis`, mais `"nome_comercial"`) —
  /// vem de `carregarValoresEstruturadosPorCategoria()`, já resolvido pra
  /// categoria selecionada no momento (a tela chamadora faz o lookup, mesmo
  /// padrão de `camposVisiveis`). Campo ausente/lista vazia = sem sugestão,
  /// campo funciona como texto livre normal.
  final Map<String, List<String>> valoresExistentes;

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
    this.valoresExistentes = const {},
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

    List<String> sugestoesPara(String campo) => valoresExistentes[campo] ?? const [];

    final campos = [
      MapEntry('especie', _CampoComSugestao(
        controller: especieController,
        label: 'Espécie',
        sugestoes: sugestoesPara('especie'),
      )),
      MapEntry('fase', _CampoComSugestao(
        controller: faseController,
        label: 'Fase',
        sugestoes: sugestoesPara('fase'),
      )),
      MapEntry('porte', _CampoComSugestao(
        controller: porteController,
        label: 'Porte',
        sugestoes: sugestoesPara('porte'),
      )),
      MapEntry('sabor', _CampoComSugestao(
        controller: saborController,
        label: 'Sabor',
        sugestoes: sugestoesPara('sabor'),
      )),
      MapEntry('dose', _CampoComSugestao(
        controller: doseController,
        label: 'Dose',
        sugestoes: sugestoesPara('dose'),
      )),
      MapEntry('apresentacao', _CampoComSugestao(
        controller: apresentacaoController,
        label: 'Apresentação',
        sugestoes: sugestoesPara('apresentacao'),
      )),
      MapEntry('composicao', _CampoComSugestao(
        controller: composicaoController,
        label: 'Composição/princípio ativo',
        helperText: 'Mostrado entre parênteses no nome gerado',
        sugestoes: sugestoesPara('composicao'),
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
        _CampoComSugestao(
          controller: nomeComercialController,
          label: 'Nome comercial',
          helperText: 'Ex: "Agemoxi", "Golden Fórmula" — nome da linha/marca do produto',
          sugestoes: sugestoesPara('nome_comercial'),
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
