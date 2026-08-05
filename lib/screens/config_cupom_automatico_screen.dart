import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/supabase_config.dart';
import '../models/cupom.dart';
import '../providers/auth_provider.dart';
import '../utils/formatadores_input.dart';
import '../utils/produto_validators.dart';
import '../widgets/form_section.dart';

/// Regra de geração automática de cupom — pro cliente (no cadastro,
/// trigger gerar_cupom_boas_vindas) e pro vendedor (código de indicação,
/// trigger gerar_cupom_vendedor). Segue o mesmo padrão de DescontoScreen/
/// PedidosVendasScreen: lê/grava colunas soltas em `empresas` direto,
/// sem repository/provider dedicado.
class ConfigCupomAutomaticoScreen extends StatefulWidget {
  const ConfigCupomAutomaticoScreen({super.key});

  @override
  State<ConfigCupomAutomaticoScreen> createState() => _ConfigCupomAutomaticoScreenState();
}

class _ConfigCupomAutomaticoScreenState extends State<ConfigCupomAutomaticoScreen> {
  bool _carregando = true;
  bool _salvando = false;

  bool _boasVindasAtivo = false;
  TipoDescontoCupom _boasVindasTipo = TipoDescontoCupom.percentual;
  final _boasVindasValorController = TextEditingController();
  final _boasVindasValidadeController = TextEditingController();

  bool _vendedorAtivo = false;
  TipoDescontoCupom _vendedorTipo = TipoDescontoCupom.percentual;
  final _vendedorValorController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _boasVindasValorController.dispose();
    _boasVindasValidadeController.dispose();
    _vendedorValorController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;
    try {
      final data = await supabase
          .from('empresas')
          .select(
              'cupom_boas_vindas_ativo, cupom_boas_vindas_tipo_desconto, cupom_boas_vindas_valor, cupom_boas_vindas_validade_dias, cupom_vendedor_ativo, cupom_vendedor_tipo_desconto, cupom_vendedor_valor')
          .eq('id', empresaId)
          .single();

      if (!mounted) return;
      setState(() {
        _boasVindasAtivo = data['cupom_boas_vindas_ativo'] as bool? ?? false;
        _boasVindasTipo = tipoDescontoDeTexto(data['cupom_boas_vindas_tipo_desconto']?.toString());
        final valorBoasVindas = (data['cupom_boas_vindas_valor'] as num?)?.toDouble();
        if (valorBoasVindas != null) {
          _boasVindasValorController.text = ProdutoValidators.formatarMoeda(valorBoasVindas);
        }
        final validade = data['cupom_boas_vindas_validade_dias'] as int?;
        if (validade != null) _boasVindasValidadeController.text = validade.toString();

        _vendedorAtivo = data['cupom_vendedor_ativo'] as bool? ?? false;
        _vendedorTipo = tipoDescontoDeTexto(data['cupom_vendedor_tipo_desconto']?.toString());
        final valorVendedor = (data['cupom_vendedor_valor'] as num?)?.toDouble();
        if (valorVendedor != null) {
          _vendedorValorController.text = ProdutoValidators.formatarMoeda(valorVendedor);
        }
      });
    } catch (e) {
      debugPrint('Erro ao carregar configuração de cupom automático: $e');
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
        'cupom_boas_vindas_ativo': _boasVindasAtivo,
        'cupom_boas_vindas_tipo_desconto': tipoDescontoParaTexto(_boasVindasTipo),
        'cupom_boas_vindas_valor': ProdutoValidators.parseNumero(_boasVindasValorController.text),
        'cupom_boas_vindas_validade_dias': int.tryParse(_boasVindasValidadeController.text.trim()),
        'cupom_vendedor_ativo': _vendedorAtivo,
        'cupom_vendedor_tipo_desconto': tipoDescontoParaTexto(_vendedorTipo),
        'cupom_vendedor_valor': ProdutoValidators.parseNumero(_vendedorValorController.text),
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
      appBar: AppBar(title: const Text('Cupom Automático')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormSection(
              titulo: 'Boas-vindas pro cliente',
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Gerar automaticamente no cadastro'),
                  subtitle: const Text('Todo cliente novo ganha um cupom só dele.'),
                  value: _boasVindasAtivo,
                  onChanged: (v) => setState(() => _boasVindasAtivo = v),
                ),
                if (_boasVindasAtivo) ...[
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<TipoDescontoCupom>(
                          initialValue: _boasVindasTipo,
                          decoration: const InputDecoration(labelText: 'Tipo'),
                          items: const [
                            DropdownMenuItem(value: TipoDescontoCupom.percentual, child: Text('Percentual (%)')),
                            DropdownMenuItem(value: TipoDescontoCupom.fixo, child: Text('Valor fixo (R\$)')),
                          ],
                          onChanged: (v) => setState(() => _boasVindasTipo = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _boasVindasValorController,
                          decoration: const InputDecoration(labelText: 'Valor'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [DecimalInputFormatter()],
                        ),
                      ),
                    ],
                  ),
                  TextFormField(
                    controller: _boasVindasValidadeController,
                    decoration: const InputDecoration(
                      labelText: 'Validade (dias)',
                      helperText: 'Vazio = sem expiração',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            FormSection(
              titulo: 'Código de indicação do vendedor',
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Gerar automaticamente pra cada vendedor'),
                  subtitle: const Text('O vendedor divulga o código; ao usar, credita a venda a ele.'),
                  value: _vendedorAtivo,
                  onChanged: (v) => setState(() => _vendedorAtivo = v),
                ),
                if (_vendedorAtivo)
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<TipoDescontoCupom>(
                          initialValue: _vendedorTipo,
                          decoration: const InputDecoration(labelText: 'Tipo'),
                          items: const [
                            DropdownMenuItem(value: TipoDescontoCupom.percentual, child: Text('Percentual (%)')),
                            DropdownMenuItem(value: TipoDescontoCupom.fixo, child: Text('Valor fixo (R\$)')),
                          ],
                          onChanged: (v) => setState(() => _vendedorTipo = v!),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _vendedorValorController,
                          decoration: const InputDecoration(labelText: 'Valor'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [DecimalInputFormatter()],
                        ),
                      ),
                    ],
                  ),
              ],
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
