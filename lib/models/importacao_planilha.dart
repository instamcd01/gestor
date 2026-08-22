class ImportacaoPlanilha {
  final String id;
  final String tipo;
  final String? nomeArquivo;
  final int totalLinhas;
  final int novos;
  final int atualizados;
  final int linhasIgnoradas;
  final String status;
  final String? mensagemErro;
  final DateTime criadoEm;

  ImportacaoPlanilha({
    required this.id,
    required this.tipo,
    this.nomeArquivo,
    required this.totalLinhas,
    required this.novos,
    required this.atualizados,
    required this.linhasIgnoradas,
    required this.status,
    this.mensagemErro,
    required this.criadoEm,
  });

  factory ImportacaoPlanilha.fromSupabase(Map<String, dynamic> row) {
    return ImportacaoPlanilha(
      id: row['id'] as String,
      tipo: row['tipo'] as String,
      nomeArquivo: row['nome_arquivo'] as String?,
      totalLinhas: (row['total_linhas'] as num?)?.toInt() ?? 0,
      novos: (row['novos'] as num?)?.toInt() ?? 0,
      atualizados: (row['atualizados'] as num?)?.toInt() ?? 0,
      linhasIgnoradas: (row['linhas_ignoradas'] as num?)?.toInt() ?? 0,
      status: row['status'] as String,
      mensagemErro: row['mensagem_erro'] as String?,
      criadoEm: DateTime.parse(row['criado_em'] as String),
    );
  }
}
