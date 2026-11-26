import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/cliente_validators.dart';
import 'entrega_oferta_acerto_screen.dart';
import 'entrega_oferta_rotas_screen.dart';

/// Entregador por oferta no WhatsApp (19/11): o pedido de entrega cai, a rota vai como oferta
/// pros motoboys marcados no cadastro, o 1º que aceita leva. Aqui o dono liga/desliga e ajusta
/// o valor que o motoboy recebe (ele só vê o total, nunca a conta). Tabela entrega_oferta_config
/// (RLS: só dono). Desenho: docs/superpowers/specs/2026-11-19-entregador-por-oferta-whatsapp-design.md
class EntregaOfertaConfigScreen extends StatefulWidget {
  const EntregaOfertaConfigScreen({super.key});

  @override
  State<EntregaOfertaConfigScreen> createState() => _EntregaOfertaConfigScreenState();
}

class _EntregaOfertaConfigScreenState extends State<EntregaOfertaConfigScreen> {
  final _db = Supabase.instance.client;
  final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
  final _saida = TextEditingController();
  final _km = TextEditingController();
  final _parada = TextEditingController();
  final _telefoneAviso = TextEditingController();
  final _antecedencia = TextEditingController();
  final _minimo = TextEditingController();
  final _bonusChuva = TextEditingController();
  final _chuvaMm = TextEditingController();
  final _bonusPico = TextEditingController();
  final _picoHorarios = TextEditingController();
  final _inicio = TextEditingController();
  final _fim = TextEditingController();
  final _antecedenciaOferta = TextEditingController();

  bool _carregando = true;
  bool _salvando = false;
  bool _ativo = false;
  int _motoboys = 0;
  String? _empresaId;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
    for (final c in [_saida, _km, _parada, _minimo]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_saida, _km, _parada, _telefoneAviso, _antecedencia, _minimo, _antecedenciaOferta,
      _bonusChuva, _chuvaMm, _bonusPico, _picoHorarios, _inicio, _fim]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final cfg = await _db.from('entrega_oferta_config').select().maybeSingle();
      final motoboys = await _db
          .from('entregadores')
          .select('id')
          .eq('freelancer_oferta', true)
          .eq('ativo', true)
          .isFilter('deleted_at', null);
      if (!mounted) return;
      setState(() {
        _empresaId = cfg?['empresa_id'] as String?;
        _ativo = cfg?['ativo'] as bool? ?? false;
        _saida.text = ClienteValidators.formatarMoeda((cfg?['valor_saida'] as num?)?.toDouble() ?? 4);
        _km.text = ClienteValidators.formatarMoeda((cfg?['valor_km'] as num?)?.toDouble() ?? 1);
        _parada.text = ClienteValidators.formatarMoeda((cfg?['valor_parada_extra'] as num?)?.toDouble() ?? 2);
        _telefoneAviso.text = cfg?['telefone_aviso'] as String? ?? '';
        _antecedencia.text = '${cfg?['antecedencia_sem_aceite_min'] ?? 15}';
        _minimo.text = ClienteValidators.formatarMoeda((cfg?['valor_minimo'] as num?)?.toDouble() ?? 7);
        _antecedenciaOferta.text = '${cfg?['antecedencia_oferta_min'] ?? 30}';
        _bonusChuva.text = ClienteValidators.formatarMoeda((cfg?['bonus_chuva'] as num?)?.toDouble() ?? 0);
        _chuvaMm.text = '${cfg?['chuva_mm_minimo'] ?? 1}';
        _bonusPico.text = ClienteValidators.formatarMoeda((cfg?['bonus_pico'] as num?)?.toDouble() ?? 0);
        _picoHorarios.text = cfg?['pico_horarios'] as String? ?? '';
        _inicio.text = (cfg?['oferta_inicio'] as String?)?.substring(0, 5) ?? '';
        _fim.text = (cfg?['oferta_fim'] as String?)?.substring(0, 5) ?? '';
        _motoboys = (motoboys as List).length;
        _carregando = false;
      });
    } catch (e) {
      if (mounted) setState(() => _erro = 'Não foi possível carregar: $e');
    }
  }

  double _n(TextEditingController c) => ClienteValidators.parseNumero(c.text) ?? 0;

  /// "18" / "18:30" → "18:30"; vazio = sem limite
  String? _hora(String t) {
    final m = RegExp(r'^(\d{1,2})(?::(\d{2}))?$').firstMatch(t.trim());
    if (m == null) return null;
    return '${m.group(1)!.padLeft(2, '0')}:${m.group(2) ?? '00'}';
  }

  /// Mesma conta de entrega_oferta_calcular: saída + km só de ida + paradas extras,
  /// arredondado pra cima de 50 em 50 centavos.
  String _exemplo(double km, int paradas) {
    final conta = ((_n(_saida) + _n(_km) * km + _n(_parada) * (paradas - 1)) * 2).ceil() / 2;
    return _moeda.format(conta < _n(_minimo) ? _n(_minimo) : conta);
  }

  Future<void> _salvar() async {
    // reconta na hora: a tela pode ter sido aberta antes de cadastrar o motoboy (25/11: o "ligar" não gravava)
    if (_ativo && _motoboys == 0) {
      try {
        final motoboys = await _db
            .from('entregadores')
            .select('id')
            .eq('freelancer_oferta', true)
            .eq('ativo', true)
            .isFilter('deleted_at', null);
        _motoboys = (motoboys as List).length;
      } catch (_) {}
    }
    if (_ativo && _motoboys == 0) {
      setState(() => _erro = 'Marque pelo menos um motoboy como "Recebe ofertas" (Usuários › Entregadores) antes de ligar.');
      return;
    }
    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      final dados = {
        'ativo': _ativo,
        'valor_saida': _n(_saida),
        'valor_km': _n(_km),
        'valor_parada_extra': _n(_parada),
        'telefone_aviso': _telefoneAviso.text.replaceAll(RegExp(r'\D'), '').isEmpty
            ? null
            : _telefoneAviso.text.replaceAll(RegExp(r'\D'), ''),
        'antecedencia_sem_aceite_min': int.tryParse(_antecedencia.text.trim()) ?? 15,
        'valor_minimo': _n(_minimo),
        'antecedencia_oferta_min': int.tryParse(_antecedenciaOferta.text.trim()) ?? 30,
        'bonus_chuva': _n(_bonusChuva),
        'chuva_mm_minimo': double.tryParse(_chuvaMm.text.trim().replaceAll(',', '.')) ?? 1,
        'bonus_pico': _n(_bonusPico),
        'pico_horarios': _picoHorarios.text.trim().isEmpty ? null : _picoHorarios.text.trim(),
        'oferta_inicio': _hora(_inicio.text),
        'oferta_fim': _hora(_fim.text),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (_empresaId == null) {
        throw Exception('configuração da loja não encontrada (só o dono pode alterar)');
      }
      final gravado = await _db.from('entrega_oferta_config').update(dados).eq('empresa_id', _empresaId!).select('ativo');
      if ((gravado as List).isEmpty) throw Exception('nada foi gravado (só o dono pode alterar)');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_ativo ? 'Salvo. As ofertas estão ligadas.' : 'Salvo. As ofertas estão desligadas.')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _erro = 'Não foi possível salvar: $e');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  Widget _campoValor(TextEditingController c, String rotulo, {String? ajuda}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: c,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: rotulo, prefixText: 'R\$ ', helperText: ajuda),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Entregador por oferta')),
      body: _carregando && _erro == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Quando cair um pedido de entrega, a rota vai pelo WhatsApp pros motoboys marcados. '
                  'O primeiro que aceitar leva, e o que cair até ele sair entra na rota dele. '
                  'Ele só vê o valor final.',
                  style: TextStyle(color: cores.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.two_wheeler),
                    title: const Text('Rotas de motoboy'),
                    subtitle: const Text('Rotas abertas, pausar ofertas, pedidos fora e os que voltaram'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const EntregaOfertaRotasScreen())),
                  ),
                ),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.payments_outlined),
                    title: const Text('Acerto com motoboys'),
                    subtitle: const Text('Quanto pagar ou receber de cada um'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const EntregaOfertaAcertoScreen())),
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ligado', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(_motoboys == 0
                      ? 'Nenhum motoboy recebendo ofertas ainda'
                      : '$_motoboys motoboy${_motoboys == 1 ? '' : 's'} recebendo ofertas'),
                  value: _ativo,
                  onChanged: (v) => setState(() => _ativo = v),
                ),
                const Divider(height: 24),
                Text('Quanto o motoboy recebe', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                _campoValor(_saida, 'Por saída (cada rota)'),
                _campoValor(_km, 'Por km (só a ida)', ajuda: 'A volta não conta'),
                _campoValor(_parada, 'Por entrega a mais na mesma rota'),
                _campoValor(_minimo, 'Valor mínimo por rota', ajuda: 'Entrega curta não sai por menos que isso'),
                Card(
                  color: cores.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Exemplos', style: TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text('1 entrega a 1,3 km (loja): ${_exemplo(1.3, 1)}'),
                        Text('1 entrega a 3 km (site): ${_exemplo(3, 1)}'),
                        Text('1 entrega a 4,3 km (iFood): ${_exemplo(4.3, 1)}'),
                        Text('2 entregas, 5 km até a última: ${_exemplo(5, 2)}'),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 32),
                Text('Bônus', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                _campoValor(_bonusChuva, 'A mais quando chove', ajuda: 'Pela previsão do tempo do período (manhã, tarde, noite). 0 = desligado'),
                TextField(
                  controller: _chuvaMm,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Conta como chuva a partir de', suffixText: 'mm no período'),
                ),
                const SizedBox(height: 12),
                _campoValor(_bonusPico, 'A mais no horário de pico', ajuda: '0 = desligado'),
                TextField(
                  controller: _picoHorarios,
                  decoration: const InputDecoration(labelText: 'Horários de pico', hintText: '11:30-13:30,18:00-20:30'),
                ),
                const Divider(height: 32),
                Text('Horário das ofertas', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: TextField(controller: _inicio, decoration: const InputDecoration(labelText: 'Das', hintText: '09:00'))),
                  const SizedBox(width: 12),
                  Expanded(child: TextField(controller: _fim, decoration: const InputDecoration(labelText: 'Até', hintText: '21:00'))),
                ]),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Vazio = o dia todo. Fora do horário os pedidos não viram oferta (a loja entrega).',
                      style: TextStyle(fontSize: 12, color: cores.onSurfaceVariant)),
                ),
                const Divider(height: 32),
                Text('Quando a oferta sai', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(
                  controller: _antecedenciaOferta,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Mandar a oferta quantos minutos antes da hora de sair',
                    suffixText: 'min',
                    helperText: 'Até lá os pedidos vão se juntando na mesma rota e o motoboy não fica esperando',
                  ),
                ),
                const Divider(height: 32),
                Text('Se ninguém aceitar', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(
                  controller: _antecedencia,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Avisar a loja quantos minutos antes do prazo de saída',
                    suffixText: 'min',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _telefoneAviso,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp que recebe o aviso "rota sem entregador"',
                    helperText: 'Com DDD. O aviso também aparece no app.',
                  ),
                ),
                if (_erro != null) ...[
                  const SizedBox(height: 16),
                  Text(_erro!, style: TextStyle(color: cores.error)),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _salvando || _carregando ? null : _salvar,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  child: Text(_salvando ? 'Salvando...' : 'Salvar'),
                ),
              ],
            ),
    );
  }
}
