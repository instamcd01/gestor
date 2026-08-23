import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/supabase_config.dart';
import '../providers/auth_provider.dart';
import '../providers/produto_provider.dart';
import '../utils/cliente_validators.dart';
import '../utils/formatadores_input.dart';
import '../widgets/aviso_banner.dart';
import '../widgets/form_section.dart';

/// Configuração do catálogo/site público (Configurações > Catálogo Online).
/// O site em si ainda não existe — vai ser um projeto separado depois —
/// mas os dados ficam prontos aqui: slug da loja, se o catálogo está
/// publicado, se aceita pedido online, redes sociais e info extra que a
/// página pública vai exibir.
class CatalogoOnlineScreen extends StatefulWidget {
  const CatalogoOnlineScreen({super.key});

  @override
  State<CatalogoOnlineScreen> createState() => _CatalogoOnlineScreenState();
}

class _CatalogoOnlineScreenState extends State<CatalogoOnlineScreen> {
  final _formKey = GlobalKey<FormState>();
  final _slugController = TextEditingController();
  final _whatsappController = TextEditingController();
  final _instagramController = TextEditingController();
  final _facebookController = TextEditingController();
  final _infoExtraController = TextEditingController();
  final _retiradaPrazoMinController = TextEditingController();
  final _freteEconomicoValorController = TextEditingController();
  final _freteEconomicoPrazoDiasController = TextEditingController();
  final _taxaServicoValorController = TextEditingController();

  bool _catalogoAtivo = false;
  bool _aceitaPedidosOnline = false;
  bool _aceitaRetirada = true;
  bool _mostrarEstoqueBaixo = false;
  bool _precoAncoraMarketplaceAtivo = false;
  String _modelo = 'classico';
  String _taxaServicoTipo = 'percentual';

  bool _carregando = true;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _carregarDados();
  }

  @override
  void dispose() {
    _slugController.dispose();
    _whatsappController.dispose();
    _instagramController.dispose();
    _facebookController.dispose();
    _infoExtraController.dispose();
    _retiradaPrazoMinController.dispose();
    _freteEconomicoValorController.dispose();
    _freteEconomicoPrazoDiasController.dispose();
    _taxaServicoValorController.dispose();
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
          .select('catalogo_slug, catalogo_ativo, aceita_pedidos_online, aceita_retirada, '
              'mostrar_estoque_baixo, catalogo_modelo, retirada_prazo_min, '
              'frete_economico_valor, frete_economico_prazo_dias, '
              'taxa_servico_tipo, taxa_servico_valor, '
              'whatsapp_catalogo, instagram, facebook, catalogo_info_extra, '
              'preco_ancora_marketplace_ativo')
          .eq('id', empresaId)
          .single();

      _slugController.text = data['catalogo_slug']?.toString() ?? '';
      _whatsappController.text = data['whatsapp_catalogo']?.toString() ?? '';
      _instagramController.text = data['instagram']?.toString() ?? '';
      _facebookController.text = data['facebook']?.toString() ?? '';
      _infoExtraController.text = data['catalogo_info_extra']?.toString() ?? '';
      _retiradaPrazoMinController.text = data['retirada_prazo_min']?.toString() ?? '';
      _freteEconomicoValorController.text =
          ClienteValidators.formatarMoeda((data['frete_economico_valor'] as num?)?.toDouble());
      _freteEconomicoPrazoDiasController.text = data['frete_economico_prazo_dias']?.toString() ?? '';
      _taxaServicoTipo = data['taxa_servico_tipo']?.toString() ?? 'percentual';
      _taxaServicoValorController.text =
          ClienteValidators.formatarMoeda((data['taxa_servico_valor'] as num?)?.toDouble());
      _catalogoAtivo = data['catalogo_ativo'] as bool? ?? false;
      _aceitaPedidosOnline = data['aceita_pedidos_online'] as bool? ?? false;
      _aceitaRetirada = data['aceita_retirada'] as bool? ?? true;
      _mostrarEstoqueBaixo = data['mostrar_estoque_baixo'] as bool? ?? false;
      _precoAncoraMarketplaceAtivo = data['preco_ancora_marketplace_ativo'] as bool? ?? false;
      _modelo = data['catalogo_modelo']?.toString() ?? 'classico';

      if (mounted) {
        await context.read<ProdutoProvider>().carregarProdutos();
      }
    } catch (e) {
      debugPrint('Erro ao carregar configuração do catálogo: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar configuração: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  String _sanitizarSlug(String texto) {
    final semAcento = texto
        .toLowerCase()
        .replaceAll(RegExp(r'[áàâã]'), 'a')
        .replaceAll(RegExp(r'[éê]'), 'e')
        .replaceAll('í', 'i')
        .replaceAll(RegExp(r'[óôõ]'), 'o')
        .replaceAll('ú', 'u')
        .replaceAll('ç', 'c');
    return semAcento.replaceAll(RegExp(r'\s+'), '-').replaceAll(RegExp(r'[^a-z0-9\-]'), '');
  }

  /// null = os dois em branco (modalidade econômica desligada, permitido)
  /// ou os dois preenchidos. Senão, exige os dois.
  String? _validarFreteEconomico() {
    final valorTexto = _freteEconomicoValorController.text.trim();
    final prazoTexto = _freteEconomicoPrazoDiasController.text.trim();
    if (valorTexto.isEmpty && prazoTexto.isEmpty) return null;
    if (valorTexto.isEmpty || prazoTexto.isEmpty) {
      return 'Informe valor e prazo do frete econômico, ou deixe os dois em branco';
    }
    return null;
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;

    final erroFreteEconomico = _validarFreteEconomico();
    if (erroFreteEconomico != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(erroFreteEconomico)));
      return;
    }

    final empresaId = context.read<AuthProvider>().empresaId;
    if (empresaId == null) return;

    setState(() => _salvando = true);
    try {
      await supabase.from('empresas').update({
        'catalogo_slug': _slugController.text.trim().isEmpty ? null : _slugController.text.trim(),
        'catalogo_ativo': _catalogoAtivo,
        'aceita_pedidos_online': _aceitaPedidosOnline,
        'aceita_retirada': _aceitaRetirada,
        'mostrar_estoque_baixo': _mostrarEstoqueBaixo,
        'preco_ancora_marketplace_ativo': _precoAncoraMarketplaceAtivo,
        'catalogo_modelo': _modelo,
        'whatsapp_catalogo': _whatsappController.text.trim(),
        'instagram': _instagramController.text.trim(),
        'facebook': _facebookController.text.trim(),
        'catalogo_info_extra': _infoExtraController.text.trim(),
        'retirada_prazo_min': int.tryParse(_retiradaPrazoMinController.text.trim()),
        'frete_economico_valor': ClienteValidators.parseNumero(_freteEconomicoValorController.text),
        'frete_economico_prazo_dias': int.tryParse(_freteEconomicoPrazoDiasController.text.trim()),
        'taxa_servico_tipo':
            ClienteValidators.parseNumero(_taxaServicoValorController.text) == null ? null : _taxaServicoTipo,
        'taxa_servico_valor': ClienteValidators.parseNumero(_taxaServicoValorController.text),
      }).eq('id', empresaId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Configuração do catálogo salva com sucesso!')),
        );
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        final mensagem = e.code == '23505'
            ? 'Esse link já está em uso por outra loja. Escolha outro.'
            : 'Erro ao salvar: ${e.message}';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagem)));
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
    final produtoProvider = context.watch<ProdutoProvider>();
    final produtosNoCatalogo =
        produtoProvider.produtos.where((p) => p.exibirNoCatalogo && p.ativo).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Catálogo Online'),
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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AvisoBanner(
                      texto: 'O site público ainda não existe — essa tela só guarda a configuração '
                          'pra quando ele for lançado. $produtosNoCatalogo produto${produtosNoCatalogo != 1 ? 's' : ''} '
                          'já ${produtosNoCatalogo != 1 ? 'estão marcados' : 'está marcado'} pra aparecer no catálogo '
                          '(campo "Exibir no Catálogo" no cadastro de produto).',
                    ),
                    const SizedBox(height: 20),
                    FormSection(
                      titulo: 'Visibilidade',
                      children: [
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Catálogo publicado'),
                          subtitle: const Text('Quando o site existir, controla se ele fica visível ao público'),
                          value: _catalogoAtivo,
                          onChanged: (v) => setState(() => _catalogoAtivo = v),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Aceitar pedidos online'),
                          subtitle: const Text('Desligado = catálogo é só vitrine, cliente compra por WhatsApp/telefone'),
                          value: _aceitaPedidosOnline,
                          onChanged: (v) => setState(() => _aceitaPedidosOnline = v),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Aceitar retirada na loja'),
                          subtitle: const Text('Desligado = cliente só pode escolher entrega no checkout do site'),
                          value: _aceitaRetirada,
                          onChanged: (v) => setState(() => _aceitaRetirada = v),
                        ),
                        if (_aceitaRetirada)
                          TextFormField(
                            controller: _retiradaPrazoMinController,
                            decoration: const InputDecoration(
                              labelText: 'Prazo de retirada (min) (Opcional)',
                              helperText: 'Mostrado ao cliente no checkout do site — ex: 30 = "pronto em até 30 min"',
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [InteiroInputFormatter()],
                          ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Mostrar estoque baixo no produto'),
                          subtitle: const Text('Liga o aviso "Só restam X em estoque" — desligado por padrão, '
                              'pode passar imagem de loja pequena com pouco de cada item'),
                          value: _mostrarEstoqueBaixo,
                          onChanged: (v) => setState(() => _mostrarEstoqueBaixo = v),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Comparar preço com marketplaces'),
                          subtitle: const Text(
                            'Produto sem promoção cadastrada, mas com preço maior em algum marketplace '
                            '(iFood, 99Food...), passa a mostrar esse preço maior riscado no site — como se '
                            'estivesse com desconto comparado a ele. Não menciona o marketplace, só cria o '
                            'efeito visual de oferta.',
                          ),
                          value: _precoAncoraMarketplaceAtivo,
                          onChanged: (v) => setState(() => _precoAncoraMarketplaceAtivo = v),
                        ),
                        TextFormField(
                          controller: _slugController,
                          decoration: const InputDecoration(
                            labelText: 'Link da loja',
                            prefixText: 'suaLoja.com/',
                            helperText: 'Só letras minúsculas, números e hífen',
                          ),
                          onChanged: (texto) {
                            final sanitizado = _sanitizarSlug(texto);
                            if (sanitizado != texto) {
                              _slugController.value = TextEditingValue(
                                text: sanitizado,
                                selection: TextSelection.collapsed(offset: sanitizado.length),
                              );
                            }
                          },
                          inputFormatters: [FilteringTextInputFormatter.deny(RegExp(r'\s'))],
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: _modelo,
                          decoration: const InputDecoration(labelText: 'Modelo do catálogo'),
                          items: const [
                            DropdownMenuItem(value: 'classico', child: Text('Clássico')),
                            DropdownMenuItem(value: 'moderno', child: Text('Moderno')),
                          ],
                          onChanged: (v) => setState(() => _modelo = v!),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FormSection(
                      titulo: 'Entrega econômica (site)',
                      children: [
                        Text(
                          'Modalidade extra, mais barata e mais lenta que a entrega por zona '
                          '(Configurações > Opções de Entrega) — vale pra qualquer endereço dentro '
                          'da área de entrega. Deixe os dois campos em branco pra não oferecer essa opção.',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _freteEconomicoValorController,
                                decoration: const InputDecoration(labelText: 'Valor (R\$)', prefixText: 'R\$ '),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [MoedaInputFormatter()],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                controller: _freteEconomicoPrazoDiasController,
                                decoration: const InputDecoration(labelText: 'Prazo (dias úteis)'),
                                keyboardType: TextInputType.number,
                                inputFormatters: [InteiroInputFormatter()],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FormSection(
                      titulo: 'Taxa de serviço (site)',
                      children: [
                        Text(
                          'Cobrada em cima do valor dos produtos, em qualquer pedido do site '
                          '(entrega ou retirada) — igual ao iFood. Deixe o valor em branco pra '
                          'não cobrar taxa nenhuma.',
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _taxaServicoTipo,
                                isExpanded: true,
                                decoration: const InputDecoration(labelText: 'Tipo'),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'percentual',
                                    child: Text('Percentual (%)', overflow: TextOverflow.ellipsis),
                                  ),
                                  DropdownMenuItem(
                                    value: 'fixo',
                                    child: Text('Valor fixo (R\$)', overflow: TextOverflow.ellipsis),
                                  ),
                                ],
                                onChanged: (v) => setState(() => _taxaServicoTipo = v!),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                controller: _taxaServicoValorController,
                                decoration: InputDecoration(
                                  labelText: 'Valor',
                                  prefixText: _taxaServicoTipo == 'fixo' ? 'R\$ ' : null,
                                  suffixText: _taxaServicoTipo == 'percentual' ? '%' : null,
                                ),
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                inputFormatters: [DecimalInputFormatter()],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    FormSection(
                      titulo: 'Redes sociais e contato',
                      children: [
                        TextFormField(
                          controller: _whatsappController,
                          decoration: const InputDecoration(
                            labelText: 'WhatsApp do catálogo (Opcional)',
                            helperText: 'Número normal do Brasil (ex: (21) 97150-9079) ou já internacional '
                                'começando com "+" (ex: +1 555 154 1583, número de teste da Meta)',
                          ),
                          keyboardType: TextInputType.phone,
                          inputFormatters: [TelefoneInputFormatter()],
                        ),
                        TextFormField(
                          controller: _instagramController,
                          decoration: const InputDecoration(labelText: 'Instagram (Opcional)', prefixText: '@'),
                        ),
                        TextFormField(
                          controller: _facebookController,
                          decoration: const InputDecoration(labelText: 'Facebook (Opcional)'),
                        ),
                        TextFormField(
                          controller: _infoExtraController,
                          decoration: const InputDecoration(
                            labelText: 'Informações extras (Opcional)',
                            helperText: 'Ex: horário de funcionamento, política de trocas',
                          ),
                          maxLines: 3,
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
              ),
            ),
    );
  }
}
