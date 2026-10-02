import '../config/supabase_config.dart';
import '../models/checklist_estoque.dart';

class ChecklistEstoqueRepository {
  // Supabase corta em 1000 linhas por consulta — o catálogo já passa de 970.
  static const _tamanhoPagina = 1000;

  Future<List<Map<String, dynamic>>> _todasPaginas(
    Future<List<dynamic>> Function(int de, int ate) consulta,
  ) async {
    final linhas = <Map<String, dynamic>>[];
    for (var de = 0;; de += _tamanhoPagina) {
      final pagina = await consulta(de, de + _tamanhoPagina - 1);
      linhas.addAll(pagina.cast<Map<String, dynamic>>());
      if (pagina.length < _tamanhoPagina) return linhas;
    }
  }

  Future<List<ChecklistEstoque>> listar() async {
    final data = await supabase.from('checklists_estoque').select().order('iniciado_em', ascending: false);
    return (data as List).map((r) => ChecklistEstoque.fromSupabase(r as Map<String, dynamic>)).toList();
  }

  Future<ChecklistEstoque> iniciar(String referencia) async {
    final data = await supabase.from('checklists_estoque').insert({'referencia': referencia}).select().single();
    return ChecklistEstoque.fromSupabase(data);
  }

  Future<void> concluir(String checklistId) async {
    await supabase.from('checklists_estoque').update({
      'concluido_em': DateTime.now().toUtc().toIso8601String(),
      'concluido_por': supabase.auth.currentUser?.id,
    }).eq('id', checklistId);
  }

  /// Reabre um checklist concluído por engano (só se não houver outro aberto
  /// — o índice único no banco recusa).
  Future<void> reabrir(String checklistId) async {
    await supabase
        .from('checklists_estoque')
        .update({'concluido_em': null, 'concluido_por': null}).eq('id', checklistId);
  }

  Future<Map<String, ChecklistItem>> listarItens(String checklistId) async {
    final linhas = await _todasPaginas((de, ate) => supabase
        .from('checklist_estoque_itens')
        .select()
        .eq('checklist_id', checklistId)
        .order('id')
        .range(de, ate));
    return {for (final r in linhas) r['produto_id'] as String: ChecklistItem.fromSupabase(r)};
  }

  /// Validade mais próxima conferida por produto (null = conferido sem
  /// validade, ex: acessório). Produto ausente do mapa = nunca conferido.
  Future<Map<String, DateTime?>> listarValidades() async {
    final linhas = await _todasPaginas((de, ate) => supabase
        .from('produtos_validade')
        .select('produto_id, validade')
        .order('produto_id')
        .range(de, ate));
    return {
      for (final r in linhas)
        r['produto_id'] as String: r['validade'] != null ? DateTime.parse(r['validade'] as String) : null,
    };
  }

  /// Saldo lido do banco agora — a lista em memória pode estar velha
  /// (venda no meio da contagem) e a RPC recusa se não bater.
  Future<int> saldoAtual(String produtoId) async {
    final data =
        await supabase.from('estoque').select('quantidade_atual').eq('produto_id', produtoId).maybeSingle();
    return (data?['quantidade_atual'] as num?)?.toInt() ?? 0;
  }

  Future<ChecklistItem> conferir({
    required String checklistId,
    required String produtoId,
    required int quantidadeContada,
    required int quantidadeEsperada,
    required DateTime? validade,
  }) async {
    final data = await supabase.rpc('conferir_item_checklist', params: {
      'p_checklist_id': checklistId,
      'p_produto_id': produtoId,
      'p_quantidade_contada': quantidadeContada,
      'p_quantidade_esperada': quantidadeEsperada,
      'p_validade': validade == null
          ? null
          : '${validade.year}-${validade.month.toString().padLeft(2, '0')}-${validade.day.toString().padLeft(2, '0')}',
    });
    return ChecklistItem.fromSupabase(data as Map<String, dynamic>);
  }
}
