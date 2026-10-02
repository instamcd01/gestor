import '../config/supabase_config.dart';

/// Uma alteração de preço (`historico_precos`, gravado por trigger em
/// `produtos` e `produto_canal` — pega mudança de qualquer origem).
class AlteracaoPreco {
  final String id;

  /// 'preco' | 'preco_promocional' | 'custo' | 'preco_canal'
  final String campo;
  final String? marketplace;
  final double? valorAntigo;
  final double? valorNovo;

  /// 'manual' | 'reversao' | 'auditoria_ifood' | outro valor de app.preco_origem.
  final String? origem;
  final DateTime alteradoEm;

  const AlteracaoPreco({
    required this.id,
    required this.campo,
    required this.marketplace,
    required this.valorAntigo,
    required this.valorNovo,
    required this.origem,
    required this.alteradoEm,
  });

  String get rotuloCampo => switch (campo) {
        'preco' => 'Preço da loja',
        'preco_promocional' => 'Preço promocional',
        'custo' => 'Custo',
        'preco_canal' => 'Preço ${marketplace ?? 'marketplace'}',
        _ => campo,
      };

  /// Promocional pode voltar pra "sem promoção" (null); os outros precisam
  /// de um valor anterior.
  bool get podeReverter => campo == 'preco_promocional' || valorAntigo != null;

  factory AlteracaoPreco.fromSupabase(Map<String, dynamic> row) => AlteracaoPreco(
        id: row['id'] as String,
        campo: row['campo'] as String,
        marketplace: (row['marketplaces'] as Map<String, dynamic>?)?['nome'] as String?,
        valorAntigo: (row['valor_antigo'] as num?)?.toDouble(),
        valorNovo: (row['valor_novo'] as num?)?.toDouble(),
        origem: row['origem'] as String?,
        alteradoEm: DateTime.parse(row['alterado_em'] as String).toLocal(),
      );
}

class HistoricoPrecosRepository {
  Future<List<AlteracaoPreco>> listar(String produtoId, {int limite = 300}) async {
    final data = await supabase
        .from('historico_precos')
        .select('id, campo, valor_antigo, valor_novo, origem, alterado_em, marketplaces(nome)')
        .eq('produto_id', produtoId)
        .order('alterado_em', ascending: false)
        .limit(limite);
    return (data as List).map((r) => AlteracaoPreco.fromSupabase(r as Map<String, dynamic>)).toList();
  }

  /// Volta o campo pro valor anterior (RPC `reverter_alteracao_preco`) — o
  /// preço de marketplace segue pra lá pela sincronização normal.
  Future<void> reverter(String historicoId) async {
    await supabase.rpc('reverter_alteracao_preco', params: {'p_historico_id': historicoId});
  }
}
