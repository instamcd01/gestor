import 'package:flutter/material.dart';

import '../repositories/datas_especiais_repository.dart';
import '../screens/datas_especiais_screen.dart';

/// Faixa da tela Início: feriado nos próximos 7 dias sem horário escolhido.
/// Some quando o dono decide (normal, especial ou fechada).
class AvisoFeriadoBanner extends StatefulWidget {
  const AvisoFeriadoBanner({super.key});

  @override
  State<AvisoFeriadoBanner> createState() => _AvisoFeriadoBannerState();
}

class _AvisoFeriadoBannerState extends State<AvisoFeriadoBanner> {
  DataEspecial? _feriado;
  String? _recomendacao;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final datas = await DatasEspeciaisRepository().proximas(dias: 7);
      final pendente = datas.where((d) => d.ehFeriado && !d.decidido).firstOrNull;
      if (mounted) setState(() => _feriado = pendente);
      if (pendente != null) {
        final r = await DatasEspeciaisRepository().recomendar(pendente.id, pendente.inicio);
        if (r != null && mounted) {
          final ped = (r['pedidos'] as num?)?.round() ?? 0;
          setState(() => _recomendacao = switch (r['modo']) {
                'fechada' => 'Recomendado: fechar',
                'normal' => 'Recomendado: horário normal (~$ped pedidos)',
                _ => 'Recomendado: ${r['abre']}–${r['fecha']} (~$ped pedidos)',
              });
        }
      }
    } catch (_) {
      // A tela Início não pode depender disso.
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = _feriado;
    if (f == null) return const SizedBox.shrink();
    final quando = f.diasPara == 0 ? 'Hoje' : f.diasPara == 1 ? 'Amanhã' : 'Em ${f.diasPara} dias';
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: Color.alphaBlend(Colors.deepOrange.withValues(alpha: 0.15), cs.surface),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            await Navigator.push(context, MaterialPageRoute(builder: (_) => const DatasEspeciaisScreen()));
            _carregar();
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.event_busy_outlined, color: Colors.deepOrange),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$quando é ${f.nome}. Como a loja vai funcionar?',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (_recomendacao != null) Text(_recomendacao!, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
