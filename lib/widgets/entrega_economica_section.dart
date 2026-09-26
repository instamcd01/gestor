import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/supabase_config.dart';
import '../providers/auth_provider.dart';
import '../utils/cliente_validators.dart';
import '../utils/formatadores_input.dart';
import 'frete_economico_bairros_section.dart';

/// Configuração da entrega econômica (Configurações > Opções de Entrega):
/// valor padrão + prazo (`empresas.frete_economico_*`) e a lista de valor
/// por bairro. Tem o próprio "Salvar" — a tela de Opções de Entrega não
/// tem formulário único (zonas salvam cada uma na sua folha).
/// Morava no Catálogo Online até 26/09; mudou pra cá a pedido do usuário.
class EntregaEconomicaSection extends StatefulWidget {
  const EntregaEconomicaSection({super.key});

  @override
  State<EntregaEconomicaSection> createState() => _EntregaEconomicaSectionState();
}

class _EntregaEconomicaSectionState extends State<EntregaEconomicaSection> {
  final _valorController = TextEditingController();
  final _prazoController = TextEditingController();
  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _valorController.dispose();
    _prazoController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) {
      setState(() => _carregando = false);
      return;
    }
    try {
      final data = await supabase
          .from('empresas')
          .select('frete_economico_valor, frete_economico_prazo_dias')
          .eq('id', empresaId)
          .single();
      _valorController.text = ClienteValidators.formatarMoeda((data['frete_economico_valor'] as num?)?.toDouble());
      _prazoController.text = data['frete_economico_prazo_dias']?.toString() ?? '';
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao carregar entrega econômica: $e')));
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  /// null = os dois em branco (econômica desligada nos bairros fora da
  /// lista, permitido) ou os dois preenchidos. Senão, exige os dois.
  String? _validar() {
    final valor = _valorController.text.trim();
    final prazo = _prazoController.text.trim();
    if (valor.isEmpty && prazo.isEmpty) return null;
    if (valor.isEmpty || prazo.isEmpty) return 'Informe valor e prazo da entrega econômica, ou deixe os dois em branco';
    return null;
  }

  Future<void> _salvar() async {
    final erro = _validar();
    if (erro != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erro)));
      return;
    }
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;
    setState(() => _salvando = true);
    try {
      await supabase.from('empresas').update({
        'frete_economico_valor': ClienteValidators.parseNumero(_valorController.text),
        'frete_economico_prazo_dias': int.tryParse(_prazoController.text.trim()),
      }).eq('id', empresaId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entrega econômica salva!')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Entrega Econômica',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        Text(
          'Modalidade extra, mais barata e mais lenta que a entrega por faixa, oferecida no site e no '
          'WhatsApp. O valor abaixo é o padrão; bairros com valor próprio ficam em "Valor por bairro". '
          'Deixe os dois campos em branco pra não oferecer nos bairros fora da lista.',
          style: TextStyle(fontSize: 12, color: cores.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        if (_carregando)
          const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
        else
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _valorController,
                          decoration: const InputDecoration(labelText: 'Valor padrão (R\$)', prefixText: 'R\$ '),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [MoedaInputFormatter()],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _prazoController,
                          decoration: const InputDecoration(labelText: 'Prazo (dias úteis)'),
                          keyboardType: TextInputType.number,
                          inputFormatters: [InteiroInputFormatter()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: _salvando ? null : _salvar,
                      child: Text(_salvando ? 'Salvando...' : 'Salvar valor padrão'),
                    ),
                  ),
                  const FreteEconomicoBairrosSection(),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
