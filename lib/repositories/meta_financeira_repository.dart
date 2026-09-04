import '../config/supabase_config.dart';
import '../models/meta_financeira.dart';

class MetaFinanceiraRepository {
  Future<MetaFinanceira?> buscar({required String periodoTipo, required DateTime periodoInicio}) async {
    final row = await supabase
        .from('metas_financeiras')
        .select()
        .eq('periodo_tipo', periodoTipo)
        .eq('periodo_inicio', periodoInicio.toIso8601String().split('T').first)
        .maybeSingle();
    return row == null ? null : MetaFinanceira.fromSupabase(row);
  }

  /// `upsert`, não `insert` — o `unique (empresa_id, periodo_tipo,
  /// periodo_inicio)` faria um segundo `insert` pro mesmo período estourar
  /// 23505 ao reeditar uma meta já definida.
  Future<void> salvar(MetaFinanceira meta, {required String empresaId, String? criadoPor}) async {
    await supabase.from('metas_financeiras').upsert(
      {
        ...meta.toSupabaseMap(),
        'empresa_id': empresaId,
        'criado_por': criadoPor,
      },
      onConflict: 'empresa_id,periodo_tipo,periodo_inicio',
    );
  }

  /// "Realizado" = soma de `pedidos.valor_total` só com `status =
  /// 'entregue'` — mesma definição de "venda real" já usada em
  /// `sugestoes_pedido_compra` (nunca conta pedido cancelado/pendente).
  /// `fim` é exclusivo (`< fim`, nunca `<= fim`).
  Future<double> buscarRealizado({required DateTime inicio, required DateTime fim}) async {
    final data = await supabase
        .from('pedidos')
        .select('valor_total')
        .eq('status', 'entregue')
        .gte('created_at', inicio.toIso8601String())
        .lt('created_at', fim.toIso8601String());

    return (data as List).fold<double>(0, (soma, row) => soma + ((row['valor_total'] as num?)?.toDouble() ?? 0));
  }
}
