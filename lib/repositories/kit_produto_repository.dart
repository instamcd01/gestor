import '../config/supabase_config.dart';
import '../models/kit_produto.dart';

/// Camada de acesso a dados de kits (combos de produtos). Kits são linhas
/// normais de `produtos` (`eh_kit = true`) — o isolamento por empresa
/// continua vindo do RLS, igual a `ProdutoRepository`.
class KitProdutoRepository {
  /// Duas idas ao banco em vez de um embed aninhado só: `kit_componentes`
  /// tem 2 FKs pra `produtos` (kit_id e componente_produto_id), o que torna
  /// o embed do Supabase ambíguo sem hint de constraint — mais simples e
  /// menos frágil resolver em 2 passos do que depender do nome exato da
  /// constraint gerada pelo Postgres.
  Future<List<KitProduto>> listar() async {
    final kitsData = await supabase
        .from('produtos')
        .select()
        .eq('eh_kit', true)
        .isFilter('deleted_at', null)
        .order('nome', ascending: true);

    final kitIds = (kitsData as List).map((r) => r['id'] as String).toList();
    if (kitIds.isEmpty) return [];

    final componentesData = await supabase
        .from('kit_componentes')
        .select('kit_id, componente_produto_id, quantidade, produtos:componente_produto_id(nome, preco, custo)')
        .inFilter('kit_id', kitIds);

    final componentesPorKit = <String, List<ComponenteKit>>{};
    for (final row in (componentesData as List)) {
      final kitId = row['kit_id'] as String;
      final produtoComponente = row['produtos'] as Map<String, dynamic>?;
      (componentesPorKit[kitId] ??= []).add(ComponenteKit(
        produtoId: row['componente_produto_id'] as String,
        nome: produtoComponente?['nome']?.toString() ?? '',
        preco: (produtoComponente?['preco'] as num?)?.toDouble() ?? 0.0,
        custo: (produtoComponente?['custo'] as num?)?.toDouble() ?? 0.0,
        quantidade: (row['quantidade'] as num).toInt(),
      ));
    }

    final kits = (kitsData)
        .map((row) => KitProduto.fromSupabase(
              row as Map<String, dynamic>,
              componentes: componentesPorKit[row['id']] ?? const [],
            ))
        .toList();

    // Estoque de cada kit já vem pronto de `estoque` — sincronizado por
    // trigger toda vez que o estoque de algum componente muda (ou os
    // componentes do kit são editados), não precisa mais recalcular aqui
    // chamando `estoque_disponivel_kit` uma vez por kit.
    final estoqueData = await supabase
        .from('estoque')
        .select('produto_id, quantidade_atual, quantidade_minima')
        .inFilter('produto_id', kitIds);
    final estoquePorKit = {
      for (final row in (estoqueData as List)) row['produto_id'] as String: row as Map<String, dynamic>,
    };

    return [
      for (final kit in kits)
        kit.comEstoque(
          disponivel: (estoquePorKit[kit.id]?['quantidade_atual'] as num?)?.toInt() ?? 0,
          minimo: (estoquePorKit[kit.id]?['quantidade_minima'] as num?)?.toInt() ?? 0,
        ),
    ];
  }

  Future<KitProduto> criar(KitProduto kit, {required String empresaId}) async {
    final kitInserido = await supabase
        .from('produtos')
        .insert({...kit.toSupabaseMap(), 'empresa_id': empresaId, 'eh_kit': true})
        .select()
        .single();

    final kitId = kitInserido['id'] as String;

    if (kit.componentes.isNotEmpty) {
      await supabase.from('kit_componentes').insert([
        for (final c in kit.componentes)
          {
            'empresa_id': empresaId,
            'kit_id': kitId,
            'componente_produto_id': c.produtoId,
            'quantidade': c.quantidade,
          },
      ]);
    }

    return KitProduto.fromSupabase(kitInserido, componentes: kit.componentes);
  }

  Future<void> atualizar(KitProduto kit, {required String empresaId}) async {
    if (kit.id == null) {
      throw ArgumentError('Kit sem id não pode ser atualizado');
    }

    await supabase.from('produtos').update(kit.toSupabaseMap()).eq('id', kit.id!);

    // Substitui a lista inteira de componentes — mais simples e seguro que
    // diff incremental pra um formulário pequeno (poucos componentes por kit).
    await supabase.from('kit_componentes').delete().eq('kit_id', kit.id!);
    if (kit.componentes.isNotEmpty) {
      await supabase.from('kit_componentes').insert([
        for (final c in kit.componentes)
          {
            'empresa_id': empresaId,
            'kit_id': kit.id,
            'componente_produto_id': c.produtoId,
            'quantidade': c.quantidade,
          },
      ]);
    }
  }

  /// Estoque mínimo (alerta) do kit — mora na linha de `estoque`
  /// sincronizada por trigger, não em `produtos`. A trigger nunca
  /// sobrescreve esse valor ao ressincronizar `quantidade_atual`, então
  /// isso é seguro de chamar a qualquer momento (o kit já tem uma linha de
  /// `estoque` desde que o 1º componente foi vinculado).
  Future<void> atualizarEstoqueMinimo(String kitId, int minimo) async {
    await supabase.from('estoque').update({'quantidade_minima': minimo}).eq('produto_id', kitId);
  }

  /// Exclusão lógica — mesmo padrão de `ProdutoRepository.excluir`.
  Future<void> excluir(String kitId) async {
    await supabase.from('produtos').update({'deleted_at': DateTime.now().toIso8601String()}).eq('id', kitId);
  }
}
