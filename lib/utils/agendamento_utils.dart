/// Mesma lógica de agendamento usada no checkout do site (gestor-loja,
/// src/lib/agendamento.ts) — mantida em espelho pros dois lados oferecerem
/// exatamente as mesmas janelas pro cliente, seja ele escolhendo sozinho no
/// site ou o vendedor escolhendo por ele no telefone/WhatsApp.
library;

const _diasSemana = ['domingo', 'segunda', 'terca', 'quarta', 'quinta', 'sexta', 'sabado'];

const _diasAFrente = 3;
const _antecedenciaMinimaMin = 60;
const _duracaoJanelaMin = 60;

class OpcaoDataAgendamento {
  /// Meia-noite local do dia (só a data importa, hora é sempre 00:00).
  final DateTime data;
  final String label;
  final String diaSemana;

  const OpcaoDataAgendamento({required this.data, required this.label, required this.diaSemana});
}

class JanelaHorarioAgendamento {
  final DateTime inicio;
  final DateTime fim;
  final String label;

  const JanelaHorarioAgendamento({required this.inicio, required this.fim, required this.label});
}

/// DateTime.weekday: segunda=1 ... domingo=7. `% 7` faz domingo cair em 0,
/// batendo com o índice usado em _diasSemana (mesma convenção do Date.getDay() no JS).
String _diaSemanaChave(DateTime data) => _diasSemana[data.weekday % 7];

String _formatarHM(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

const _diasAbrev = ['dom.', 'seg.', 'ter.', 'qua.', 'qui.', 'sex.', 'sáb.'];

String _formatarDataCurta(DateTime data) {
  final abrev = _diasAbrev[data.weekday % 7];
  return '$abrev ${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}';
}

List<int> _parseHora(String? texto, int horaPadrao, int minPadrao) {
  if (texto == null) return [horaPadrao, minPadrao];
  final partes = texto.split(':');
  if (partes.length != 2) return [horaPadrao, minPadrao];
  final hora = int.tryParse(partes[0]);
  final minuto = int.tryParse(partes[1]);
  if (hora == null || minuto == null) return [horaPadrao, minPadrao];
  return [hora, minuto];
}

/// Dias em que dá pra agendar — hoje até +3 dias, pulando os que a loja
/// marcou como fechado em Configurações > Horário de Funcionamento.
List<OpcaoDataAgendamento> gerarOpcoesData(Map<String, dynamic>? horarioFuncionamento) {
  final opcoes = <OpcaoDataAgendamento>[];
  final agora = DateTime.now();
  final hoje = DateTime(agora.year, agora.month, agora.day);

  for (var i = 0; i <= _diasAFrente; i++) {
    final data = hoje.add(Duration(days: i));
    final diaSemana = _diaSemanaChave(data);
    final config = horarioFuncionamento?[diaSemana] as Map<String, dynamic>?;
    if (config?['aberto'] == false) continue;

    final label = i == 0 ? 'Hoje' : (i == 1 ? 'Amanhã' : _formatarDataCurta(data));
    opcoes.add(OpcaoDataAgendamento(data: data, label: label, diaSemana: diaSemana));
  }
  return opcoes;
}

/// Janelas de 1h dentro do horário de funcionamento do dia escolhido, já
/// descartando qualquer janela que comece antes de 1h a partir de agora
/// (tempo mínimo pra loja se preparar).
List<JanelaHorarioAgendamento> gerarJanelasHorario(
  DateTime data,
  String diaSemana,
  Map<String, dynamic>? horarioFuncionamento,
) {
  final config = horarioFuncionamento?[diaSemana] as Map<String, dynamic>?;
  if (config?['aberto'] == false) return [];

  final abre = _parseHora(config?['abre'] as String?, 8, 0);
  final fecha = _parseHora(config?['fecha'] as String?, 18, 0);

  final antecedenciaMinima = DateTime.now().add(const Duration(minutes: _antecedenciaMinimaMin));
  final fechamento = DateTime(data.year, data.month, data.day, fecha[0], fecha[1]);

  final janelas = <JanelaHorarioAgendamento>[];
  var cursor = DateTime(data.year, data.month, data.day, abre[0], abre[1]);

  while (!cursor.add(const Duration(minutes: _duracaoJanelaMin)).isAfter(fechamento)) {
    final inicio = cursor;
    final fim = cursor.add(const Duration(minutes: _duracaoJanelaMin));

    if (!inicio.isBefore(antecedenciaMinima)) {
      janelas.add(JanelaHorarioAgendamento(inicio: inicio, fim: fim, label: '${_formatarHM(inicio)}–${_formatarHM(fim)}'));
    }
    cursor = fim;
  }
  return janelas;
}
