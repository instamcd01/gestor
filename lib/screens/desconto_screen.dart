import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/supabase_config.dart';
import '../providers/auth_provider.dart';
import '../utils/cliente_validators.dart';
import '../utils/formatadores_input.dart';

class DescontoScreen extends StatefulWidget {
  final double valorTotal;

  DescontoScreen({required this.valorTotal});

  @override
  _DescontoScreenState createState() => _DescontoScreenState();
}

class _DescontoScreenState extends State<DescontoScreen> {
  double descontoValor = 0.0;
  double descontoPercentual = 0.0;
  double? _descontoMaximoPercentual;

  final TextEditingController _valorController = TextEditingController();
  final TextEditingController _percentualController = TextEditingController();

  bool _atualizando = false; // Para evitar loop de atualização

  @override
  void initState() {
    super.initState();
    _carregarLimiteDesconto();
  }

  Future<void> _carregarLimiteDesconto() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;
    try {
      final data = await supabase
          .from('empresas')
          .select('desconto_maximo_percentual')
          .eq('id', empresaId)
          .single();
      final limite = (data['desconto_maximo_percentual'] as num?)?.toDouble();
      if (mounted) setState(() => _descontoMaximoPercentual = limite);
    } catch (e) {
      debugPrint('Erro ao carregar limite de desconto: $e');
    }
  }

  @override
  void dispose() {
    _valorController.dispose();
    _percentualController.dispose();
    super.dispose();
  }

  double get _percentualMaximoEfetivo => _descontoMaximoPercentual ?? 100;

  void _mostrarAvisoLimite() {
    final limite = _descontoMaximoPercentual;
    if (limite == null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Desconto máximo permitido: ${limite.toStringAsFixed(0)}%')),
    );
  }

  void _atualizarValor(String value) {
    if (_atualizando) return;
    _atualizando = true;

    setState(() {
      descontoValor = ClienteValidators.parseNumero(value) ?? 0.0;
      if (descontoValor > widget.valorTotal) descontoValor = widget.valorTotal;

      final valorMaximoPeloLimite = (_percentualMaximoEfetivo / 100) * widget.valorTotal;
      if (descontoValor > valorMaximoPeloLimite) {
        descontoValor = valorMaximoPeloLimite;
        _mostrarAvisoLimite();
      }

      // Atualiza percentual
      descontoPercentual = widget.valorTotal == 0 ? 0 : (descontoValor / widget.valorTotal) * 100;
      _percentualController.text = ClienteValidators.formatarMoeda(descontoPercentual);
    });

    _atualizando = false;
  }

  void _atualizarPercentual(String value) {
    if (_atualizando) return;
    _atualizando = true;

    setState(() {
      descontoPercentual = ClienteValidators.parseNumero(value) ?? 0.0;
      if (descontoPercentual > _percentualMaximoEfetivo) {
        descontoPercentual = _percentualMaximoEfetivo;
        _mostrarAvisoLimite();
      }

      // Atualiza valor
      descontoValor = (descontoPercentual / 100) * widget.valorTotal;
      _valorController.text = ClienteValidators.formatarMoeda(descontoValor);
    });

    _atualizando = false;
  }

  double get valorFinal {
    double finalValue = widget.valorTotal - descontoValor;
    if (finalValue < 0) finalValue = 0.0;
    return finalValue;
  }

  void resetar() {
    setState(() {
      descontoValor = 0.0;
      descontoPercentual = 0.0;
      _valorController.clear();
      _percentualController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Aplicar Desconto'),
        actions: [
          IconButton(
            icon: Icon(Icons.clear),
            tooltip: 'Limpar',
            onPressed: resetar,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _valorController,
              decoration: InputDecoration(
                labelText: 'Desconto em Valor (R\$)',
                prefixText: 'R\$ ',
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [MoedaInputFormatter()],
              onChanged: _atualizarValor,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _percentualController,
              decoration: InputDecoration(
                labelText: 'Desconto Percentual (%)',
                suffixText: '%',
                helperText: _descontoMaximoPercentual != null
                    ? 'Máximo permitido: ${_descontoMaximoPercentual!.toStringAsFixed(0)}%'
                    : null,
              ),
              inputFormatters: [DecimalInputFormatter()],
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              onChanged: _atualizarPercentual,
            ),
            const SizedBox(height: 20),
            Card(
              margin: EdgeInsets.zero,
              color: colorScheme.primary.withValues(alpha: 0.08),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text('Valor final', style: TextStyle(color: colorScheme.onSurfaceVariant)),
                    const SizedBox(height: 4),
                    Text(
                      'R\$ ${valorFinal.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                    ),
                    if (widget.valorTotal > 0 && descontoValor > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        'de R\$ ${widget.valorTotal.toStringAsFixed(2)} — ${descontoPercentual.toStringAsFixed(1)}% off',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context, valorFinal); // retorna o valor do desconto
              },
              style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
              child: Text('Aplicar Desconto'),
            ),
          ],
        ),
      ),
    );
  }
}
