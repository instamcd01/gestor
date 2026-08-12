import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/supabase_config.dart';
import '../providers/auth_provider.dart';
import '../utils/formatadores_input.dart';
import '../utils/produto_validators.dart';
import '../widgets/aviso_banner.dart';
import '../widgets/form_section.dart';

/// Configuração do PetCash (cashback automático) — mesmo padrão de
/// leitura/escrita direta em colunas de `empresas` já usado em
/// ConfigCupomAutomaticoScreen/DescontoScreen, sem repository dedicado.
/// Só concede em pedidos do site quando entregues (ver trigger
/// gerar_petcash_pedido) — desligar aqui não afeta o PetCash já
/// concedido, que o cliente continua podendo gastar.
class ConfigPetCashScreen extends StatefulWidget {
  const ConfigPetCashScreen({super.key});

  @override
  State<ConfigPetCashScreen> createState() => _ConfigPetCashScreenState();
}

class _ConfigPetCashScreenState extends State<ConfigPetCashScreen> {
  bool _carregando = true;
  bool _salvando = false;

  bool _ativo = false;
  final _percentualController = TextEditingController();
  final _validadeController = TextEditingController(text: '60');
  final _usoMaximoController = TextEditingController(text: '20');
  final _pedidoMinimoController = TextEditingController(text: '50');

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _percentualController.dispose();
    _validadeController.dispose();
    _usoMaximoController.dispose();
    _pedidoMinimoController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;
    try {
      final data = await supabase
          .from('empresas')
          .select(
              'petcash_ativo, petcash_percentual, petcash_validade_dias, petcash_uso_maximo_percentual, petcash_pedido_minimo_uso')
          .eq('id', empresaId)
          .single();

      if (!mounted) return;
      setState(() {
        _ativo = data['petcash_ativo'] as bool? ?? false;
        final percentual = (data['petcash_percentual'] as num?)?.toDouble();
        if (percentual != null) _percentualController.text = ProdutoValidators.formatarMoeda(percentual);
        final validade = data['petcash_validade_dias'] as int?;
        if (validade != null) _validadeController.text = validade.toString();
        final usoMaximo = (data['petcash_uso_maximo_percentual'] as num?)?.toDouble();
        if (usoMaximo != null) _usoMaximoController.text = ProdutoValidators.formatarMoeda(usoMaximo);
        final pedidoMinimo = (data['petcash_pedido_minimo_uso'] as num?)?.toDouble();
        if (pedidoMinimo != null) _pedidoMinimoController.text = ProdutoValidators.formatarMoeda(pedidoMinimo);
      });
    } catch (e) {
      debugPrint('Erro ao carregar configuração de PetCash: $e');
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
        'petcash_ativo': _ativo,
        'petcash_percentual': ProdutoValidators.parseNumero(_percentualController.text),
        'petcash_validade_dias': int.tryParse(_validadeController.text.trim()) ?? 60,
        'petcash_uso_maximo_percentual': ProdutoValidators.parseNumero(_usoMaximoController.text),
        'petcash_pedido_minimo_uso': ProdutoValidators.parseNumero(_pedidoMinimoController.text),
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
      appBar: AppBar(title: const Text('🐾 PetCash')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AvisoBanner(
              texto: 'Cliente ganha um percentual de volta em crédito (PetCash) quando um pedido do SITE é '
                  'entregue — pra usar em compras futuras, incentivando ele a voltar. Não afeta vendas na loja '
                  'física, WhatsApp ou marketplaces.',
            ),
            const SizedBox(height: 16),
            FormSection(
              titulo: 'Cashback automático',
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ativar PetCash'),
                  subtitle: const Text('Desligar não afeta o PetCash que os clientes já têm — só para novos créditos.'),
                  value: _ativo,
                  onChanged: (v) => setState(() => _ativo = v),
                ),
                if (_ativo) ...[
                  TextFormField(
                    controller: _percentualController,
                    decoration: const InputDecoration(
                      labelText: 'Percentual do pedido',
                      suffixText: '%',
                      helperText: 'Sobre o valor dos produtos — nunca sobre frete/taxa de serviço.',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [DecimalInputFormatter()],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _validadeController,
                    decoration: const InputDecoration(
                      labelText: 'Validade do crédito (dias)',
                      helperText: 'Contados da data em que o PetCash foi concedido.',
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            FormSection(
              titulo: 'Limites de uso',
              children: [
                TextFormField(
                  controller: _usoMaximoController,
                  decoration: const InputDecoration(
                    labelText: 'Uso máximo por pedido',
                    suffixText: '%',
                    helperText: 'Até quanto do valor do pedido pode ser pago com PetCash.',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [DecimalInputFormatter()],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _pedidoMinimoController,
                  decoration: const InputDecoration(
                    labelText: 'Pedido mínimo pra usar',
                    prefixText: 'R\$ ',
                    helperText: 'Pedidos abaixo desse valor não podem usar PetCash.',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [DecimalInputFormatter()],
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
