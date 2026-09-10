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

  // Custo real da moto + pagamento ao entregador — alimenta a análise de
  // Rentabilidade por Zona (Estatísticas), não o cálculo automático de
  // custo_entrega_valor por pedido (que continua usando o modo/valor
  // simples acima) — são parâmetros pra simular cenário, editáveis a
  // qualquer momento enquanto o modelo de pagamento ainda não é
  // definitivo.
  final _motoValorController = TextEditingController();
  final _motoConsumoController = TextEditingController();
  final _motoCombustivelPrecoController = TextEditingController();
  final _motoKmMesController = TextEditingController();
  final _motoManutencaoController = TextEditingController();
  final _entregadorBaseController = TextEditingController();
  final _entregadorLimiarKmController = TextEditingController();
  final _entregadorBonusTurnoController = TextEditingController();
  final _mediaEntregasPorRotaController = TextEditingController();

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
    _motoValorController.dispose();
    _motoConsumoController.dispose();
    _motoCombustivelPrecoController.dispose();
    _motoKmMesController.dispose();
    _motoManutencaoController.dispose();
    _entregadorBaseController.dispose();
    _entregadorLimiarKmController.dispose();
    _entregadorBonusTurnoController.dispose();
    _mediaEntregasPorRotaController.dispose();
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
              'entrega_propria_custo_modo, entrega_propria_custo_valor, entrega_propria_veiculo_da_loja, '
              'moto_valor_compra, moto_consumo_km_por_litro, moto_combustivel_preco_litro, '
              'moto_km_rodado_mes_estimado, moto_manutencao_valor_por_km, '
              'entregador_pagamento_base, entregador_limiar_km_distancia, entregador_bonus_turno_medio, '
              'media_entregas_por_rota')
          .eq('id', empresaId)
          .single();

      _taxaCreditoController.text = _formatarNumero(empresa['taxa_maquininha_credito'] as num?) ?? '';
      _taxaDebitoController.text = _formatarNumero(empresa['taxa_maquininha_debito'] as num?) ?? '';
      _custoEmbalagemController.text = _formatarNumero(empresa['custo_embalagem_padrao'] as num?) ?? '';
      _entregaValorController.text = _formatarNumero(empresa['entrega_propria_custo_valor'] as num?) ?? '';
      _entregaModo = empresa['entrega_propria_custo_modo'] as String?;
      _veiculoDaLoja = empresa['entrega_propria_veiculo_da_loja'] as bool? ?? false;
      _motoValorController.text = _formatarNumero(empresa['moto_valor_compra'] as num?) ?? '';
      _motoConsumoController.text = _formatarNumero(empresa['moto_consumo_km_por_litro'] as num?) ?? '';
      _motoCombustivelPrecoController.text = _formatarNumero(empresa['moto_combustivel_preco_litro'] as num?) ?? '';
      _motoKmMesController.text = _formatarNumero(empresa['moto_km_rodado_mes_estimado'] as num?) ?? '';
      _motoManutencaoController.text = _formatarNumero(empresa['moto_manutencao_valor_por_km'] as num?) ?? '';
      _entregadorBaseController.text = _formatarNumero(empresa['entregador_pagamento_base'] as num?) ?? '';
      _entregadorLimiarKmController.text = _formatarNumero(empresa['entregador_limiar_km_distancia'] as num?) ?? '';
      _entregadorBonusTurnoController.text = _formatarNumero(empresa['entregador_bonus_turno_medio'] as num?) ?? '';
      _mediaEntregasPorRotaController.text = _formatarNumero(empresa['media_entregas_por_rota'] as num?) ?? '';

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
        'moto_valor_compra': _parseNumero(_motoValorController.text),
        'moto_consumo_km_por_litro': _parseNumero(_motoConsumoController.text),
        'moto_combustivel_preco_litro': _parseNumero(_motoCombustivelPrecoController.text),
        'moto_km_rodado_mes_estimado': _parseNumero(_motoKmMesController.text),
        'moto_manutencao_valor_por_km': _parseNumero(_motoManutencaoController.text),
        'entregador_pagamento_base': _parseNumero(_entregadorBaseController.text),
        'entregador_limiar_km_distancia': _parseNumero(_entregadorLimiarKmController.text),
        'entregador_bonus_turno_medio': _parseNumero(_entregadorBonusTurnoController.text),
        'media_entregas_por_rota': _parseNumero(_mediaEntregasPorRotaController.text),
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
                    const SizedBox(height: 16),
                    FormSection(
                      titulo: 'Custo real da moto (análise de rentabilidade por zona)',
                      children: [
                        Text(
                          'Não muda o custo automático por pedido acima — alimenta só a análise de '
                          'Rentabilidade por Zona (Estatísticas), pra mostrar o custo real de rodar a moto '
                          '(combustível, manutenção, depreciação) por km, separado do que você paga ao '
                          'entregador. Ajuste sempre que quiser testar um cenário diferente.',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _motoValorController,
                          decoration: const InputDecoration(
                            labelText: 'Valor de compra/mercado da moto (R\$)',
                            prefixText: 'R\$ ',
                            helperText: 'Usado pra estimar depreciação (~0,8% ao mês, referência real de mercado)',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: _validarValor,
                        ),
                        TextFormField(
                          controller: _motoConsumoController,
                          decoration: const InputDecoration(labelText: 'Consumo (km por litro)', suffixText: 'km/L'),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: _validarValor,
                        ),
                        TextFormField(
                          controller: _motoCombustivelPrecoController,
                          decoration: const InputDecoration(
                            labelText: 'Preço do combustível (R\$/litro)',
                            prefixText: 'R\$ ',
                            helperText: 'Atualize sempre que o preço mudar de verdade',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: _validarValor,
                        ),
                        TextFormField(
                          controller: _motoManutencaoController,
                          decoration: const InputDecoration(
                            labelText: 'Manutenção por km (R\$/km)',
                            prefixText: 'R\$ ',
                            helperText: 'Faixa real de mercado pra moto urbana: R\$0,15 a R\$0,30/km — troque pelo seu gasto real ÷ km rodado assim que tiver uns meses de histórico',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: _validarValor,
                        ),
                        TextFormField(
                          controller: _motoKmMesController,
                          decoration: const InputDecoration(
                            labelText: 'Km rodado por mês (opcional)',
                            suffixText: 'km',
                            helperText: 'Deixe em branco até ter dado real (ex: quando o app do entregador estiver medindo) — sem isso, a depreciação não entra na conta',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: _validarValor,
                        ),
                        TextFormField(
                          controller: _mediaEntregasPorRotaController,
                          decoration: const InputDecoration(
                            labelText: 'Entregas por rota/viagem (em média)',
                            suffixText: 'entregas',
                            helperText: 'Quantas entregas costumam sair juntas na mesma viagem — a ida-e-volta da moto é '
                                'rateada entre elas, em vez de cobrar a viagem inteira de cada entrega isolada. '
                                'Estimativa editável até o app do entregador ter dado real de rota.',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: _validarValor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FormSection(
                      titulo: 'Pagamento ao entregador (análise de rentabilidade por zona)',
                      children: [
                        Text(
                          'Modelo atual, editável — você mencionou que ainda está estudando a melhor forma de '
                          'pagar, então ajuste isso sempre que decidir testar outro esquema.',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _entregadorBaseController,
                          decoration: const InputDecoration(
                            labelText: 'Valor base por entrega (R\$)',
                            prefixText: 'R\$ ',
                            helperText: 'Pago até o limiar de distância abaixo',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: _validarValor,
                        ),
                        TextFormField(
                          controller: _entregadorLimiarKmController,
                          decoration: const InputDecoration(
                            labelText: 'A partir de quantos km o valor escala com a distância',
                            suffixText: 'km',
                            helperText: 'Ex: 10 — acima disso, hoje você paga ~R\$1 por km (10km=R\$10, 15km=R\$15)',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: _validarValor,
                        ),
                        TextFormField(
                          controller: _entregadorBonusTurnoController,
                          decoration: const InputDecoration(
                            labelText: 'Bônus médio por turno trabalhado (R\$)',
                            prefixText: 'R\$ ',
                            helperText: 'Custo fixo por dia trabalhado (não por entrega) — você mencionou R\$20 a R\$30, dependendo do turno',
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          validator: _validarValor,
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
