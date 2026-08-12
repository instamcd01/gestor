import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/supabase_config.dart';
import '../providers/auth_provider.dart';
import '../widgets/aviso_banner.dart';

/// Ciclo de recompra padrão pra produto que não tem o próprio ciclo
/// configurado (ver Produto.cicloRecompraDias, campo em cada produto) —
/// usado pela previsão automática de recompra (lembrete via WhatsApp,
/// ver v_clientes_prontos_recompra). Vazio = produto sem ciclo próprio
/// fica de fora da detecção, não assume nenhum valor.
class CicloRecompraPadraoScreen extends StatefulWidget {
  const CicloRecompraPadraoScreen({super.key});

  @override
  State<CicloRecompraPadraoScreen> createState() => _CicloRecompraPadraoScreenState();
}

class _CicloRecompraPadraoScreenState extends State<CicloRecompraPadraoScreen> {
  bool _carregando = true;
  bool _salvando = false;
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;
    try {
      final data = await supabase
          .from('empresas')
          .select('ciclo_recompra_padrao_dias')
          .eq('id', empresaId)
          .single();
      if (!mounted) return;
      final valor = data['ciclo_recompra_padrao_dias'] as int?;
      if (valor != null) _controller.text = valor.toString();
    } catch (e) {
      debugPrint('Erro ao carregar ciclo de recompra padrão: $e');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvar() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;

    setState(() => _salvando = true);
    try {
      await supabase.from('empresas').update({
        'ciclo_recompra_padrao_dias': int.tryParse(_controller.text.trim()),
      }).eq('id', empresaId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuração salva.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Ciclo de Recompra Padrão')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AvisoBanner(
              texto: 'Cada produto pode ter seu próprio ciclo de recompra (edite o produto e '
                  'preencha "Ciclo de recompra"). Esse valor aqui é só o PADRÃO usado quando um '
                  'produto não tem ciclo próprio configurado. Deixe em branco pra esses produtos '
                  'ficarem de fora do lembrete automático de recompra.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Ciclo padrão (dias)',
                helperText: 'Ex: 30 — produto sem ciclo próprio é considerado "pronto pra recomprar" nesse prazo.',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _salvando ? null : _salvar,
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
              child: _salvando
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Theme.of(context).colorScheme.onPrimary),
                    )
                  : const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}
