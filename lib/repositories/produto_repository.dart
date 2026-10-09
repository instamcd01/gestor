import '../config/supabase_config.dart';
import '../models/estoque_parado.dart';
import '../models/resultado_acao.dart';
import '../models/movimentacao_estoque.dart';
import '../models/produto.dart';
import '../models/sugestao_variante.dart';

/// Camada de acesso a dados de produtos. Fala diretamente com o Supabase.
/// O isolamento por empresa é garantido pelo RLS no banco — não precisamos
/// (nem devemos) filtrar por empresa_id manualmente aqui nas consultas de
/// leitura, o Postgres já faz isso.
class ProdutoRepository {
  static const _selectComEstoque =
      '*, estoque(id, quantidade_atual, quantidade_minima, deposito_id)';

  /// Sugere um ciclo de recompra (dias) pra um produto ainda não salvo, com
  /// base em produtos parecidos já cadastrados que já têm ciclo definido
  /// (RPC `sugerir_ciclo_recompra_dias`) — mesma pesquisa por categoria já
  /// aplicada manualmente aos produtos existentes (ver
  /// [[gestor_recompra_estrutura_completa]]), generalizada: prioriza match
  /// por nome comercial (pega o ciclo já certo pra mesma linha/molécula,
  /// caso de antipulgas/vermífugos), senão por porte/fase/espécie, e quando
  /// há peso escala pela proporção dias/kg mediana do grupo encontrado (caso
  /// de ração, onde o ciclo é proporcional ao peso da embalagem). Categoria
  /// sem nenhum produto com ciclo (ex: Sachês, Petiscos — decisão deliberada
  /// de não ter ciclo automático) sempre volta null, sem sugestão.
  Future<int?> sugerirCicloRecompraDias({
    required String empresaId,
    required String categoria,
    String? porte,
    String? fase,
    String? especie,
    String? nomeComercial,
    double? peso,
  }) async {
    final resultado = await supabase.rpc('sugerir_ciclo_recompra_dias', params: {
      'p_empresa_id': empresaId,
      'p_categoria': categoria,
      'p_porte': porte,
      'p_fase': fase,
      'p_especie': especie,
      'p_nome_comercial': nomeComercial,
      'p_peso': peso,
    });
    return resultado as int?;
  }

  Future<List<Produto>> listar() async {
    // Kit ENTRA aqui de propósito (desde 09/09) — ganhou EAN interno e uma
    // linha de `estoque` sincronizada por trigger (`trg_sincronizar_estoque_kit_componentes`/
    // `trg_sincronizar_estoque_kits`, banco), então já chega com estoque
    // real calculado, não "0 quebrado" — é assim que cupom "Produtos
    // específicos" e o alerta de estoque baixo passam a enxergar kit,
    // sem precisar de nenhum código novo nessas duas telas.
    //
    // Paginado explicitamente: o Supabase corta em 1000 linhas por consulta,
    // e o catálogo passou disso (achado real 30/09, 1.009 produtos — os
    // últimos em ordem alfabética, ex: Vetmax, sumiam da lista e de toda
    // tela que usa o ProdutoProvider, inclusive o casamento da NF-e).
    const tamanhoPagina = 1000;
    final linhas = <Map<String, dynamic>>[];
    var pagina = 0;
    while (true) {
      final inicio = pagina * tamanhoPagina;
      final resultado = await supabase
          .from('produtos')
          .select(_selectComEstoque)
          .isFilter('deleted_at', null)
          .order('nome', ascending: true)
          // Desempate estável: nome repetido sem isso pode repetir ou sumir
          // entre uma página e outra.
          .order('id', ascending: true)
          .range(inicio, inicio + tamanhoPagina - 1);
      linhas.addAll(List<Map<String, dynamic>>.from(resultado));
      if (resultado.length < tamanhoPagina) break;
      pagina++;
    }

    return linhas.map(Produto.fromSupabase).toList();
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
  ///
  /// `exibir_no_catalogo` só vai no UPDATE com [gravarExibirNoCatalogo]
  /// (usuário mexeu no switch): quem cuida dele é o trigger
  /// `trg_sincronizar_visibilidade_catalogo` (estoque > 0 → aparece). Mandar
  /// o valor do objeto em memória desfazia o trigger — bug real 02/10:
  /// ajustar estoque 0→4 e salvar na mesma tela deixava o produto oculto,
  /// e ele saía inativo na planilha do iFood.
  Future<Produto> atualizar(Produto produto, {bool gravarExibirNoCatalogo = false}) async {
    if (produto.id == null) {
      throw ArgumentError('Produto sem id não pode ser atualizado');
    }

    final payload = produto.toSupabaseMap();
    if (!gravarExibirNoCatalogo) payload.remove('exibir_no_catalogo');

    final produtoAtualizado = await supabase
        .from('produtos')
        .update(payload)
        .eq('id', produto.id!)
        .select()
        .single();

    // NUNCA grava quantidade_atual aqui: o objeto vem de uma lista carregada
    // antes, e regravar o saldo dela "ressuscitava" unidades vendidas nesse
    // meio-tempo (bug real 01/10 — salvar custo na importação de NF-e ou
    // editar o preço desfazia baixas). Saldo só muda via [ajustarEstoque]
    // (motivo obrigatório + histórico) ou pelas rotinas de venda/entrada.
    // O saldo devolvido é o lido do banco agora, não o da memória.
    List<dynamic> estoqueAtualizado = [];
    if (produto.estoqueId != null) {
      estoqueAtualizado = await supabase
          .from('estoque')
          .update({'quantidade_minima': produto.estoqueMinimo})
          .eq('id', produto.estoqueId!)
          .select('id, quantidade_atual, quantidade_minima');
    }

    return Produto.fromSupabase({
      ...produtoAtualizado,
      'estoque': estoqueAtualizado,
    });
  }

  /// Ajuste manual de saldo (RPC `ajustar_estoque`): exige motivo e grava no
  /// histórico de movimentações. [quantidadeEsperada] é o saldo que o
  /// usuário estava vendo — se o banco mudou nesse meio-tempo (venda,
  /// entrada), a RPC recusa em vez de sobrescrever. Retorna o saldo final.
  Future<int> ajustarEstoque({
    required String produtoId,
    required int quantidadeNova,
    required String motivo,
    String? observacao,
    int? quantidadeEsperada,
  }) async {
    final resultado = await supabase.rpc('ajustar_estoque', params: {
      'p_produto_id': produtoId,
      'p_quantidade_nova': quantidadeNova,
      'p_motivo': motivo,
      'p_observacao': observacao,
      'p_quantidade_esperada': quantidadeEsperada,
    });
    return (resultado as num).toInt();
  }

  Future<List<MovimentacaoEstoque>> listarMovimentacoesEstoque(String produtoId, {int limite = 300}) async {
    final data = await supabase.rpc('listar_movimentacoes_estoque', params: {
      'p_produto_id': produtoId,
      'p_limite': limite,
    });
    return (data as List).map((r) => MovimentacaoEstoque.fromSupabase(r as Map<String, dynamic>)).toList();
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

  /// Sugestão de margem alvo pra um fracionado novo — reaproveita a última
  /// margem usada num produto do mesmo fabricante (fallback: mesma
  /// categoria) pra agilizar o cadastro em série de uma linha inteira.
  /// Sempre editável no diálogo, nunca aplicada sem o usuário ver.
  Future<double?> buscarMargemFracionadoSugerida({String? fabricante, required String categoria}) async {
    if (fabricante != null && fabricante.isNotEmpty) {
      final porFabricante = await supabase
          .from('produtos')
          .select('margem_alvo_fracionado')
          .eq('fabricante', fabricante)
          .not('margem_alvo_fracionado', 'is', null)
          .order('created_at', ascending: false)
          .limit(1);
      if ((porFabricante as List).isNotEmpty) {
        return (porFabricante.first['margem_alvo_fracionado'] as num?)?.toDouble();
      }
    }

    final porCategoria = await supabase
        .from('produtos')
        .select('margem_alvo_fracionado')
        .eq('categoria', categoria)
        .not('margem_alvo_fracionado', 'is', null)
        .order('created_at', ascending: false)
        .limit(1);
    if ((porCategoria as List).isNotEmpty) {
      return (porCategoria.first['margem_alvo_fracionado'] as num?)?.toDouble();
    }
    return null;
  }

  /// Liga dois produtos já existentes como embalagem fechada (pai) + unidade
  /// fracionada (filho) — mesmo vínculo do "Fracionar em unidade menor", sem
  /// criar produto novo. Tudo numa transação no banco (RPC
  /// `vincular_fracionamento_existente`): valida, liga, alinha custo/preço do
  /// filho e grava [estoqueFilho] (contagem real informada pelo usuário) —
  /// o estoque do pai é recalculado pelo trigger a partir dele.
  Future<void> vincularFracionamentoExistente({
    required String paiId,
    required String filhoId,
    required int fator,
    required int estoqueFilho,
    double? margemAlvo,
  }) async {
    await supabase.rpc('vincular_fracionamento_existente', params: {
      'p_pai_id': paiId,
      'p_filho_id': filhoId,
      'p_fator': fator,
      'p_estoque_filho': estoqueFilho,
      'p_margem_alvo': margemAlvo,
    });
  }

  Future<List<Produto>> buscarPorIds(List<String> ids) async {
    final data = await supabase.from('produtos').select(_selectComEstoque).inFilter('id', ids);
    return (data as List).map((row) => Produto.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  /// Tira/volta o produto da sugestão de compra. [naoSugerir] = não vai mais
  /// comprar; [pausarAte] = pausa até a data (volta sozinho). Os dois nulos/
  /// false = volta a ser sugerido. Update só desses 2 campos.
  Future<void> definirSugestaoCompra(String produtoId, {bool naoSugerir = false, DateTime? pausarAte}) async {
    await supabase.from('produtos').update({
      'nao_sugerir_compra': naoSugerir,
      'sugestao_compra_pausada_ate': pausarAte == null
          ? null
          : '${pausarAte.year.toString().padLeft(4, '0')}-${pausarAte.month.toString().padLeft(2, '0')}-${pausarAte.day.toString().padLeft(2, '0')}',
    }).eq('id', produtoId);
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

  /// Produtos com estoque sem venda há mais de [dias] — ver RPC
  /// `produtos_estoque_parado` (granel conta junto, kits ficam fora).
  Future<List<EstoqueParado>> listarEstoqueParado({int dias = 90}) async {
    final data = await supabase.rpc('analise_estoque_parado', params: {'p_dias': dias});
    return (data as List).map((r) => EstoqueParado.fromSupabase(r as Map<String, dynamic>)).toList();
  }

  /// O que foi feito com um produto parado — a análise mostra quanto vendeu
  /// desde a última ação.
  Future<void> registrarAcaoEstoqueParado({
    required String produtoId,
    required String acao,
    String? detalhe,
    int? quantidade,
    double? preco,
  }) async {
    await supabase.from('estoque_parado_acoes').insert({
      'produto_id': produtoId,
      'acao': acao,
      'detalhe': detalhe,
      'quantidade_no_momento': quantidade,
      'preco_no_momento': preco,
    });
  }

  Future<List<ResultadoAcao>> listarResultadoAcoes() async {
    final data = await supabase.rpc('resultado_acoes_estoque_parado');
    return (data as List).map((r) => ResultadoAcao.fromSupabase(r as Map<String, dynamic>)).toList();
  }

  Future<List<({String nome, String? telefone, int vezes, DateTime ultimaCompra})>> clientesQueCompraram(
      String produtoId) async {
    final data = await supabase.rpc('clientes_que_compraram_produto', params: {'p_produto_id': produtoId});
    return [
      for (final r in (data as List).cast<Map<String, dynamic>>())
        (
          nome: r['nome'] as String? ?? 'Cliente',
          telefone: r['telefone'] as String?,
          vezes: (r['vezes'] as num).toInt(),
          ultimaCompra: DateTime.parse(r['ultima_compra'] as String).toLocal(),
        ),
    ];
  }

  /// Preço promocional por produto (null remove a promoção) — valor
  /// diferente pra cada um, então um UPDATE estreito por produto, em
  /// paralelo. Retorna os ids que falharam.
  Future<List<String>> aplicarPrecoPromocionalEmMassa(Map<String, double?> promocionalPorId) async {
    final falhas = <String>[];
    await Future.wait(promocionalPorId.entries.map((entrada) async {
      try {
        await supabase.from('produtos').update({'preco_promocional': entrada.value}).eq('id', entrada.key);
      } catch (_) {
        falhas.add(entrada.key);
      }
    }));
    return falhas;
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
