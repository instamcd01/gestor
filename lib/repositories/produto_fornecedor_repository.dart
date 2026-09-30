import '../config/supabase_config.dart';
import '../models/produto_fornecedor.dart';

/// Vínculos produto↔fornecedor (`produto_fornecedores`) e suas faixas de
/// desconto por quantidade (`faixas_desconto_produto_fornecedor`).
class ProdutoFornecedorRepository {
  static const _selectCompleto = '*, fornecedor:fornecedores(id, nome), faixas_desconto_produto_fornecedor(*)';

  Future<List<ProdutoFornecedor>> listarPorProduto(String produtoId) async {
    final data = await supabase
        .from('produto_fornecedores')
        .select(_selectCompleto)
        .eq('produto_id', produtoId)
        .order('principal', ascending: false);

    return (data as List).map((row) => ProdutoFornecedor.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  /// Vínculos de vários produtos de uma vez, agrupados por `produto_id` —
  /// evita 1 chamada por produto (ex: tela de Sugestão de Compra, que
  /// antes fazia N chamadas sequenciais, uma por produto sugerido).
  Future<Map<String, List<ProdutoFornecedor>>> listarPorProdutos(List<String> produtoIds) async {
    if (produtoIds.isEmpty) return {};
    final data = await supabase
        .from('produto_fornecedores')
        .select(_selectCompleto)
        .inFilter('produto_id', produtoIds)
        .order('principal', ascending: false);

    final porProduto = <String, List<ProdutoFornecedor>>{};
    for (final row in (data as List)) {
      final vinculo = ProdutoFornecedor.fromSupabase(row as Map<String, dynamic>);
      porProduto.putIfAbsent(vinculo.produtoId, () => []).add(vinculo);
    }
    return porProduto;
  }

  /// Todos os vínculos de um fornecedor, com o nome/código do produto
  /// embutido — usado pela tela de desvincular em massa (não precisa
  /// carregar a lista de faixas de desconto aqui, é só listagem).
  Future<List<ProdutoFornecedor>> listarPorFornecedor(String fornecedorId) async {
    final data = await supabase
        .from('produto_fornecedores')
        .select('*, produto:produtos(nome, codigo_barras)')
        .eq('fornecedor_id', fornecedorId)
        .order('id');

    final vinculos = (data as List).map((row) => ProdutoFornecedor.fromSupabase(row as Map<String, dynamic>)).toList();
    vinculos.sort((a, b) => (a.produtoNome ?? '').compareTo(b.produtoNome ?? ''));
    return vinculos;
  }

  /// Produto -> nomes dos fornecedores que já compram esse produto,
  /// considerando TODOS os fornecedores (não só um específico) — usado no
  /// seletor de "vincular produtos" pra avisar quando um produto já tem
  /// fornecedor antes de vincular de novo sem querer. `excetoFornecedorId`
  /// tira o fornecedor atual do resultado (ele já é excluído da lista de
  /// candidatos por outro caminho, mas filtra aqui também por segurança).
  Future<Map<String, List<String>>> listarFornecedoresPorProduto(
    String empresaId, {
    String? excetoFornecedorId,
  }) async {
    var query = supabase
        .from('produto_fornecedores')
        .select('produto_id, fornecedor:fornecedores(nome)')
        .eq('empresa_id', empresaId);
    if (excetoFornecedorId != null) {
      query = query.neq('fornecedor_id', excetoFornecedorId);
    }
    final data = await query;

    final mapa = <String, List<String>>{};
    for (final row in (data as List)) {
      final produtoId = row['produto_id'] as String;
      final nome = (row['fornecedor'] as Map?)?['nome'] as String?;
      if (nome == null) continue;
      (mapa[produtoId] ??= []).add(nome);
    }
    return mapa;
  }

  /// Remove vários vínculos de uma vez — usado pela tela de desvincular em
  /// massa. Continua tentando os demais mesmo se um id falhar, devolvendo
  /// os que não puderam ser removidos.
  Future<List<String>> excluirEmLote(List<String> vinculoIds) async {
    final falharam = <String>[];
    for (final id in vinculoIds) {
      try {
        await excluir(id);
      } catch (_) {
        falharam.add(id);
      }
    }
    return falharam;
  }

  Future<ProdutoFornecedor> criar(ProdutoFornecedor vinculo, {required String empresaId}) async {
    if (vinculo.principal) {
      await _limparPrincipal(vinculo.produtoId);
    }
    final row = await supabase
        .from('produto_fornecedores')
        .insert({...vinculo.toSupabaseMap(), 'empresa_id': empresaId})
        .select(_selectCompleto)
        .single();
    final vinculoId = row['id'] as String;

    if (vinculo.faixasDesconto.isNotEmpty) {
      await supabase.from('faixas_desconto_produto_fornecedor').insert(
            vinculo.faixasDesconto.map((f) => {...f.toSupabaseMap(), 'produto_fornecedor_id': vinculoId}).toList(),
          );
    }

    return await _buscarPorId(vinculoId);
  }

  Future<ProdutoFornecedor> atualizar(ProdutoFornecedor vinculo) async {
    if (vinculo.id == null) {
      throw ArgumentError('Vínculo sem id não pode ser atualizado');
    }
    if (vinculo.principal) {
      await _limparPrincipal(vinculo.produtoId, exceto: vinculo.id);
    }
    await supabase.from('produto_fornecedores').update(vinculo.toSupabaseMap()).eq('id', vinculo.id!);

    // Substitui as faixas inteiras — mais simples que diff item a item, e
    // a lista costuma ser pequena (poucas faixas por fornecedor).
    await supabase.from('faixas_desconto_produto_fornecedor').delete().eq('produto_fornecedor_id', vinculo.id!);
    if (vinculo.faixasDesconto.isNotEmpty) {
      await supabase.from('faixas_desconto_produto_fornecedor').insert(
            vinculo.faixasDesconto.map((f) => {...f.toSupabaseMap(), 'produto_fornecedor_id': vinculo.id}).toList(),
          );
    }

    return await _buscarPorId(vinculo.id!);
  }

  /// Marca um vínculo já existente como principal (desmarca os demais do
  /// mesmo produto) sem precisar recarregar/reenviar o vínculo inteiro —
  /// usado pelo atalho "Tornar principal" na Sugestão de Compra, quando o
  /// usuário decide trocar de fornecedor por causa da comparação de preço.
  Future<void> marcarComoPrincipal(String vinculoId, String produtoId) async {
    await _limparPrincipal(produtoId, exceto: vinculoId);
    await supabase.from('produto_fornecedores').update({'principal': true}).eq('id', vinculoId);
  }

  Future<void> excluir(String vinculoId) async {
    await supabase.from('produto_fornecedores').delete().eq('id', vinculoId);
  }

  /// Chamado ao importar uma NF-e: mantém o vínculo produto↔fornecedor
  /// sempre refletindo a compra real, sem exigir cadastro manual. Se já
  /// existe vínculo com esse fornecedor pro produto, só atualiza o custo
  /// (preço mais recente pago); se não existe, cria um novo — marcando
  /// como principal só se for o primeiro fornecedor desse produto (não
  /// sobrescreve uma escolha manual de principal já feita).
  Future<void> vincularDeEntrada({
    required String produtoId,
    required String fornecedorId,
    required String empresaId,
    required double custoUnitario,
  }) async {
    if (custoUnitario <= 0) return;
    final existentes = await listarPorProduto(produtoId);
    final match = existentes.where((v) => v.fornecedorId == fornecedorId).toList();

    if (match.isNotEmpty) {
      final vinculo = match.first;
      if (vinculo.id != null && vinculo.custoUnitario != custoUnitario) {
        await supabase.from('produto_fornecedores').update({'custo_unitario': custoUnitario}).eq('id', vinculo.id!);
      }
      return;
    }

    await criar(
      ProdutoFornecedor(
        produtoId: produtoId,
        fornecedorId: fornecedorId,
        custoUnitario: custoUnitario,
        principal: existentes.isEmpty,
      ),
      empresaId: empresaId,
    );
  }

  /// Vincula o código interno do fornecedor a um produto já cadastrado —
  /// atualiza o vínculo existente entre eles se já houver um (sem mexer no
  /// custo já cadastrado, que continua sendo mantido manualmente), ou cria
  /// um vínculo novo usando [custoUnitarioFallback] (o preço lido do PDF)
  /// como ponto de partida quando esse produto ainda nunca foi vinculado a
  /// esse fornecedor. Usado pra "ensinar" a leitura automática de PDF de
  /// cotação (ver `parseCotacaoTargetSistemasTabela`): da próxima vez que a
  /// mesma cotação desse fornecedor vier, o item já casa sozinho pelo
  /// código, sem precisar vincular nada de novo.
  ///
  /// Libera esse código de qualquer OUTRO produto do mesmo fornecedor que
  /// já estivesse com ele antes de gravar aqui — sem isso, corrigir um
  /// vínculo feito errado (ex: escolheu o produto errado na busca) deixaria
  /// os dois produtos "donos" do mesmo código, e o próximo PDF lido casaria
  /// com um dos dois de forma imprevisível. Corrigir um vínculo errado é só
  /// vincular esse mesmo código de novo, agora no produto certo.
  Future<ProdutoFornecedor> vincularCodigoFornecedor({
    required String produtoId,
    required String fornecedorId,
    required String empresaId,
    required String codigo,
    required double custoUnitarioFallback,
  }) async {
    await supabase
        .from('produto_fornecedores')
        .update({'codigo_produto_fornecedor': null})
        .eq('fornecedor_id', fornecedorId)
        .eq('codigo_produto_fornecedor', codigo)
        .neq('produto_id', produtoId);

    final existentes = await listarPorProduto(produtoId);
    final match = existentes.where((v) => v.fornecedorId == fornecedorId).toList();
    if (match.isNotEmpty) {
      final vinculo = match.first;
      await supabase.from('produto_fornecedores').update({'codigo_produto_fornecedor': codigo}).eq('id', vinculo.id!);
      return await _buscarPorId(vinculo.id!);
    }
    return await criar(
      ProdutoFornecedor(
        produtoId: produtoId,
        fornecedorId: fornecedorId,
        custoUnitario: custoUnitarioFallback,
        codigoProdutoFornecedor: codigo,
        principal: existentes.isEmpty,
      ),
      empresaId: empresaId,
    );
  }

  /// Grava quantas unidades vêm em 1 unidade faturada na NF-e desse
  /// fornecedor (ex.: caixa com 12) — ensinado na importação de NF-e, pra
  /// próxima nota já converter caixa→unidade sozinha. 1 ou menos = sem
  /// conversão (grava null). Só atualiza vínculo já existente: na
  /// importação ele sempre acabou de ser criado/atualizado antes disso.
  Future<void> definirUnidadesPorEmbalagem({
    required String produtoId,
    required String fornecedorId,
    required int unidades,
  }) async {
    await supabase
        .from('produto_fornecedores')
        .update({'unidades_por_embalagem': unidades > 1 ? unidades : null})
        .eq('produto_id', produtoId)
        .eq('fornecedor_id', fornecedorId);
  }

  /// Move um vínculo inteiro (custo, código do fornecedor, faixas de
  /// desconto) pra outro produto — usado quando o vínculo foi feito no
  /// produto errado (ex: veio de uma cotação lida automaticamente e o
  /// usuário escolheu o produto errado na busca, ver
  /// `ConferenciaEspelhoScreen._vincularExistente`). Não dá só pra fazer
  /// update do `produto_id`: a constraint única é (produto_id,
  /// fornecedor_id), então se o produto novo já comprar desse fornecedor,
  /// o vínculo antigo é fundido no que já existe (o código do fornecedor
  /// prevalece, mas o custo/faixas do vínculo já existente no destino são
  /// mantidos — presumidamente mais atualizados) em vez de duplicar.
  Future<ProdutoFornecedor> trocarProdutoDoVinculo({
    required ProdutoFornecedor vinculoAtual,
    required String novoProdutoId,
    required String empresaId,
  }) async {
    if (vinculoAtual.produtoId == novoProdutoId) return vinculoAtual;

    final existentesNovo = await listarPorProduto(novoProdutoId);
    final jaTinha = existentesNovo.where((v) => v.fornecedorId == vinculoAtual.fornecedorId).toList();

    final ProdutoFornecedor resultado;
    if (jaTinha.isNotEmpty) {
      final destino = jaTinha.first;
      resultado = await atualizar(ProdutoFornecedor(
        id: destino.id,
        produtoId: destino.produtoId,
        fornecedorId: destino.fornecedorId,
        custoUnitario: destino.custoUnitario,
        codigoProdutoFornecedor: vinculoAtual.codigoProdutoFornecedor ?? destino.codigoProdutoFornecedor,
        multiploCompra: destino.multiploCompra,
        unidadesPorEmbalagem: vinculoAtual.unidadesPorEmbalagem ?? destino.unidadesPorEmbalagem,
        principal: destino.principal,
        ativo: destino.ativo,
        faixasDesconto: destino.faixasDesconto,
      ));
    } else {
      resultado = await criar(
        ProdutoFornecedor(
          produtoId: novoProdutoId,
          fornecedorId: vinculoAtual.fornecedorId,
          custoUnitario: vinculoAtual.custoUnitario,
          codigoProdutoFornecedor: vinculoAtual.codigoProdutoFornecedor,
          multiploCompra: vinculoAtual.multiploCompra,
          unidadesPorEmbalagem: vinculoAtual.unidadesPorEmbalagem,
          // Não herda "principal" — decidir isso é do produto de destino,
          // não queremos desmarcar sem querer o principal certo dele.
          faixasDesconto: vinculoAtual.faixasDesconto,
        ),
        empresaId: empresaId,
      );
    }

    await excluir(vinculoAtual.id!);
    return resultado;
  }

  Future<ProdutoFornecedor> _buscarPorId(String id) async {
    final row = await supabase.from('produto_fornecedores').select(_selectCompleto).eq('id', id).single();
    return ProdutoFornecedor.fromSupabase(row);
  }

  /// O índice único parcial (`produto_fornecedores_unico_principal`) só
  /// permite 1 linha com `principal = true` por produto — precisa
  /// desmarcar as outras antes de marcar uma nova, senão o insert/update
  /// falha com violação de unicidade.
  Future<void> _limparPrincipal(String produtoId, {String? exceto}) async {
    var query = supabase.from('produto_fornecedores').update({'principal': false}).eq('produto_id', produtoId);
    if (exceto != null) {
      query = query.neq('id', exceto);
    }
    await query;
  }
}
