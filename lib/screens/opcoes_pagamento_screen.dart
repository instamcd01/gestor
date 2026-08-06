import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/supabase_config.dart';
import '../providers/auth_provider.dart';
import '../utils/cliente_validators.dart';
import '../widgets/form_section.dart';

const metodosPagamentoDisponiveis = [
  'Dinheiro',
  'Cartão de Débito',
  'Cartão de Crédito',
  'Pix',
  'Link de Pagamento',
  'Outros',
];

/// Chave salva em `empresas.bandeiras_aceitas` — mostrada como ícone/rótulo
/// no checkout do site (só exibição, sem validação real: a maquininha
/// física é quem de fato aceita ou recusa o cartão).
const bandeirasCartaoDisponiveis = [
  ('visa', 'Visa'),
  ('mastercard', 'Mastercard'),
  ('elo', 'Elo'),
  ('amex', 'American Express'),
  ('hipercard', 'Hipercard'),
  ('diners', 'Diners Club'),
];

const _parcelaMaxima = 12;

/// Configurações > Opções de Pagamento: quais métodos aparecem na tela de
/// pagamento do balcão, e a chave Pix mostrada ao caixa (pagamento continua
/// sendo feito numa maquininha/Pix físico à parte — o app só registra).
class OpcoesPagamentoScreen extends StatefulWidget {
  const OpcoesPagamentoScreen({super.key});

  @override
  State<OpcoesPagamentoScreen> createState() => _OpcoesPagamentoScreenState();
}

class _OpcoesPagamentoScreenState extends State<OpcoesPagamentoScreen> {
  final _chavePixController = TextEditingController();
  final Set<String> _metodosAtivos = {...metodosPagamentoDisponiveis};
  final Set<String> _bandeirasAtivas = {};
  // Parcela 1 (à vista) sempre oferecida — não faz sentido desligar.
  final Set<int> _parcelasAtivas = {1};
  final Map<int, TextEditingController> _jurosControllers = {
    for (var n = 1; n <= _parcelaMaxima; n++) n: TextEditingController(text: n == 1 ? '0' : ''),
  };
  final _valorMinimoParcelaController = TextEditingController(text: '5');
  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  @override
  void dispose() {
    _chavePixController.dispose();
    for (final c in _jurosControllers.values) {
      c.dispose();
    }
    _valorMinimoParcelaController.dispose();
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
          .select('metodos_pagamento_ativos, chave_pix, bandeiras_aceitas, taxas_parcelamento, valor_minimo_parcela')
          .eq('id', empresaId)
          .single();

      final metodos = data['metodos_pagamento_ativos'] as List?;
      if (metodos != null) {
        _metodosAtivos
          ..clear()
          ..addAll(metodos.map((m) => m.toString()));
      }
      _chavePixController.text = data['chave_pix']?.toString() ?? '';

      final bandeiras = data['bandeiras_aceitas'] as List?;
      if (bandeiras != null) {
        _bandeirasAtivas
          ..clear()
          ..addAll(bandeiras.map((b) => b.toString()));
      }

      final taxas = data['taxas_parcelamento'] as Map<String, dynamic>?;
      if (taxas != null) {
        _parcelasAtivas.clear();
        for (final entry in taxas.entries) {
          final n = int.tryParse(entry.key);
          if (n == null || n < 1 || n > _parcelaMaxima) continue;
          _parcelasAtivas.add(n);
          _jurosControllers[n]!.text = ClienteValidators.formatarMoeda((entry.value as num).toDouble());
        }
      }

      final valorMinimoParcela = data['valor_minimo_parcela'] as num?;
      if (valorMinimoParcela != null) {
        _valorMinimoParcelaController.text = ClienteValidators.formatarMoeda(valorMinimoParcela.toDouble());
      }
    } catch (e) {
      debugPrint('Erro ao carregar opções de pagamento: $e');
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _salvar() async {
    if (_metodosAtivos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pelo menos uma forma de pagamento precisa ficar ativa.')),
      );
      return;
    }

    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;

    final taxasParcelamento = {
      for (final n in _parcelasAtivas)
        n.toString(): ClienteValidators.parseNumero(_jurosControllers[n]!.text) ?? 0,
    };
    final valorMinimoParcela = ClienteValidators.parseNumero(_valorMinimoParcelaController.text) ?? 5;

    setState(() => _salvando = true);
    try {
      await supabase.from('empresas').update({
        'metodos_pagamento_ativos': _metodosAtivos.toList(),
        'chave_pix': _chavePixController.text.trim(),
        'bandeiras_aceitas': _bandeirasAtivas.toList(),
        'taxas_parcelamento': taxasParcelamento,
        'valor_minimo_parcela': valorMinimoParcela,
      }).eq('id', empresaId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Opções de pagamento salvas com sucesso!')),
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
        title: const Text('Opções de Pagamento'),
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
                FormSection(
                  titulo: 'Formas de pagamento aceitas no balcão',
                  children: [
                    Text(
                      'Desmarque as que sua loja não usa — elas somem da tela de pagamento.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                    ),
                    Column(
                      children: metodosPagamentoDisponiveis
                          .map((metodo) => CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(metodo),
                                value: _metodosAtivos.contains(metodo),
                                onChanged: (v) => setState(() {
                                  if (v == true) {
                                    _metodosAtivos.add(metodo);
                                  } else {
                                    _metodosAtivos.remove(metodo);
                                  }
                                }),
                              ))
                          .toList(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FormSection(
                  titulo: 'Pix',
                  children: [
                    TextField(
                      controller: _chavePixController,
                      decoration: const InputDecoration(
                        labelText: 'Chave Pix (Opcional)',
                        helperText: 'Mostrada ao caixa na tela de pagamento via Pix',
                      ),
                      inputFormatters: [FilteringTextInputFormatter.singleLineFormatter],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FormSection(
                  titulo: 'Bandeiras de cartão aceitas',
                  children: [
                    Text(
                      'Só pra exibir no site — a maquininha é quem decide de verdade se aceita o cartão.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: bandeirasCartaoDisponiveis.map((bandeira) {
                        final (chave, nome) = bandeira;
                        return FilterChip(
                          label: Text(nome),
                          selected: _bandeirasAtivas.contains(chave),
                          onSelected: (v) => setState(() {
                            if (v) {
                              _bandeirasAtivas.add(chave);
                            } else {
                              _bandeirasAtivas.remove(chave);
                            }
                          }),
                        );
                      }).toList(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FormSection(
                  titulo: 'Parcelamento no cartão de crédito',
                  children: [
                    Text(
                      'Marque quantas parcelas sua maquininha oferece e a taxa de juros de cada uma — '
                      'o site mostra o valor de cada parcela já com o juros aplicado. A cobrança real '
                      'continua acontecendo na maquininha, na entrega/retirada.',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                    ),
                    for (var n = 1; n <= _parcelaMaxima; n++)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Checkbox(
                              value: _parcelasAtivas.contains(n),
                              // Parcela 1 (à vista) não pode ser desligada.
                              onChanged: n == 1
                                  ? null
                                  : (v) => setState(() {
                                        if (v == true) {
                                          _parcelasAtivas.add(n);
                                        } else {
                                          _parcelasAtivas.remove(n);
                                        }
                                      }),
                            ),
                            SizedBox(width: 56, child: Text(n == 1 ? '1x (à vista)' : '${n}x')),
                            Expanded(
                              child: TextField(
                                controller: _jurosControllers[n],
                                enabled: _parcelasAtivas.contains(n),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  suffixText: '% de juros',
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _valorMinimoParcelaController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Valor mínimo por parcela',
                        prefixText: 'R\$ ',
                        helperText: 'Abaixo disso (2x em diante), a parcela some das opções no site.',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
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
