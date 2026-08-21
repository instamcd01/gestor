import 'package:flutter/material.dart';

import '../config/supabase_config.dart';
import '../screens/gerenciar_valores_estruturados_screen.dart';
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

/// Campo de texto com sugestão dos valores já usados nesse campo/categoria
/// (vocabulário curado em `valores_estruturados_variante`, ver
/// `ValorEstruturadoRepository`) — tocar no campo já mostra a lista (não
/// precisa digitar nada pra ver as opções), filtra conforme digita (mesma
/// normalização de acento/maiúscula da busca de produtos), e digitar algo
/// que não está na lista continua funcionando normalmente: o valor novo
/// entra no vocabulário sozinho ao salvar o produto (`garantir`), sem
/// exigir um botão "adicionar" aqui.
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

/// Campos estruturados de variante (tipo de produto, nome comercial,
/// espécie, fase, porte, sabor, dose, composição, apresentação) — usados
/// em cadastro/edição de produto. Reaproveitado entre CadastroProdutoScreen
/// e EditarProdutoScreen pra não duplicar os 9 campos + a lógica de aviso
/// do nome automático.
///
/// Todos os campos são opcionais. Quando "Nome comercial" é preenchido, o
/// trigger `gerar_nome_produto_estruturado` do banco recompõe o campo
/// "Nome do Produto" automaticamente ao salvar (a menos que
/// `nomeManualOverride` esteja marcado) — ver
/// docs/superpowers/specs/2026-08-03-variantes-produto-design.md.
class CamposEstruturadosVariante extends StatelessWidget {
  final TextEditingController tipoProdutoController;
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

  /// Categoria selecionada no momento — usada só pra resolver
  /// `valoresPorCategoria[categoria]` (sugestões específicas dessa
  /// categoria, combinadas com as globais em `valoresPorCategoria['']`).
  final String categoria;

  /// Vocabulário completo (todas as categorias de uma vez, ver
  /// `ValorEstruturadoRepository.carregarPorCategoria`) — resolvido aqui
  /// pra [categoria] + globais, em vez de a tela chamadora já mandar
  /// pré-resolvido, porque a combinação (específico ∪ global) é lógica
  /// deste widget, não de quem o usa.
  final Map<String, Map<String, List<String>>> valoresPorCategoria;

  /// Chamado depois de voltar da tela de gerenciamento de valores — a tela
  /// chamadora recarrega `valoresPorCategoria` (o vocabulário pode ter
  /// mudado: renomeado, excluído, adicionado).
  final VoidCallback onValoresAtualizados;

  const CamposEstruturadosVariante({
    super.key,
    required this.tipoProdutoController,
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
    required this.categoria,
    required this.onValoresAtualizados,
    this.camposVisiveis,
    this.valoresPorCategoria = const {},
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

    List<String> sugestoesPara(String campo) {
      final especificos = valoresPorCategoria[categoria]?[campo] ?? const <String>[];
      final globais = valoresPorCategoria['']?[campo] ?? const <String>[];
      if (globais.isEmpty) return especificos;
      return {...especificos, ...globais}.toList()..sort();
    }

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
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                'Preencha se este produto tem outras opções de peso, dose ou sabor '
                '(ex: a mesma ração em pesos diferentes). Ajuda o sistema a sugerir '
                'o agrupamento delas no site automaticamente. Se "Nome comercial" '
                'for preenchido, o "Nome do Produto" acima é gerado automaticamente '
                'a partir destes campos ao salvar — a menos que "Editar nome '
                'manualmente" esteja marcado abaixo.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
            IconButton(
              tooltip: 'Gerenciar valores sugeridos',
              icon: const Icon(Icons.tune, size: 20),
              onPressed: () async {
                await Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => GerenciarValoresEstruturadosScreen(categoriaInicial: categoria),
                ));
                onValoresAtualizados();
              },
            ),
          ],
        ),
        if (nomeManualOverride)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, size: 20, color: colorScheme.onErrorContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'O nome não será atualizado automaticamente',
                        style: TextStyle(fontWeight: FontWeight.w600, color: colorScheme.onErrorContainer),
                      ),
                      Text(
                        '"Editar nome manualmente" está ativado pra este produto (padrão herdado '
                        'do catálogo importado) — preencher os campos abaixo não muda o "Nome do '
                        'Produto" enquanto isso estiver ligado.',
                        style: TextStyle(fontSize: 12, color: colorScheme.onErrorContainer),
                      ),
                      TextButton(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(0, 32),
                          foregroundColor: colorScheme.onErrorContainer,
                        ),
                        onPressed: () => onNomeManualOverrideChanged(false),
                        child: const Text('Desativar e gerar automaticamente'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        _CampoComSugestao(
          controller: tipoProdutoController,
          label: 'Tipo de produto',
          helperText: 'Ex: "Antibiótico", "Antipulgas", "Ração" — início do nome gerado. '
              'Em branco, esse trecho simplesmente não aparece (não usa a categoria)',
          sugestoes: sugestoesPara('tipo_produto'),
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
