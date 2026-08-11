import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/supabase_config.dart';
import '../providers/auth_provider.dart';
import '../repositories/marketplace_config_repository.dart';
import '../widgets/aviso_banner.dart';
import '../widgets/form_section.dart';

/// Custo real de cada venda, além do custo de produto (Configurações >
/// Custos Operacionais, só dono — mesma sensibilidade de "Pagamento
/// Online"): taxa de maquininha, custo de embalagem e custo de entrega
/// própria são aplicados automaticamente a TODO pedido novo (qualquer
/// canal) por um trigger no banco (`calcular_custos_operacionais_pedido`),
/// e a comissão configurada aqui por marketplace é aplicada por
/// `calcular_comissao_marketplace` assim que o pedido chega. Ver detalhe
/// da venda (`venda_detalhes_screen.dart`, card "Informações internas")
/// pra onde esses valores aparecem.
class CustosOperacionaisScreen extends StatefulWidget {
  const CustosOperacionaisScreen({super.key});

  @override
  State<CustosOperacionaisScreen> createState() => _CustosOperacionaisScreenState();
}

class _ComissaoMarketplace {
  final String marketplaceId;
  final String nome;
  final percentualController = TextEditingController();
  final taxaGatewayController = TextEditingController();
  final taxaFixaController = TextEditingController();
  double? _percentualOriginal;
  double? _taxaGatewayOriginal;
  double? _taxaFixaOriginal;

  _ComissaoMarketplace({required this.marketplaceId, required this.nome});

  void dispose() {
    percentualController.dispose();
    taxaGatewayController.dispose();
    taxaFixaController.dispose();
  }
}

class _CustosOperacionaisScreenState extends State<CustosOperacionaisScreen> {
  final _formKey = GlobalKey<FormState>();

  final _taxaCreditoController = TextEditingController();
  final _taxaDebitoController = TextEditingController();
  final _custoEmbalagemController = TextEditingController();
  final _entregaValorController = TextEditingController();

  String? _entregaModo;
  bool _veiculoDaLoja = false;
  List<_ComissaoMarketplace> _comissoes = [];

  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  @override
  void dispose() {
    _taxaCreditoController.dispose();
    _taxaDebitoController.dispose();
    _custoEmbalagemController.dispose();
    _entregaValorController.dispose();
    for (final c in _comissoes) {
      c.dispose();
    }
    super.dispose();
  }

  String? _formatarNumero(num? valor) => valor == null ? '' : valor.toString();

  Future<void> _carregarDados() async {
    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) {
      if (mounted) setState(() => _carregando = false);
      return;
    }

    try {
      final empresa = await supabase
          .from('empresas')
          .select('taxa_maquininha_credito, taxa_maquininha_debito, custo_embalagem_padrao, '
              'entrega_propria_custo_modo, entrega_propria_custo_valor, entrega_propria_veiculo_da_loja')
          .eq('id', empresaId)
          .single();

      _taxaCreditoController.text = _formatarNumero(empresa['taxa_maquininha_credito'] as num?) ?? '';
      _taxaDebitoController.text = _formatarNumero(empresa['taxa_maquininha_debito'] as num?) ?? '';
      _custoEmbalagemController.text = _formatarNumero(empresa['custo_embalagem_padrao'] as num?) ?? '';
      _entregaValorController.text = _formatarNumero(empresa['entrega_propria_custo_valor'] as num?) ?? '';
      _entregaModo = empresa['entrega_propria_custo_modo'] as String?;
      _veiculoDaLoja = empresa['entrega_propria_veiculo_da_loja'] as bool? ?? false;

      final configs = await MarketplaceConfigRepository().listar();
      final marketplacesAtivos = configs.where((c) => c.ativo).toList();
      if (marketplacesAtivos.isNotEmpty) {
        final marketplacesRows = await supabase
            .from('marketplaces')
            .select('id, nome')
            .inFilter('id', marketplacesAtivos.map((c) => c.marketplaceId).toList());
        final nomesPorId = {for (final r in marketplacesRows) r['id'] as String: r['nome']?.toString() ?? '?'};

        final taxasRows = await supabase
            .from('marketplace_taxas')
            .select('marketplace_id, percentual_comissao, taxa_gateway, taxa_fixa')
            .eq('empresa_id', empresaId)
            .isFilter('vigencia_fim', null);
        final taxasPorMarketplace = {for (final r in taxasRows) r['marketplace_id'] as String: r};

        _comissoes = marketplacesAtivos.map((config) {
          final comissao = _ComissaoMarketplace(
            marketplaceId: config.marketplaceId,
            nome: nomesPorId[config.marketplaceId] ?? config.marketplaceId,
          );
          final taxaAtual = taxasPorMarketplace[config.marketplaceId];
          if (taxaAtual != null) {
            comissao._percentualOriginal = (taxaAtual['percentual_comissao'] as num?)?.toDouble();
            comissao._taxaGatewayOriginal = (taxaAtual['taxa_gateway'] as num?)?.toDouble();
            comissao._taxaFixaOriginal = (taxaAtual['taxa_fixa'] as num?)?.toDouble();
            comissao.percentualController.text = _formatarNumero(taxaAtual['percentual_comissao'] as num?) ?? '';
            comissao.taxaGatewayController.text = _formatarNumero(taxaAtual['taxa_gateway'] as num?) ?? '';
            comissao.taxaFixaController.text = _formatarNumero(taxaAtual['taxa_fixa'] as num?) ?? '';
          }
          return comissao;
        }).toList();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar custos operacionais: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  double? _parseNumero(String texto) {
    if (texto.trim().isEmpty) return null;
    return double.tryParse(texto.trim().replaceAll(',', '.'));
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;

    setState(() => _salvando = true);
    try {
      await supabase.from('empresas').update({
        'taxa_maquininha_credito': _parseNumero(_taxaCreditoController.text),
        'taxa_maquininha_debito': _parseNumero(_taxaDebitoController.text),
        'custo_embalagem_padrao': _parseNumero(_custoEmbalagemController.text),
        'entrega_propria_custo_modo': _entregaModo,
        'entrega_propria_custo_valor': _parseNumero(_entregaValorController.text),
        'entrega_propria_veiculo_da_loja': _veiculoDaLoja,
      }).eq('id', empresaId);

      // marketplace_taxas guarda histórico por vigência — só abre uma linha
      // nova quando o valor realmente mudou (senão, salvar sem mexer em
      // nada criaria uma vigência nova a cada clique em "Salvar").
      for (final comissao in _comissoes) {
        final percentual = _parseNumero(comissao.percentualController.text);
        final taxaGateway = _parseNumero(comissao.taxaGatewayController.text);
        final taxaFixa = _parseNumero(comissao.taxaFixaController.text);
        final mudou = percentual != comissao._percentualOriginal ||
            taxaGateway != comissao._taxaGatewayOriginal ||
            taxaFixa != comissao._taxaFixaOriginal;
        if (!mudou || percentual == null) continue;

        final hoje = DateTime.now().toIso8601String().split('T').first;
        await supabase
            .from('marketplace_taxas')
            .update({'vigencia_fim': hoje})
            .eq('empresa_id', empresaId)
            .eq('marketplace_id', comissao.marketplaceId)
            .isFilter('vigencia_fim', null);

        await supabase.from('marketplace_taxas').insert({
          'empresa_id': empresaId,
          'marketplace_id': comissao.marketplaceId,
          'vigencia_inicio': hoje,
          'percentual_comissao': percentual,
          'taxa_gateway': taxaGateway ?? 0,
          'taxa_fixa': taxaFixa ?? 0,
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Custos operacionais salvos! Valem a partir do próximo pedido.')),
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

  String? _validarPercentual(String? valor) {
    if (valor == null || valor.isEmpty) return null;
    final numero = _parseNumero(valor);
    if (numero == null) return 'Número inválido';
    if (numero < 0 || numero > 100) return 'Entre 0 e 100';
    return null;
  }

  String? _validarValor(String? valor) {
    if (valor == null || valor.isEmpty) return null;
    if (_parseNumero(valor) == null) return 'Número inválido';
    return null;
  }

  Widget _chipModo(String modo, String label, {required bool habilitado}) {
    final selecionado = _entregaModo == modo;
    final chip = ChoiceChip(
      label: Text(label),
      selected: selecionado,
      onSelected: habilitado ? (_) => setState(() => _entregaModo = modo) : null,
    );
    if (habilitado) return chip;
    return Tooltip(
      message: 'Disponível quando o módulo de rotas de entrega existir',
      child: chip,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Custos Operacionais'),
        actions: [
          _salvando
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : IconButton(icon: const Icon(Icons.save), onPressed: _salvar),
        ],
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AvisoBanner(
                      icone: Icons.insights_outlined,
                      texto: 'Esses valores são usados pra calcular o lucro líquido real de cada venda '
                          '(ver "Informações internas" no detalhe da venda) — descontando o que a loja '
                          'realmente paga, além do custo do produto.',
                    ),
                    const SizedBox(height: 20),
                    FormSection(
                      titulo: 'Maquininha de cartão',
                      children: [
                        Text(
                          'Só se aplica a pagamento com cartão cobrado na entrega/loja física — '
                          'Mercado Pago (pagamento online do site) e marketplaces têm taxa própria.',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        TextFormField(
                          controller: _taxaCreditoController,
                          decoration: const InputDecoration(labelText: 'Taxa no crédito (%)', suffixText: '%'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: _validarPercentual,
                        ),
                        TextFormField(
                          controller: _taxaDebitoController,
                          decoration: const InputDecoration(labelText: 'Taxa no débito (%)', suffixText: '%'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: _validarPercentual,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FormSection(
                      titulo: 'Embalagem',
                      children: [
                        TextFormField(
                          controller: _custoEmbalagemController,
                          decoration: const InputDecoration(
                            labelText: 'Custo fixo por pedido (R\$)',
                            prefixText: 'R\$ ',
                            helperText: 'Aplicado em todo pedido, de qualquer canal',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: _validarValor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FormSection(
                      titulo: 'Entrega própria',
                      children: [
                        Text(
                          'Como calcular o custo por pedido — inclui pedidos de marketplace '
                          '(iFood/99Food), já que hoje são entregues pela própria loja.',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _chipModo('fixo', 'Valor fixo por entrega', habilitado: true),
                            _chipModo('km', 'Valor por km rodado', habilitado: true),
                            _chipModo('salario', 'Salário fixo', habilitado: false),
                            _chipModo('rota', 'Por rota (múltiplas entregas)', habilitado: false),
                          ],
                        ),
                        if (_entregaModo == 'fixo' || _entregaModo == 'km')
                          TextFormField(
                            controller: _entregaValorController,
                            decoration: InputDecoration(
                              labelText: _entregaModo == 'km' ? 'Valor por km (R\$)' : 'Valor por entrega (R\$)',
                              prefixText: 'R\$ ',
                            ),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            validator: _validarValor,
                          ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Moto/veículo é da loja'),
                          subtitle: const Text('Informativo por enquanto — não muda o cálculo'),
                          value: _veiculoDaLoja,
                          onChanged: (v) => setState(() => _veiculoDaLoja = v),
                        ),
                      ],
                    ),
                    if (_comissoes.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      FormSection(
                        titulo: 'Comissão de marketplace',
                        children: _comissoes.expand((comissao) => [
                              Text(comissao.nome, style: const TextStyle(fontWeight: FontWeight.bold)),
                              if (_comissoes.first == comissao)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    'Só os percentuais cobrados POR PEDIDO entram aqui. Mensalidade fixa '
                                    '(ex: taxa de adesão/plano do iFood) não é custo por venda — cadastre '
                                    'como despesa RECORRENTE em Configurações > Despesas (gera sozinha todo '
                                    'mês), senão o lucro por pedido fica impreciso, oscilando com o volume '
                                    'de vendas do mês.',
                                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ),
                                ),
                              TextFormField(
                                controller: comissao.percentualController,
                                decoration: const InputDecoration(labelText: 'Comissão (%)', suffixText: '%'),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                validator: _validarPercentual,
                              ),
                              TextFormField(
                                controller: comissao.taxaGatewayController,
                                decoration: const InputDecoration(
                                  labelText: 'Taxa de pagamento online (%)',
                                  suffixText: '%',
                                  helperText: 'Separada da comissão — cobrada pelo processamento do pagamento',
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                validator: _validarPercentual,
                              ),
                              TextFormField(
                                controller: comissao.taxaFixaController,
                                decoration: const InputDecoration(
                                  labelText: 'Taxa fixa por pedido (R\$, opcional)',
                                  prefixText: 'R\$ ',
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                validator: _validarValor,
                              ),
                            ]).toList(),
                      ),
                    ],
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _salvando ? null : _salvar,
                      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                      child: const Text('Salvar'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
