class OrigemTarefa {
  static const manual = 'manual';
  static const sugestaoCompra = 'sugestao_compra';
  static const sugestaoRecompra = 'sugestao_recompra';
  static const sugestaoCampanha = 'sugestao_campanha';
  static const sugestaoConteudo = 'sugestao_conteudo';
}

class RecorrenciaTarefa {
  static const diaria = 'diaria';
  static const semanal = 'semanal';
  static const mensal = 'mensal';
}

class Tarefa {
  final String? id;
  final String titulo;
  final String descricao;
  final DateTime data;
  final bool concluida;
  final DateTime? concluidaEm;
  final String? concluidaPor;
  final String? criadoPor;
  final String? atribuidoA;

  final String origem;
  final String? origemReferenciaId;

  final bool recorrente;
  final String? recorrenciaTipo; // ver RecorrenciaTarefa
  final int? recorrenciaDiaSemana; // 0-6, só p/ semanal
  final int? recorrenciaDiaMes; // 1-28, só p/ mensal
  final String? tarefaOrigemId;

  Tarefa({
    this.id,
    required this.titulo,
    this.descricao = '',
    required this.data,
    this.concluida = false,
    this.concluidaEm,
    this.concluidaPor,
    this.criadoPor,
    this.atribuidoA,
    this.origem = OrigemTarefa.manual,
    this.origemReferenciaId,
    this.recorrente = false,
    this.recorrenciaTipo,
    this.recorrenciaDiaSemana,
    this.recorrenciaDiaMes,
    this.tarefaOrigemId,
  });

  Tarefa copyWith({
    String? id,
    String? titulo,
    String? descricao,
    DateTime? data,
    bool? concluida,
    DateTime? concluidaEm,
    String? concluidaPor,
    String? criadoPor,
    String? atribuidoA,
    String? origem,
    String? origemReferenciaId,
    bool? recorrente,
    String? recorrenciaTipo,
    int? recorrenciaDiaSemana,
    int? recorrenciaDiaMes,
    String? tarefaOrigemId,
  }) {
    return Tarefa(
      id: id ?? this.id,
      titulo: titulo ?? this.titulo,
      descricao: descricao ?? this.descricao,
      data: data ?? this.data,
      concluida: concluida ?? this.concluida,
      concluidaEm: concluidaEm ?? this.concluidaEm,
      concluidaPor: concluidaPor ?? this.concluidaPor,
      criadoPor: criadoPor ?? this.criadoPor,
      atribuidoA: atribuidoA ?? this.atribuidoA,
      origem: origem ?? this.origem,
      origemReferenciaId: origemReferenciaId ?? this.origemReferenciaId,
      recorrente: recorrente ?? this.recorrente,
      recorrenciaTipo: recorrenciaTipo ?? this.recorrenciaTipo,
      recorrenciaDiaSemana: recorrenciaDiaSemana ?? this.recorrenciaDiaSemana,
      recorrenciaDiaMes: recorrenciaDiaMes ?? this.recorrenciaDiaMes,
      tarefaOrigemId: tarefaOrigemId ?? this.tarefaOrigemId,
    );
  }

  factory Tarefa.fromSupabase(Map<String, dynamic> row) {
    return Tarefa(
      id: row['id'] as String?,
      titulo: row['titulo']?.toString() ?? '',
      descricao: row['descricao']?.toString() ?? '',
      data: DateTime.parse(row['data'].toString()),
      concluida: row['concluida'] as bool? ?? false,
      concluidaEm: row['concluida_em'] != null ? DateTime.parse(row['concluida_em'].toString()) : null,
      concluidaPor: row['concluida_por'] as String?,
      criadoPor: row['criado_por'] as String?,
      atribuidoA: row['atribuido_a'] as String?,
      origem: row['origem']?.toString() ?? OrigemTarefa.manual,
      origemReferenciaId: row['origem_referencia_id'] as String?,
      recorrente: row['recorrente'] as bool? ?? false,
      recorrenciaTipo: row['recorrencia_tipo'] as String?,
      recorrenciaDiaSemana: (row['recorrencia_dia_semana'] as num?)?.toInt(),
      recorrenciaDiaMes: (row['recorrencia_dia_mes'] as num?)?.toInt(),
      tarefaOrigemId: row['tarefa_origem_id'] as String?,
    );
  }

  Map<String, dynamic> toSupabaseMap() {
    return {
      'titulo': titulo,
      'descricao': descricao,
      'data': data.toIso8601String().split('T').first,
      'concluida': concluida,
      'concluida_em': concluidaEm?.toIso8601String(),
      'concluida_por': concluidaPor,
      'atribuido_a': atribuidoA,
      'origem': origem,
      'origem_referencia_id': origemReferenciaId,
      'recorrente': recorrente,
      'recorrencia_tipo': recorrenciaTipo,
      'recorrencia_dia_semana': recorrenciaDiaSemana,
      'recorrencia_dia_mes': recorrenciaDiaMes,
    };
  }
}
