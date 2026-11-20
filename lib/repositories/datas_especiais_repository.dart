import '../config/supabase_config.dart';

/// Uma data do calendário da loja: feriado, data pet, data de vendas ou
/// temporada. Vem da função `datas_especiais_proximas` (banco), que já
/// filtra por cidade/estado da loja e calcula as datas móveis (Páscoa,
/// Carnaval, Dia das Mães, Black Friday...).
class DataEspecial {
  final String id;
  final String nome;
  final String categoria; // feriado | pet | vendas | temporada
  final DateTime inicio;
  final DateTime fim;
  final int diasPara;
  final String? dica;
  final String? funcionamento; // normal | especial | fechada (só feriado)
  final String? abre; // HH:MM
  final String? fecha;
  final Map<String, dynamic>? horarioNormal; // {abre, fecha, aberto} do dia da semana

  DataEspecial({
    required this.id,
    required this.nome,
    required this.categoria,
    required this.inicio,
    required this.fim,
    required this.diasPara,
    this.dica,
    this.funcionamento,
    this.abre,
    this.fecha,
    this.horarioNormal,
  });

  bool get ehFeriado => categoria == 'feriado';
  bool get emAndamento => diasPara <= 0;
  bool get decidido => funcionamento != null;

  static String? _hora(dynamic v) {
    if (v == null) return null;
    final s = v.toString();
    return s.length >= 5 ? s.substring(0, 5) : s;
  }

  factory DataEspecial.fromRow(Map<String, dynamic> r) => DataEspecial(
        id: r['data_especial_id'] as String,
        nome: r['nome'] as String,
        categoria: r['categoria'] as String,
        inicio: DateTime.parse(r['inicio'] as String),
        fim: DateTime.parse(r['fim'] as String),
        diasPara: (r['dias_para'] as num).toInt(),
        dica: r['dica'] as String?,
        funcionamento: r['funcionamento'] as String?,
        abre: _hora(r['abre']),
        fecha: _hora(r['fecha']),
        horarioNormal: r['horario_normal'] == null ? null : Map<String, dynamic>.from(r['horario_normal'] as Map),
      );
}

class DatasEspeciaisRepository {
  Future<List<DataEspecial>> proximas({int dias = 90}) async {
    final data = await supabase.rpc('datas_especiais_proximas', params: {'p_dias': dias});
    return (data as List).map((r) => DataEspecial.fromRow(Map<String, dynamic>.from(r as Map))).toList();
  }

  /// Recomendação de horário pro feriado (histórico + tipo de feriado + clima +
  /// custo por hora). Campos: modo, abre, fecha, pedidos, lucro, faixas[],
  /// motivos[], confianca.
  Future<Map<String, dynamic>?> recomendar(String dataEspecialId, DateTime data) async {
    final d = '${data.year.toString().padLeft(4, '0')}-${data.month.toString().padLeft(2, '0')}-${data.day.toString().padLeft(2, '0')}';
    final r = await supabase.rpc('recomendar_horario_feriado', params: {'p_data_especial_id': dataEspecialId, 'p_data': d});
    return r == null ? null : Map<String, dynamic>.from(r as Map);
  }

  /// Horário da loja no feriado. Por baixo cria pausas (pausas_loja), que já
  /// travam site/WhatsApp e pausam iFood/99Food nos horários fechados.
  Future<void> definirFuncionamento({
    required String dataEspecialId,
    required DateTime data,
    required String modo,
    String? abre,
    String? fecha,
  }) async {
    final d = '${data.year.toString().padLeft(4, '0')}-${data.month.toString().padLeft(2, '0')}-${data.day.toString().padLeft(2, '0')}';
    await supabase.rpc('definir_funcionamento_data', params: {
      'p_data_especial_id': dataEspecialId,
      'p_data': d,
      'p_modo': modo,
      'p_abre': abre,
      'p_fecha': fecha,
    });
  }
}
