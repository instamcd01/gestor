import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../config/supabase_config.dart';
import '../models/pausa_loja.dart';
import '../providers/auth_provider.dart';
import '../repositories/pausa_loja_repository.dart';
import 'pausar_loja_screen.dart';

const _diasSemana = [
  ('segunda', 'Segunda-feira'),
  ('terca', 'Terça-feira'),
  ('quarta', 'Quarta-feira'),
  ('quinta', 'Quinta-feira'),
  ('sexta', 'Sexta-feira'),
  ('sabado', 'Sábado'),
  ('domingo', 'Domingo'),
];

class _HorarioDia {
  bool aberto;
  TimeOfDay abre;
  TimeOfDay fecha;
  _HorarioDia({required this.aberto, required this.abre, required this.fecha});
}

/// Configurações > Geral: horário de funcionamento da loja. Usado pelo
/// catálogo online (quando existir) e por futuras automações de
/// atendimento (n8n) pra saber se a loja está aberta.
class GeralScreen extends StatefulWidget {
  const GeralScreen({super.key});

  @override
  State<GeralScreen> createState() => _GeralScreenState();
}

class _GeralScreenState extends State<GeralScreen> {
  final Map<String, _HorarioDia> _horarios = {
    for (final (chave, _) in _diasSemana)
      chave: _HorarioDia(
        aberto: chave != 'domingo',
        abre: const TimeOfDay(hour: 8, minute: 0),
        fecha: const TimeOfDay(hour: 18, minute: 0),
      ),
  };

  final _pausaRepository = PausaLojaRepository();
  PausaLoja? _pausaAtiva;

  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregarDados();
    _carregarPausa();
  }

  // Pedido do usuário: pausa temporária e horário fixo semanal são as
  // duas faces de "quando a loja atende" — ficam juntas nesta tela em
  // vez de espalhadas em itens de menu separados (ver PausarLojaScreen
  // pro fluxo completo de pausar/agendar/cancelar).
  Future<void> _carregarPausa() async {
    try {
      final pausas = await _pausaRepository.listarAtivasOuAgendadas();
      if (mounted) setState(() => _pausaAtiva = pausas.where((p) => p.ativa).firstOrNull);
    } catch (e) {
      debugPrint('Erro ao carregar pausa da loja: $e');
    }
  }

  Future<void> _abrirPausarLoja() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const PausarLojaScreen()));
    _carregarPausa();
  }

  TimeOfDay _parseHora(String? texto, TimeOfDay padrao) {
    if (texto == null) return padrao;
    final partes = texto.split(':');
    if (partes.length != 2) return padrao;
    final hora = int.tryParse(partes[0]);
    final minuto = int.tryParse(partes[1]);
    if (hora == null || minuto == null) return padrao;
    return TimeOfDay(hour: hora, minute: minuto);
  }

  String _formatarHora(TimeOfDay hora) =>
      '${hora.hour.toString().padLeft(2, '0')}:${hora.minute.toString().padLeft(2, '0')}';

  Future<void> _carregarDados() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) {
      setState(() => _carregando = false);
      return;
    }

    try {
      final data = await supabase
          .from('empresas')
          .select('horario_funcionamento')
          .eq('id', empresaId)
          .single();

      final horarioSalvo = data['horario_funcionamento'] as Map<String, dynamic>?;
      if (horarioSalvo != null) {
        for (final (chave, _) in _diasSemana) {
          final dia = horarioSalvo[chave] as Map<String, dynamic>?;
          if (dia != null) {
            _horarios[chave] = _HorarioDia(
              aberto: dia['aberto'] as bool? ?? false,
              abre: _parseHora(dia['abre']?.toString(), const TimeOfDay(hour: 8, minute: 0)),
              fecha: _parseHora(dia['fecha']?.toString(), const TimeOfDay(hour: 18, minute: 0)),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Erro ao carregar horário de funcionamento: $e');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvar() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;

    setState(() => _salvando = true);
    try {
      final horarioJson = {
        for (final entry in _horarios.entries)
          entry.key: {
            'aberto': entry.value.aberto,
            'abre': _formatarHora(entry.value.abre),
            'fecha': _formatarHora(entry.value.fecha),
          },
      };

      await supabase.from('empresas').update({'horario_funcionamento': horarioJson}).eq('id', empresaId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Horário de funcionamento salvo com sucesso!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Future<void> _escolherHora(String chave, bool ehAbertura) async {
    final horario = _horarios[chave]!;
    final escolhida = await showTimePicker(
      context: context,
      initialTime: ehAbertura ? horario.abre : horario.fecha,
    );
    if (escolhida == null) return;
    setState(() {
      if (ehAbertura) {
        horario.abre = escolhida;
      } else {
        horario.fecha = escolhida;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Horário de Funcionamento'),
        actions: [
          _salvando
              ? Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary, strokeWidth: 2),
                  ),
                )
              : IconButton(icon: const Icon(Icons.save), onPressed: _carregando ? null : _salvar),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Usado no catálogo online e em futuras automações de atendimento.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 12),
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Icon(
                      _pausaAtiva != null ? Icons.pause_circle_outline : Icons.event_busy_outlined,
                      color: _pausaAtiva != null ? Colors.orange : null,
                    ),
                    title: const Text('Pausar loja temporariamente'),
                    subtitle: Text(
                      _pausaAtiva != null
                          ? 'Em pausa${_pausaAtiva!.motivo != null ? ": ${_pausaAtiva!.motivo}" : ""} — volta às '
                              '${DateFormat('dd/MM HH:mm').format(_pausaAtiva!.fim)}'
                          : 'Pausa imediata ou agendada — vale pro site, WhatsApp e marketplaces',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _abrirPausarLoja,
                  ),
                ),
                ..._diasSemana.map((diaInfo) {
                  final (chave, rotulo) = diaInfo;
                  final horario = _horarios[chave]!;
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: Text(rotulo, style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                          Switch(
                            value: horario.aberto,
                            onChanged: (v) => setState(() => horario.aberto = v),
                          ),
                          if (horario.aberto) ...[
                            Expanded(
                              flex: 3,
                              child: TextButton(
                                onPressed: () => _escolherHora(chave, true),
                                child: Text(_formatarHora(horario.abre)),
                              ),
                            ),
                            const Text('—'),
                            Expanded(
                              flex: 3,
                              child: TextButton(
                                onPressed: () => _escolherHora(chave, false),
                                child: Text(_formatarHora(horario.fecha)),
                              ),
                            ),
                          ] else
                            Expanded(
                              flex: 6,
                              child: Text(
                                'Fechado',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                textAlign: TextAlign.center,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _salvando ? null : _salvar,
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                  child: const Text('Salvar'),
                ),
              ],
            ),
    );
  }
}
