import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/supabase_config.dart';
import '../providers/auth_provider.dart';
import '../utils/cliente_validators.dart';
import '../utils/formatadores_input.dart';

/// Configurações > Pedidos e Vendas: limites aplicados no balcão — hoje o
/// app não tinha nenhum teto de desconto nem valor mínimo de pedido.
class PedidosVendasScreen extends StatefulWidget {
  const PedidosVendasScreen({super.key});

  @override
  State<PedidosVendasScreen> createState() => _PedidosVendasScreenState();
}

class _PedidosVendasScreenState extends State<PedidosVendasScreen> {
  final _formKey = GlobalKey<FormState>();
  final _descontoMaximoController = TextEditingController();
  final _valorMinimoController = TextEditingController();
  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  @override
  void dispose() {
    _descontoMaximoController.dispose();
    _valorMinimoController.dispose();
    super.dispose();
  }

  Future<void> _carregarDados() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) {
      setState(() => _carregando = false);
      return;
    }

    try {
      final data = await supabase
          .from('empresas')
          .select('desconto_maximo_percentual, valor_minimo_pedido')
          .eq('id', empresaId)
          .single();

      final descontoMaximo = (data['desconto_maximo_percentual'] as num?)?.toDouble();
      final valorMinimo = (data['valor_minimo_pedido'] as num?)?.toDouble();
      if (descontoMaximo != null) _descontoMaximoController.text = ClienteValidators.formatarMoeda(descontoMaximo);
      if (valorMinimo != null) _valorMinimoController.text = ClienteValidators.formatarMoeda(valorMinimo);
    } catch (e) {
      debugPrint('Erro ao carregar regras de venda: $e');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;

    setState(() => _salvando = true);
    try {
      await supabase.from('empresas').update({
        'desconto_maximo_percentual': ClienteValidators.parseNumero(_descontoMaximoController.text),
        'valor_minimo_pedido': ClienteValidators.parseNumero(_valorMinimoController.text),
      }).eq('id', empresaId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Regras de venda salvas com sucesso!')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pedidos e Vendas'),
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
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Regras de Venda',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Deixe em branco pra não aplicar nenhum limite.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _descontoMaximoController,
                      decoration: const InputDecoration(
                        labelText: 'Desconto máximo permitido (Opcional)',
                        suffixText: '%',
                        border: OutlineInputBorder(),
                        helperText: 'Limite de desconto que o caixa pode aplicar numa venda',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [DecimalInputFormatter()],
                      validator: (v) {
                        final valor = ClienteValidators.parseNumero(v);
                        if (valor != null && (valor <= 0 || valor > 100)) return 'Informe um percentual entre 0 e 100';
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _valorMinimoController,
                      decoration: const InputDecoration(
                        labelText: 'Valor mínimo do pedido (Opcional)',
                        prefixText: 'R\$ ',
                        border: OutlineInputBorder(),
                        helperText: 'Impede fechar uma venda de balcão abaixo desse valor',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [MoedaInputFormatter()],
                      validator: (v) {
                        final valor = ClienteValidators.parseNumero(v);
                        if (valor != null && valor < 0) return 'Informe um valor válido';
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _salvando ? null : _salvar,
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: const Text('Salvar'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
