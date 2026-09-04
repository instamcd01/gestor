/// Período usado pelo módulo Planejamento (tarefas e metas financeiras) —
/// dia único, semana (segunda a domingo) ou mês corrente, sempre ancorado
/// numa data de referência (`PeriodoSelecionado.referencia`).
enum PeriodoPlanejamento { dia, semana, mes }

/// Um período concreto (tipo + intervalo [inicio, fim) já calculado a
/// partir de uma data de referência) — evita recalcular início/fim em
/// vários lugares da tela com risco de decisões diferentes (ex: semana
/// começando domingo num lugar e segunda em outro).
class PeriodoSelecionado {
  final PeriodoPlanejamento tipo;
  final DateTime referencia;

  PeriodoSelecionado({required this.tipo, required this.referencia});

  static DateTime _apenasData(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Início do período (inclusive).
  DateTime get inicio {
    final ref = _apenasData(referencia);
    switch (tipo) {
      case PeriodoPlanejamento.dia:
        return ref;
      case PeriodoPlanejamento.semana:
        // weekday: 1=segunda ... 7=domingo — volta pra segunda-feira da semana.
        return ref.subtract(Duration(days: ref.weekday - 1));
      case PeriodoPlanejamento.mes:
        return DateTime(ref.year, ref.month, 1);
    }
  }

  /// Fim do período (exclusive) — usar `< fim`, nunca `<= fim`, em filtros.
  DateTime get fim {
    switch (tipo) {
      case PeriodoPlanejamento.dia:
        return inicio.add(const Duration(days: 1));
      case PeriodoPlanejamento.semana:
        return inicio.add(const Duration(days: 7));
      case PeriodoPlanejamento.mes:
        return DateTime(inicio.year, inicio.month + 1, 1);
    }
  }

  bool contem(DateTime data) {
    final d = _apenasData(data);
    return !d.isBefore(inicio) && d.isBefore(fim);
  }

  /// Move o período pra frente (n=1) ou pra trás (n=-1) — dia vira dia
  /// seguinte/anterior, semana vira a próxima/anterior, mês vira o
  /// próximo/anterior (dia 1, evita estourar meses mais curtos).
  PeriodoSelecionado navegar(int n) {
    switch (tipo) {
      case PeriodoPlanejamento.dia:
        return PeriodoSelecionado(tipo: tipo, referencia: referencia.add(Duration(days: n)));
      case PeriodoPlanejamento.semana:
        return PeriodoSelecionado(tipo: tipo, referencia: referencia.add(Duration(days: 7 * n)));
      case PeriodoPlanejamento.mes:
        return PeriodoSelecionado(tipo: tipo, referencia: DateTime(referencia.year, referencia.month + n, 1));
    }
  }

  String get rotulo {
    switch (tipo) {
      case PeriodoPlanejamento.dia:
        return 'Dia';
      case PeriodoPlanejamento.semana:
        return 'Semana';
      case PeriodoPlanejamento.mes:
        return 'Mês';
    }
  }
}
