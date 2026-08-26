import '../config/supabase_config.dart';
import '../models/produto.dart';
import '../models/sugestao_variante.dart';

/// Camada de acesso a dados de produtos. Fala diretamente com o Supabase.
/// O isolamento por empresa é garantido pelo RLS no banco — não precisamos
/// (nem devemos) filtrar por empresa_id manualmente aqui nas consultas de
/// leitura, o Postgres já faz isso.
class ProdutoRepository {
  static const _selectComEstoque =
      '*, estoque(id, quantidade_atual, quantidade_minima, deposito_id)';

  Future<List<Produto>> listar() async {
    // eh_kit=false: kit é uma linha de produtos sem estoque próprio — sem
    // esse filtro apareceria aqui como produto quebrado ("0 em estoque") em
    // toda tela que lê ProdutoProvider.produtos. Kit tem listagem própria
    // (KitProdutoProvider/KitsScreen).
    final data = await supabase
        .from('produtos')
        .select(_selectComEstoque)
        .eq('eh_kit', false)
        .isFilter('deleted_at', null)
        .order('nome', ascending: true);

    return (data as List)
        .map((row) => Produto.fromSupabase(row as Map<String, dynamic>))
        .toList();
  }

  /// Cria o produto e já garante uma linha de estoque associada
  /// (quantidade zerada até o usuário definir, sem depósito ainda).
  Future<Produto> criar(Produto produto, {required String empresaId}) async {
    final produtoInserido = await supabase
        .from('produtos')
        .insert({...produto.toSupabaseMap(), 'empresa_id': empresaId})
        .select()
        .single();

    final produtoId = produtoInserido['id'] as String;

    final estoqueInserido = await supabase
        .from('estoque')
        .insert({
          'empresa_id': empresaId,
          'produto_id': produtoId,
          'quantidade_atual': produto.estoqueAtual,
          'quantidade_minima': produto.estoqueMinimo,
        })
        .select()
        .single();

    return Produto.fromSupabase({
      ...produtoInserido,
      'estoque': [estoqueInserido],
    });
  }

  /// Insere muitos produtos de uma vez (importação de planilha) — evita
  /// 2 round-trips por produto (produtos + estoque) que uma inserção
  /// sequencial faria; pra alguns milhares de linhas isso é a diferença
  /// entre segundos e dezenas de minutos. Insere em lotes de [tamanhoLote]
  /// pra não estourar o tamanho de uma única requisição.
  Future<int> criarEmLote(List<Produto> produtos, {required String empresaId, int tamanhoLote = 300}) async {
    var totalInseridos = 0;
    for (var i = 0; i < produtos.length; i += tamanhoLote) {
      final lote = produtos.sublist(i, i + tamanhoLote > produtos.length ? produtos.length : i + tamanhoLote);

      final produtosInseridos = await supabase
          .from('produtos')
          .insert(lote.map((p) => {...p.toSupabaseMap(), 'empresa_id': empresaId}).toList())
          .select('id');

      final ids = (produtosInseridos as List).map((r) => r['id'] as String).toList();

      final estoquePayload = <Map<String, dynamic>>[];
      for (var j = 0; j < ids.length; j++) {
        estoquePayload.add({
          'empresa_id': empresaId,
          'produto_id': ids[j],
          'quantidade_atual': lote[j].estoqueAtual,
          'quantidade_minima': lote[j].estoqueMinimo,
        });
      }
      await supabase.from('estoque').insert(estoquePayload);

      totalInseridos += ids.length;
    }
    return totalInseridos;
  }

  /// Retorna o produto RECÉM-LIDO do banco após o update, nunca o objeto
  /// que o client mandou — campos calculados no servidor (nome gerado por
  /// `gerar_nome_produto_estruturado`, margem, revisar_preco...) mudam via
  /// trigger DEPOIS do UPDATE, e o objeto local não sabe disso. Sem isso, a
  /// tela via o nome/margem antigos até o próximo `listar()` completo (ex:
  /// reabrir o app) — foi o que fez "gerar nome automaticamente" parecer
  /// quebrado quando na real o banco já tinha gerado certo.
  Future<Produto> atualizar(Produto produto) async {
    if (produto.id == null) {
      throw ArgumentError('Produto sem id não pode ser atualizado');
    }

    final produtoAtualizado = await supabase
        .from('produtos')
        .update(produto.toSupabaseMap())
        .eq('id', produto.id!)
        .select()
        .single();

    if (produto.estoqueId != null) {
      await supabase.from('estoque').update({
        'quantidade_atual': produto.estoqueAtual,
        'quantidade_minima': produto.estoqueMinimo,
      }).eq('id', produto.estoqueId!);
    }

    return Produto.fromSupabase({
      ...produtoAtualizado,
      'estoque': produto.estoqueId != null
          ? [
              {
                'id': produto.estoqueId,
                'quantidade_atual': produto.estoqueAtual,
                'quantidade_minima': produto.estoqueMinimo,
              }
            ]
          : [],
    });
  }

  /// Exclusão lógica — preserva histórico (vendas antigas continuam
  /// referenciando o produto) em vez de apagar a linha de verdade.
  Future<void> excluir(String produtoId) async {
    await supabase
        .from('produtos')
        .update({'deleted_at': DateTime.now().toIso8601String()})
        .eq('id', produtoId);
  }

  Future<List<Produto>> listarExcluidos() async {
    final data = await supabase
        .from('produtos')
        .select(_selectComEstoque)
        .eq('eh_kit', false)
        .not('deleted_at', 'is', null)
        .order('deleted_at', ascending: false);

    return (data as List)
        .map((row) => Produto.fromSupabase(row as Map<String, dynamic>))
        .toList();
  }

  Future<void> restaurar(String produtoId) async {
    await supabase.from('produtos').update({'deleted_at': null}).eq('id', produtoId);
  }

  Future<void> marcarPrecoRevisado(String produtoId) async {
    await supabase.from('produtos').update({'revisar_preco': false}).eq('id', produtoId);
  }

  /// Mesma coisa que [marcarPrecoRevisado], mas pra vários produtos de uma
  /// vez (tela de Análise de Produtos em massa) — todos recebem o mesmo
  /// valor, então um único UPDATE com `.inFilter` já resolve.
  Future<void> marcarPrecoRevisadoEmMassa(List<String> produtoIds) async {
    if (produtoIds.isEmpty) return;
    await supabase.from('produtos').update({'revisar_preco': false}).inFilter('id', produtoIds);
  }

  /// Recalcula o preço de venda de um produto a partir do custo atual dele
  /// (markup aplicado no cliente, ver `CalculadoraPrecoMarkup`) e já marca
  /// como revisado — usado na revisão de preço em massa, um UPDATE estreito
  /// (só `preco`/`revisar_preco`) pra não arriscar sobrescrever outros
  /// campos com um objeto `Produto` local desatualizado.
  Future<void> aplicarPrecoRevisado(String produtoId, double novoPreco) async {
    await supabase
        .from('produtos')
        .update({'preco': novoPreco, 'revisar_preco': false}).eq('id', produtoId);
  }

  /// Define (ou limpa, com `dias == null`) o ciclo de recompra de vários
  /// produtos de uma vez — mesmo valor pra todos, então um único UPDATE.
  Future<void> atualizarCicloRecompraEmMassa(List<String> produtoIds, int? dias) async {
    if (produtoIds.isEmpty) return;
    await supabase.from('produtos').update({'ciclo_recompra_dias': dias}).inFilter('id', produtoIds);
  }

  /// Categorias disponíveis pra empresa — mesma fonte usada em
  /// cadastro/editar produto: a tabela `categorias` (cadastradas via
  /// "Gerenciar categorias") unida com o que já está em uso em
  /// `produtos.categoria` (que pode ter nomes ainda não formalizados lá).
  Future<List<String>> listarCategoriasDisponiveis() async {
    final data = await supabase.from('categorias').select('nome').order('ordem', ascending: true);
    final categorias = (data as List).map((r) => r['nome'] as String).toSet();

    final produtosData = await supabase.from('produtos').select('categoria');
    categorias.addAll(
      (produtosData as List).map((p) => (p['categoria'] as String?) ?? '').where((c) => c.isNotEmpty),
    );
    return categorias.toList()..sort();
  }

  /// Mesma lógica de [listarCategoriasDisponiveis], mas pra fabricantes
  /// (tabela `fabricantes` + o que já está em uso em `produtos.fabricante`).
  Future<List<String>> listarFabricantesDisponiveis() async {
    final data = await supabase.from('fabricantes').select('nome').order('ordem', ascending: true);
    final fabricantes = (data as List).map((r) => r['nome'] as String? ?? '').where((f) => f.isNotEmpty).toSet();

    final produtosData = await supabase.from('produtos').select('fabricante');
    fabricantes.addAll(
      (produtosData as List).map((p) => (p['fabricante'] as String?) ?? '').where((f) => f.isNotEmpty),
    );
    return fabricantes.toList()..sort();
  }

  /// Categoria (obrigatória) + subcategoria (opcional, `null` limpa) de
  /// vários produtos de uma vez.
  Future<void> atualizarCategoriaEmMassa(List<String> produtoIds, String categoria, String? subcategoria) async {
    if (produtoIds.isEmpty) return;
    await supabase
        .from('produtos')
        .update({'categoria': categoria, 'subcategoria': subcategoria}).inFilter('id', produtoIds);
  }

  Future<void> atualizarFabricanteEmMassa(List<String> produtoIds, String fabricante) async {
    if (produtoIds.isEmpty) return;
    await supabase.from('produtos').update({'fabricante': fabricante}).inFilter('id', produtoIds);
  }

  Future<void> atualizarExibirCatalogoEmMassa(List<String> produtoIds, bool exibir) async {
    if (produtoIds.isEmpty) return;
    await supabase.from('produtos').update({'exibir_no_catalogo': exibir}).inFilter('id', produtoIds);
  }

  Future<void> atualizarAtivoEmMassa(List<String> produtoIds, bool ativo) async {
    if (produtoIds.isEmpty) return;
    await supabase.from('produtos').update({'ativo': ativo}).inFilter('id', produtoIds);
  }

  Future<void> atualizarDestaqueEmMassa(List<String> produtoIds, bool destacar) async {
    if (produtoIds.isEmpty) return;
    await supabase.from('produtos').update({'destaque': destacar}).inFilter('id', produtoIds);
  }

  /// Estoque mínimo vive na tabela `estoque` (não em `produtos`), por isso
  /// o UPDATE aqui filtra por `produto_id`, não por `id`.
  Future<void> atualizarEstoqueMinimoEmMassa(List<String> produtoIds, int minimo) async {
    if (produtoIds.isEmpty) return;
    await supabase.from('estoque').update({'quantidade_minima': minimo}).inFilter('produto_id', produtoIds);
  }

  Future<List<SugestaoVariante>> listarSugestoesVariantePendentes() async {
    final data = await supabase
        .from('sugestoes_variante')
        .select()
        .eq('status', 'pendente')
        .order('criado_em', ascending: true);

    return (data as List)
        .map((row) => SugestaoVariante.fromSupabase(row as Map<String, dynamic>))
        .toList();
  }

  /// Aprova a sugestão via RPC `aprovar_sugestao_variante` — resolve o pai
  /// real da família no servidor, priorizando quem já pertence (ou já é)
  /// uma família existente. Precisa ser atômico no servidor porque um
  /// produto pode ter mais de uma sugestão pendente (3+ variantes): resolver
  /// só no cliente arriscava a segunda aprovação sobrescrever o vínculo já
  /// criado pela primeira em vez de somar o candidato à mesma família.
  Future<void> aprovarSugestaoVariante({
    required SugestaoVariante sugestao,
    required String tipoVariacao,
    required String varianteLabelProduto,
    required String varianteLabelCandidato,
  }) async {
    await supabase.rpc('aprovar_sugestao_variante', params: {
      'p_sugestao_id': sugestao.id,
      'p_tipo_variacao': tipoVariacao,
      'p_variante_label_produto': varianteLabelProduto,
      'p_variante_label_candidato': varianteLabelCandidato,
    });
  }

  Future<void> rejeitarSugestaoVariante(String sugestaoId) async {
    await supabase.from('sugestoes_variante').update({
      'status': 'rejeitado',
      'revisado_em': DateTime.now().toIso8601String(),
    }).eq('id', sugestaoId);
  }

  Future<List<SugestaoVariante>> listarSugestoesVarianteRejeitadas() async {
    final data = await supabase
        .from('sugestoes_variante')
        .select()
        .eq('status', 'rejeitado')
        .order('revisado_em', ascending: false);

    return (data as List)
        .map((row) => SugestaoVariante.fromSupabase(row as Map<String, dynamic>))
        .toList();
  }

  /// Volta a sugestão pra `pendente` — deixa aparecer de novo pro usuário
  /// reconsiderar sem precisar esperar o trigger gerá-la de novo.
  Future<void> reconsiderarSugestaoVariante(String sugestaoId) async {
    await supabase.from('sugestoes_variante').update({
      'status': 'pendente',
      'revisado_em': null,
    }).eq('id', sugestaoId);
  }

  /// Vínculo manual (produto que o algoritmo de sugestão não pegou) — RPC
  /// `vincular_variante_manualmente` reaproveita no servidor a mesma
  /// resolução de âncora de `aprovar_sugestao_variante`, sem depender de
  /// uma sugestão pendente.
  Future<void> vincularVarianteManualmente({
    required String produtoId,
    required String produtoCandidatoId,
    required String tipoVariacao,
    required String varianteLabelProduto,
    required String varianteLabelCandidato,
  }) async {
    await supabase.rpc('vincular_variante_manualmente', params: {
      'p_produto_id': produtoId,
      'p_produto_candidato_id': produtoCandidatoId,
      'p_tipo_variacao': tipoVariacao,
      'p_variante_label_produto': varianteLabelProduto,
      'p_variante_label_candidato': varianteLabelCandidato,
    });
  }

  /// Tira um produto da família de variantes via RPC `desvincular_variante`.
  /// Precisa ser atômico no servidor porque, quando o produto que sai é a
  /// própria âncora da família, a função promove um dos filhos a nova âncora
  /// e reaponta os demais — resolver isso em várias chamadas do cliente
  /// arriscaria deixar a família inconsistente se uma falhar no meio.
  Future<void> desvincularVariante(String produtoId) async {
    await supabase.rpc('desvincular_variante', params: {'p_produto_id': produtoId});
  }
}
