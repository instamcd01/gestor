/// Resultado de uma ação do estoque parado (RPC `resultado_acoes_estoque_parado`)
/// — inclui produto que já saiu da lista de parados, que é o caso de sucesso.
class ResultadoAcao {
  final String acaoId;
  final String produtoId;
  final String acao;
  final String? detalhe;
  final DateTime criadoEm;

  /// Dias desde a ação (mínimo 1).
  final int dias;
  final int vendasDepois;
  final int vendasDepoisIfood;

  /// Vendas nos 90 dias antes da ação, e o quanto isso daria no mesmo
  /// número de dias do "depois" (ritmo de antes).
  final int vendas90dAntes;
  final double vendasEsperadas;

  /// Lucro das vendas depois da ação (iFood já sem a taxa).
  final double lucroDepois;
  final int? estoqueNoMomento;
  final int? estoqueAtual;
  final double? precoAntigo;
  final double? precoNovo;
  final double? precoAtualIfood;

  /// Linha do histórico de preços — permite reverter.
  final String? historicoId;

  const ResultadoAcao({
    required this.acaoId,
    required this.produtoId,
    required this.acao,
    required this.detalhe,
    required this.criadoEm,
    required this.dias,
    required this.vendasDepois,
    required this.vendasDepoisIfood,
    required this.vendas90dAntes,
    required this.vendasEsperadas,
    required this.lucroDepois,
    required this.estoqueNoMomento,
    required this.estoqueAtual,
    required this.precoAntigo,
    required this.precoNovo,
    required this.precoAtualIfood,
    required this.historicoId,
  });

  bool get ajusteDePreco => acao == 'Ajuste de preço iFood';

  /// O preço do iFood não é mais o que a ação colocou (revertido ou mudado depois).
  bool get precoMudouDepois =>
      ajusteDePreco && precoNovo != null && precoAtualIfood != null && (precoAtualIfood! - precoNovo!).abs() >= 0.01;

  bool get podeReverter => ajusteDePreco && historicoId != null && precoAntigo != null && !precoMudouDepois;

  StatusResultado get status {
    if (precoMudouDepois) return StatusResultado.alterado;
    if (vendasDepois == 0) return dias >= 14 ? StatusResultado.semEfeito : StatusResultado.cedo;
    // Vendeu bem acima do ritmo de antes (ou vendeu quando antes nada).
    if (vendasDepois >= 1 && vendasDepois > vendasEsperadas * 1.5) return StatusResultado.funcionou;
    return dias < 7 ? StatusResultado.cedo : StatusResultado.igual;
  }

  factory ResultadoAcao.fromSupabase(Map<String, dynamic> r) => ResultadoAcao(
        acaoId: r['acao_id'] as String,
        produtoId: r['produto_id'] as String,
        acao: r['acao'] as String,
        detalhe: r['detalhe'] as String?,
        criadoEm: DateTime.parse(r['criado_em'] as String).toLocal(),
        dias: (r['dias'] as num).toInt(),
        vendasDepois: (r['vendas_depois'] as num?)?.toInt() ?? 0,
        vendasDepoisIfood: (r['vendas_depois_ifood'] as num?)?.toInt() ?? 0,
        vendas90dAntes: (r['vendas_90d_antes'] as num?)?.toInt() ?? 0,
        vendasEsperadas: (r['vendas_esperadas'] as num?)?.toDouble() ?? 0,
        lucroDepois: (r['lucro_depois'] as num?)?.toDouble() ?? 0,
        estoqueNoMomento: (r['estoque_no_momento'] as num?)?.toInt(),
        estoqueAtual: (r['estoque_atual'] as num?)?.toInt(),
        precoAntigo: (r['preco_antigo'] as num?)?.toDouble(),
        precoNovo: (r['preco_novo'] as num?)?.toDouble(),
        precoAtualIfood: (r['preco_atual_ifood'] as num?)?.toDouble(),
        historicoId: r['historico_id'] as String?,
      );
}

enum StatusResultado {
  funcionou('Funcionou'),
  igual('No ritmo de antes'),
  semEfeito('Sem efeito'),
  cedo('Ainda cedo'),
  alterado('Preço já mudou de novo');

  final String rotulo;
  const StatusResultado(this.rotulo);
}
