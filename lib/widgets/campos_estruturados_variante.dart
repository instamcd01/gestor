import 'package:flutter/material.dart';

import '../config/supabase_config.dart';
import '../repositories/valor_estruturado_repository.dart';
import '../screens/gerenciar_valores_estruturados_screen.dart';
import 'campo_com_sugestao.dart';
import 'form_section.dart';
import 'personalizar_campos_produto_dialog.dart';

/// Busca, pra cada categoria, quais dos 9 campos estruturados aparecem no
/// formulário e EM QUE ORDEM (`categoria_campos_estruturados.ordem`) — ex:
/// Ração usa fase/porte/sabor, Farmácia usa dose/composição/apresentação, e
/// cada uma pode ter Tipo de produto/Nome comercial em posições diferentes.
/// Mesma ordem usada por `compor_nome_produto` pra montar o nome, pra não
/// existir uma ordem no formulário e outra no nome gerado — ver tela
/// "Estrutura do Nome" (`estrutura_nome_produto_screen.dart`), que edita
/// essa mesma tabela. Carrega tudo de uma vez (mapa categoria -> campos)
/// em vez de uma consulta por categoria, mesmo padrão de categorias/
/// fabricantes já usado nas telas de cadastro/edição.
///
/// Categoria sem nenhuma linha em `categoria_campos_estruturados` volta
/// como ausente do mapa — quem consome trata isso como "mostrar todos os
/// campos, na ordem padrão" (`ordemPadraoCamposEstruturados`), fallback
/// seguro pra categoria nova/não configurada ainda.
Future<Map<String, List<String>>> carregarCamposEstruturadosPorCategoria() async {
  final linhas =
      await supabase.from('categoria_campos_estruturados').select('categoria, campo').order('ordem', ascending: true);
  final mapa = <String, List<String>>{};
  for (final linha in (linhas as List)) {
    final categoria = linha['categoria'] as String;
    final campo = linha['campo'] as String;
    (mapa[categoria] ??= []).add(campo);
  }
  return mapa;
}

// Campo com sugestão movido pra widgets/campo_com_sugestao.dart (`CampoComSugestao`,
// público) — reaproveitado também em vincular_variante_dialog.dart.

/// Campos estruturados de variante (tipo de produto, nome comercial,
/// espécie, fase, porte, sabor, dose, composição, apresentação) — usados
/// em cadastro/edição de produto. Reaproveitado entre CadastroProdutoScreen
/// e EditarProdutoScreen pra não duplicar os 9 campos + a lógica de aviso
/// do nome automático.
///
/// Todos os campos são opcionais (exceto Nome comercial, sempre presente —
/// sem ele o produto fica sem identidade no nome gerado). Quando "Nome
/// comercial" é preenchido, o trigger `gerar_nome_produto_estruturado` do
/// banco recompõe o campo "Nome do Produto" automaticamente ao salvar (a
/// menos que `nomeManualOverride` esteja marcado) — ver
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

  /// Quais campos mostrar e em que ordem — mesma lista/ordem configurada em
  /// "Estrutura do Nome" pra essa categoria. `null` mostra todos, na ordem
  /// padrão (`ordemPadraoCamposEstruturados`) — categoria ainda não
  /// configurada em `categoria_campos_estruturados`.
  final List<String>? camposVisiveis;

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

  /// Id do produto atual (null pra produto novo, ainda sem id) — só usado
  /// pra excluir ele mesmo da lista de "copiar de outro produto".
  final String? produtoId;

  /// Override por ESTE produto de quais campos entram no NOME gerado e em
  /// que ordem (inclusive Peso/Volume/Fabricante, que nem aparecem neste
  /// formulário — moram em "Logística e fornecedor") — nunca afeta quais
  /// campos aparecem AQUI no formulário, isso continua só pela categoria
  /// ([camposVisiveis]). Ver `Produto.camposEstruturadosPersonalizados`.
  final List<String>? camposPersonalizados;
  final ValueChanged<List<String>?> onCamposPersonalizadosChanged;

  // Só pra alimentar a prévia do nome dentro do diálogo de personalização —
  // estes 3 campos são editados na seção "Logística e fornecedor", não
  // aqui, mas entram na composição do nome gerado.
  final TextEditingController pesoController;
  final TextEditingController volumeController;
  final TextEditingController fabricanteController;

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
    required this.produtoId,
    required this.camposPersonalizados,
    required this.onCamposPersonalizadosChanged,
    required this.pesoController,
    required this.volumeController,
    required this.fabricanteController,
    this.camposVisiveis,
    this.valoresPorCategoria = const {},
  });

  /// Ordem efetiva do FORMULÁRIO: só o padrão da categoria (ou o padrão
  /// geral, se a categoria nunca foi configurada) — nunca influenciada pela
  /// personalização de nome do produto, decisão explícita do usuário pra
  /// manter as duas coisas independentes. "Nome comercial" nunca pode
  /// ficar de fora (garantido também na tela que grava essa configuração)
  /// — reforçado aqui de novo pra este formulário nunca ficar sem como
  /// preencher o nome do produto, mesmo que a configuração salva esteja
  /// incompleta por algum motivo.
  List<String> get _ordemEfetiva {
    final ordem = camposVisiveis ?? ordemPadraoCamposEstruturados;
    return ordem.contains('nome_comercial') ? ordem : [...ordem, 'nome_comercial'];
  }

  /// Ponto de partida pro diálogo de personalização de NOME: a
  /// personalização já salva pro produto, senão o padrão da categoria (a
  /// mesma fonte que `compor_nome_produto` usa quando não há override),
  /// senão o padrão geral. Cobre os 12 campos (não só os 9 do formulário).
  List<String> get _ordemNomeEfetiva => camposPersonalizados ?? camposVisiveis ?? ordemPadraoCamposEstruturados;

  /// Agrupa os campos em pares (Row de 2), na ordem recebida — o último
  /// fica sozinho (ocupando a linha inteira) quando o total for ímpar.
  List<Widget> _linhasEmPares(List<Widget> campos) {
    final linhas = <Widget>[];
    for (var i = 0; i < campos.length; i += 2) {
      if (i + 1 < campos.length) {
        linhas.add(Row(
          children: [
            Expanded(child: campos[i]),
            const SizedBox(width: 8),
            Expanded(child: campos[i + 1]),
          ],
        ));
      } else {
        linhas.add(campos[i]);
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

    final camposPorNome = <String, Widget>{
      'tipo_produto': CampoComSugestao(
        controller: tipoProdutoController,
        label: 'Tipo de produto',
        helperText: 'Ex: "Antibiótico", "Antipulgas", "Ração". Em branco, esse trecho não aparece.',
        sugestoes: sugestoesPara('tipo_produto'),
      ),
      'nome_comercial': CampoComSugestao(
        controller: nomeComercialController,
        label: 'Nome comercial',
        helperText: 'Ex: "Agemoxi", "Golden Fórmula" — nome da linha/marca do produto',
        sugestoes: sugestoesPara('nome_comercial'),
      ),
      'especie': CampoComSugestao(
        controller: especieController,
        label: 'Espécie',
        sugestoes: sugestoesPara('especie'),
      ),
      'fase': CampoComSugestao(
        controller: faseController,
        label: 'Fase',
        sugestoes: sugestoesPara('fase'),
      ),
      'porte': CampoComSugestao(
        controller: porteController,
        label: 'Porte',
        sugestoes: sugestoesPara('porte'),
      ),
      'sabor': CampoComSugestao(
        controller: saborController,
        label: 'Sabor',
        sugestoes: sugestoesPara('sabor'),
      ),
      'dose': CampoComSugestao(
        controller: doseController,
        label: 'Dose',
        sugestoes: sugestoesPara('dose'),
      ),
      'apresentacao': CampoComSugestao(
        controller: apresentacaoController,
        label: 'Apresentação',
        sugestoes: sugestoesPara('apresentacao'),
      ),
      'composicao': CampoComSugestao(
        controller: composicaoController,
        label: 'Composição/princípio ativo',
        helperText: 'Mostrado entre parênteses no nome gerado',
        sugestoes: sugestoesPara('composicao'),
      ),
    };

    final camposEmOrdem = [
      for (final campo in _ordemEfetiva)
        if (camposPorNome[campo] != null) camposPorNome[campo]!,
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
                'o agrupamento delas no site automaticamente. O "Nome do Produto" '
                'acima é gerado automaticamente a partir destes campos, na ordem '
                'configurada em Configurações do Produto > Estrutura do Nome — a '
                'menos que "Editar nome manualmente" esteja marcado abaixo.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
              ),
            ),
            IconButton(
              tooltip: 'Personalizar ordem do nome deste produto',
              icon: Icon(
                Icons.reorder,
                size: 20,
                color: camposPersonalizados != null ? colorScheme.primary : null,
              ),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => PersonalizarCamposProdutoDialog(
                  produtoAtualId: produtoId,
                  ordemAtual: _ordemNomeEfetiva,
                  categoria: categoria,
                  tipoProduto: tipoProdutoController.text,
                  nomeComercial: nomeComercialController.text,
                  dose: doseController.text,
                  composicao: composicaoController.text,
                  apresentacao: apresentacaoController.text,
                  especie: especieController.text,
                  fase: faseController.text,
                  porte: porteController.text,
                  sabor: saborController.text,
                  peso: double.tryParse(pesoController.text.replaceAll(',', '.')),
                  volume: double.tryParse(volumeController.text.replaceAll(',', '.')),
                  fabricante: fabricanteController.text,
                  onSalvar: onCamposPersonalizadosChanged,
                  onRestaurarPadrao: () => onCamposPersonalizadosChanged(null),
                ),
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
        ..._linhasEmPares(camposEmOrdem),
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
