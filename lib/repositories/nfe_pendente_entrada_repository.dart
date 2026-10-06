import '../config/supabase_config.dart';

/// Uma NF-e ja baixada da Sefaz pelo poll de fundo (nfe-sefaz-service) mas
/// que ainda nao virou entrada de estoque no Gestor.
class NfePendenteEntrada {
  final String chave;
  final String xml;
  final DateTime recebidoEm;

  NfePendenteEntrada({required this.chave, required this.xml, required this.recebidoEm});

  factory NfePendenteEntrada.fromSupabase(Map<String, dynamic> row) {
    return NfePendenteEntrada(
      chave: row['chave'] as String,
      xml: row['xml'] as String,
      recebidoEm: DateTime.parse(row['recebido_em'] as String),
    );
  }
}

/// Lê a view `nfe_pendentes_entrada` (nfe_cache_distribuicao menos o que já
/// virou `entradas` por chave) — mesma fonte que a busca por chave/scan já
/// consulta primeiro no serviço, só que aqui pra listar tudo de uma vez, sem
/// precisar saber a chave de antemão.
class NfePendenteEntradaRepository {
  Future<List<NfePendenteEntrada>> listar() async {
    final data = await supabase.from('nfe_pendentes_entrada').select().order('recebido_em', ascending: false);
    return (data as List).map((row) => NfePendenteEntrada.fromSupabase(row as Map<String, dynamic>)).toList();
  }

  /// Tira da lista uma nota que não é mercadoria de revenda (equipamento,
  /// material de uso/consumo...). Com [lancarDespesa], cria junto uma
  /// despesa já paga — valor, fornecedor e número saem do XML no servidor,
  /// não do que o app manda.
  Future<void> dispensar({
    required String chave,
    required bool lancarDespesa,
    String? categoria,
    String? descricao,
    String? metodoPagamento,
    DateTime? dataPagamento,
  }) async {
    await supabase.rpc('dispensar_nfe_pendente', params: {
      'p_chave': chave,
      'p_lancar_despesa': lancarDespesa,
      'p_categoria': categoria,
      'p_descricao': descricao,
      'p_metodo_pagamento': metodoPagamento,
      'p_data_pagamento': dataPagamento?.toIso8601String().substring(0, 10),
    });
  }
}
