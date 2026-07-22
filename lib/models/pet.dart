class Pet {
  final String? id;
  String nome;
  String especie;
  String raca;
  String porte;
  DateTime nascimento;
  double peso;
  bool vacinado;
  bool castrado;
  String alergias;
  String observacoes;
  String imagemUrl;

  Pet({
    this.id,
    required this.nome,
    required this.especie,
    required this.raca,
    this.porte = '',
    required this.nascimento,
    required this.peso,
    required this.vacinado,
    required this.castrado,
    this.alergias = '',
    required this.observacoes,
    required this.imagemUrl,
  });

  factory Pet.fromSupabase(Map<String, dynamic> row) {
    return Pet(
      id: row['id'] as String?,
      nome: row['nome']?.toString() ?? '',
      especie: row['especie']?.toString() ?? '',
      raca: row['raca']?.toString() ?? '',
      porte: row['porte']?.toString() ?? '',
      nascimento: row['data_nascimento'] != null
          ? DateTime.parse(row['data_nascimento'])
          : DateTime.now(),
      peso: (row['peso'] as num?)?.toDouble() ?? 0.0,
      vacinado: row['vacinado'] as bool? ?? false,
      castrado: row['castrado'] as bool? ?? false,
      alergias: row['alergias']?.toString() ?? '',
      observacoes: row['observacoes']?.toString() ?? '',
      imagemUrl: row['imagem_url']?.toString() ?? '',
    );
  }

  /// Payload pra INSERT/UPDATE na tabela `pets` (não inclui cliente_id,
  /// que é adicionado pelo repositório).
  Map<String, dynamic> toSupabaseMap() {
    return {
      'nome': nome,
      'especie': especie,
      'raca': raca,
      'porte': porte,
      'data_nascimento': nascimento.toIso8601String().split('T').first,
      'peso': peso,
      'vacinado': vacinado,
      'castrado': castrado,
      'alergias': alergias,
      'observacoes': observacoes,
      'imagem_url': imagemUrl,
    };
  }
}
