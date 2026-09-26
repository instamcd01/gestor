import '../config/supabase_config.dart';

/// Valor da entrega econômica de um bairro — sobrescreve o valor padrão da
/// loja (`empresas.frete_economico_valor`). `atende = false` tira a
/// econômica desse bairro. A regra única que site, WhatsApp e cobrança do
/// pedido usam fica no banco (`valor_frete_economico`).
class FreteEconomicoBairro {
  final String? id;
  final String bairro;
  final double? valor;
  final bool atende;

  const FreteEconomicoBairro({this.id, required this.bairro, this.valor, this.atende = true});

  factory FreteEconomicoBairro.fromSupabase(Map<String, dynamic> row) => FreteEconomicoBairro(
        id: row['id'] as String?,
        bairro: row['bairro'] as String,
        valor: (row['valor'] as num?)?.toDouble(),
        atende: row['atende'] as bool? ?? true,
      );
}

/// Isolamento por empresa é do RLS (`frete_economico_bairros_isolamento`).
class FreteEconomicoBairroRepository {
  Future<List<FreteEconomicoBairro>> listar() async {
    final data = await supabase.from('frete_economico_bairros').select().order('bairro');
    return (data as List).map((r) => FreteEconomicoBairro.fromSupabase(r as Map<String, dynamic>)).toList();
  }

  /// Insere ou atualiza (quando `id` existe). Bairro repetido (ignorando
  /// acento/maiúscula) é barrado pelo índice único do banco.
  Future<void> salvar(FreteEconomicoBairro item, {required String empresaId}) async {
    final payload = {
      'bairro': item.bairro.trim(),
      'valor': item.atende ? item.valor : null,
      'atende': item.atende,
    };
    if (item.id == null) {
      await supabase.from('frete_economico_bairros').insert({...payload, 'empresa_id': empresaId});
    } else {
      await supabase.from('frete_economico_bairros').update(payload).eq('id', item.id!);
    }
  }

  Future<void> excluir(String id) async {
    await supabase.from('frete_economico_bairros').delete().eq('id', id);
  }

  /// Bairros que já aparecem nos cadastros de clientes, do mais comum pro
  /// menos — sugestão ao digitar, pra o nome bater com o que o site grava
  /// (o Google devolve "Santa Cruz", não "Sta. Cruz").
  Future<List<String>> bairrosDosClientes() async {
    final data = await supabase.from('clientes').select('bairro').isFilter('deleted_at', null).neq('bairro', '');
    final contagem = <String, int>{};
    final exibicao = <String, String>{};
    for (final row in data as List) {
      final bairro = (row['bairro'] as String?)?.trim() ?? '';
      if (bairro.isEmpty) continue;
      final chave = bairro.toLowerCase();
      contagem[chave] = (contagem[chave] ?? 0) + 1;
      exibicao.putIfAbsent(chave, () => bairro);
    }
    final chaves = contagem.keys.toList()..sort((a, b) => contagem[b]!.compareTo(contagem[a]!));
    return chaves.map((c) => exibicao[c]!).toList();
  }
}
