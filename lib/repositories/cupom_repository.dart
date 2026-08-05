import '../config/supabase_config.dart';
import '../models/cupom.dart';

class CupomRepository {
  Future<List<Cupom>> listar() async {
    final data = await supabase
        .from('cupons')
        .select('*, clientes(nome), usuarios(nome)')
        .order('created_at', ascending: false);

    return (data as List).map((row) => Cupom.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  Future<Cupom> criar(Cupom cupom, {required String empresaId}) async {
    final row = await supabase
        .from('cupons')
        .insert({...cupom.toSupabaseMap(), 'empresa_id': empresaId})
        .select()
        .single();
    return Cupom.fromSupabase(row);
  }

  Future<void> atualizar(Cupom cupom) async {
    if (cupom.id == null) {
      throw ArgumentError('Cupom sem id não pode ser atualizado');
    }
    await supabase.from('cupons').update(cupom.toSupabaseMap()).eq('id', cupom.id!);
  }

  /// Cupom não é excluído de verdade — cupons_uso referencia o cupom_id
  /// pra métricas/histórico, apagar quebraria isso. Desativar impede
  /// novos usos sem perder o rastro dos já feitos.
  Future<void> desativar(String cupomId) async {
    await supabase.from('cupons').update({'ativo': false}).eq('id', cupomId);
  }

  Future<void> ativar(String cupomId) async {
    await supabase.from('cupons').update({'ativo': true}).eq('id', cupomId);
  }

  /// Produtos específicos de um cupom com escopoTipo=produtos.
  Future<List<String>> listarProdutoIds(String cupomId) async {
    final data = await supabase.from('cupons_produtos').select('produto_id').eq('cupom_id', cupomId);
    return (data as List).map((row) => row['produto_id'] as String).toList();
  }

  Future<void> definirProdutos(String cupomId, List<String> produtoIds) async {
    await supabase.from('cupons_produtos').delete().eq('cupom_id', cupomId);
    if (produtoIds.isEmpty) return;
    await supabase
        .from('cupons_produtos')
        .insert(produtoIds.map((id) => {'cupom_id': cupomId, 'produto_id': id}).toList());
  }

  /// Mesma função Postgres usada pelo site (validar_cupom) — fonte única
  /// de validação, nunca recalcula o desconto no Dart.
  Future<ResultadoValidacaoCupom> validar({
    required String empresaId,
    required String codigo,
    String? clienteId,
    required double subtotal,
    required List<Map<String, dynamic>> itens,
  }) async {
    final row = await supabase
        .rpc('validar_cupom', params: {
          'p_empresa_id': empresaId,
          'p_codigo': codigo,
          'p_cliente_id': clienteId,
          'p_subtotal': subtotal,
          'p_itens': itens,
        })
        .single();
    return ResultadoValidacaoCupom.fromSupabase(row);
  }

  /// Uso de cupons num período, pra tela de métricas — uma linha por
  /// resgate (cupons_uso), com o código já resolvido via join.
  Future<List<({String cupomId, String codigo, double valorDesconto, DateTime data})>> buscarUsos({
    required DateTime desde,
  }) async {
    final data = await supabase
        .from('cupons_uso')
        .select('cupom_id, valor_desconto_aplicado, created_at, cupons(codigo)')
        .gte('created_at', desde.toIso8601String());

    return (data as List).map((row) {
      final cupomInfo = row['cupons'] as Map<String, dynamic>?;
      return (
        cupomId: row['cupom_id'] as String,
        codigo: cupomInfo?['codigo']?.toString() ?? '—',
        valorDesconto: (row['valor_desconto_aplicado'] as num?)?.toDouble() ?? 0,
        data: DateTime.parse(row['created_at'] as String),
      );
    }).toList();
  }
}
