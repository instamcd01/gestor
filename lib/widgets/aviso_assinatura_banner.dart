import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../screens/minha_assinatura_screen.dart';

/// Faixa da tela Início sobre a assinatura da INARI: só aparece quando o
/// dono precisa agir — teste grátis nos últimos 3 dias, pagamento atrasado
/// ou loja em modo leitura. Lojas internas, assinaturas em dia e lojas sem
/// assinatura nenhuma (antes de a cobrança existir) não veem nada.
class AvisoAssinaturaBanner extends StatefulWidget {
  const AvisoAssinaturaBanner({super.key});

  @override
  State<AvisoAssinaturaBanner> createState() => _AvisoAssinaturaBannerState();
}

class _AvisoAssinaturaBannerState extends State<AvisoAssinaturaBanner> {
  ({String texto, Color cor, IconData icone})? _aviso;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final resposta = await Supabase.instance.client.rpc('minha_assinatura');
      if (!mounted || resposta == null) return;
      final dados = Map<String, dynamic>.from(resposta as Map);
      setState(() => _aviso = _avisoPara(dados));
    } catch (_) {
      // Sem aviso se a consulta falhar: a tela Início não pode depender disso.
    }
  }

  ({String texto, Color cor, IconData icone})? _avisoPara(Map<String, dynamic> dados) {
    switch (dados['situacao']) {
      case 'teste':
        final fim = DateTime.tryParse('${dados['teste_fim']}')?.toLocal();
        if (fim == null) return null;
        final dias = fim.difference(DateTime.now()).inDays;
        if (dias > 3) return null;
        return (
          texto: dias <= 0
              ? 'Seu teste grátis termina hoje. Escolha um plano para continuar.'
              : 'Seu teste grátis termina em ${dias == 1 ? '1 dia' : '$dias dias'}. Escolha um plano.',
          cor: Colors.blue,
          icone: Icons.hourglass_bottom_outlined,
        );
      case 'atrasada':
        return (
          texto: 'Pagamento da assinatura atrasado. Regularize para não perder o acesso.',
          cor: Colors.orange,
          icone: Icons.warning_amber_outlined,
        );
      case 'suspensa':
        return (
          texto: 'Loja em modo leitura: a assinatura está sem pagamento. Seus dados estão guardados.',
          cor: Colors.red,
          icone: Icons.lock_outline,
        );
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final aviso = _aviso;
    if (aviso == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: aviso.cor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MinhaAssinaturaScreen()));
            _carregar();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(aviso.icone, color: aviso.cor),
                const SizedBox(width: 10),
                Expanded(child: Text(aviso.texto)),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
