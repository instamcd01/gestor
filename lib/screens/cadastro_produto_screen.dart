import 'package:flutter/material.dart';
import 'package:gestor/screens/produto_categorias_screen.dart';
import 'package:gestor/screens/fabricante_screen.dart';
import 'package:provider/provider.dart';

import '../config/supabase_config.dart';
import '../models/produto.dart';
import '../providers/auth_provider.dart';
import '../providers/produto_provider.dart';
import '../utils/calculadora_desconto.dart';
import '../utils/calculadora_preco.dart';
import '../utils/formatadores_input.dart';
import '../utils/produto_validators.dart';
import '../widgets/canais_marketplace_section.dart';
import '../widgets/form_section.dart';
import 'gerenciar_midias_produto_screen.dart';

class CadastroProdutoScreen extends StatefulWidget {
  /// Pré-preenche nome/código de barras/custo (ex: a partir de um item
  /// pendente na importação de nota fiscal) — o resto do formulário
  /// continua em branco, o usuário completa antes de salvar.
  final Produto? produtoInicial;

  const CadastroProdutoScreen({super.key, this.produtoInicial});

  @override
  _CadastroProdutoScreenState createState() => _CadastroProdutoScreenState();
}

class _CadastroProdutoScreenState extends State<CadastroProdutoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _canaisKey = GlobalKey<CanaisMarketplaceSectionState>();

  // Controllers para os campos do formulário
  final _nomeController = TextEditingController();
  final _precoVendaController = TextEditingController();
  final _precoPromocionalController = TextEditingController();
  final _descontoPromocionalController = TextEditingController();
  final _categoriaController = TextEditingController();
  final _subcategoriaController = TextEditingController();
  final _skuController = TextEditingController();
  final _pesoController = TextEditingController();
  final _volumeController = TextEditingController();
  final _descricaoController = TextEditingController();
  final _codigoBarrasController = TextEditingController();
  final _custoController = TextEditingController();
  final _estoqueController = TextEditingController();
  final _estoqueMinimoController = TextEditingController();
  final _markupController = TextEditingController();
  final _lucroController = TextEditingController();
  final _validadeController = TextEditingController();
  final _empresaController = TextEditingController();
  final _fabricanteController = TextEditingController();
  final _precoConcorrenciaController = TextEditingController();

  bool _destacarProduto = false;
  bool _exibirNoCatalogo = true;
  bool _ativo = true;
  bool _isLoading = false;

  List<String> _categorias = []; // categorias cadastradas na empresa
  bool _categoriasCarregadas = false;

  List<String> _subcategorias = []; // subcategorias da categoria selecionada
  bool _subcategoriasCarregadas = false;

  List<String> _fabricantes = [];
  bool _fabricantesCarregadas = false;

  late final CalculadoraPrecoMarkup _calculadora;
  late final CalculadoraDesconto _calculadoraDesconto;

  @override
  void initState() {
    super.initState();
    final inicial = widget.produtoInicial;
    if (inicial != null) {
      _nomeController.text = inicial.nome;
      _codigoBarrasController.text = inicial.codigoBarras;
      if (inicial.custo > 0) {
        _custoController.text = ProdutoValidators.formatarMoeda(inicial.custo);
      }
    }
    _carregarCategorias();
    _carregarSubcategorias();
    _carregarFabricantes();
    _calculadora = CalculadoraPrecoMarkup(
      precoController: _precoVendaController,
      custoController: _custoController,
      markupController: _markupController,
      lucroController: _lucroController,
    );
    _calculadoraDesconto = CalculadoraDesconto(
      precoController: _precoVendaController,
      promocionalController: _precoPromocionalController,
      descontoController: _descontoPromocionalController,
    );
  }

  Future<void> _carregarCategorias() async {
    try {
      final data = await supabase
          .from('categorias')
          .select('nome')
          .order('ordem');
      final categorias = (data as List)
          .map((row) => row['nome'] as String? ?? '')
          .where((c) => c.isNotEmpty)
          .toSet();

      // A tabela `categorias` só é preenchida quando alguém abre "Gerenciar
      // categorias" — até isso acontecer pra todo o catálogo, ela fica
      // incompleta. Unimos com as categorias realmente em uso em
      // `produtos.categoria` (mesma fonte que "Gerenciar categorias" usa)
      // pra sempre oferecer todas as opções reais ao cadastrar um produto novo.
      final produtosData = await supabase.from('produtos').select('categoria');
      categorias.addAll(
        (produtosData as List)
            .map((p) => (p['categoria'] as String?) ?? '')
            .where((c) => c.isNotEmpty),
      );

      final lista = categorias.toList()..sort();
      if (!mounted) return;
      setState(() {
        _categorias = lista;
        _categoriasCarregadas = true;
      });
    } catch (e) {
      debugPrint("Erro ao carregar categorias: $e");
      if (mounted) {
        setState(() => _categoriasCarregadas = true);
      }
    }
  }

  /// Recarrega as subcategorias da categoria atualmente selecionada — o
  /// mesmo texto de subcategoria (ex. "Adultos") significa coisas
  /// diferentes em categorias diferentes, então a lista é sempre escopada.
  Future<void> _carregarSubcategorias() async {
    final categoriaNome = _categoriaController.text;
    if (categoriaNome.isEmpty) {
      if (!mounted) return;
      setState(() {
        _subcategorias = [];
        _subcategoriaController.clear();
        _subcategoriasCarregadas = true;
      });
      return;
    }
    try {
      final categoria =
          await supabase.from('categorias').select('id').eq('nome', categoriaNome).maybeSingle();
      final lista = categoria == null
          ? <String>[]
          : ((await supabase
                      .from('subcategorias')
                      .select('nome')
                      .eq('categoria_id', categoria['id'])
                      .order('ordem')) as List)
              .map((row) => row['nome'] as String)
              .toList();
      if (!mounted) return;
      setState(() {
        _subcategorias = lista;
        _subcategoriasCarregadas = true;
        if (!_subcategorias.contains(_subcategoriaController.text)) {
          _subcategoriaController.clear();
        }
      });
    } catch (e) {
      debugPrint("Erro ao carregar subcategorias: $e");
      if (mounted) setState(() => _subcategoriasCarregadas = true);
    }
  }

  Future<void> _carregarFabricantes() async {
    try {
      final data = await supabase.from('fabricantes').select('nome').order('ordem');
      final fabricantes = (data as List).map((row) => row['nome'] as String? ?? '').where((f) => f.isNotEmpty).toSet();

      final produtosData = await supabase.from('produtos').select('fabricante');
      fabricantes.addAll(
        (produtosData as List).map((p) => (p['fabricante'] as String?) ?? '').where((f) => f.isNotEmpty),
      );

      if (!mounted) return;
      setState(() {
        _fabricantes = fabricantes.toList()..sort();
        _fabricantesCarregadas = true;
      });
    } catch (e) {
      debugPrint("Erro ao carregar fabricantes: $e");
      if (mounted) setState(() => _fabricantesCarregadas = true);
    }
  }

  @override
  void dispose() {
    _calculadora.dispose();
    _calculadoraDesconto.dispose();
    _nomeController.dispose();
    _precoVendaController.dispose();
    _precoPromocionalController.dispose();
    _descontoPromocionalController.dispose();
    _categoriaController.dispose();
    _subcategoriaController.dispose();
    _skuController.dispose();
    _pesoController.dispose();
    _volumeController.dispose();
    _descricaoController.dispose();
    _codigoBarrasController.dispose();
    _custoController.dispose();
    _estoqueController.dispose();
    _estoqueMinimoController.dispose();
    _markupController.dispose();
    _lucroController.dispose();
    _validadeController.dispose();
    _empresaController.dispose();
    _fabricanteController.dispose();
    _precoConcorrenciaController.dispose();
    super.dispose();
  }

  Future<void> _adicionarProduto() async {
    if (!_formKey.currentState!.validate()) {
      return; // Se o formulário não for válido, não continue
    }

    setState(() {
      _isLoading = true;
    });

    final novoProduto = Produto(
      nome: _nomeController.text,
      preco: ProdutoValidators.parseNumero(_precoVendaController.text) ?? 0.0,
      precoPromocional: ProdutoValidators.parseNumero(_precoPromocionalController.text),
      categoria: _categoriaController.text,
      subcategoria: _subcategoriaController.text.isNotEmpty ? _subcategoriaController.text : null,
      sku: _skuController.text.isNotEmpty ? _skuController.text : null,
      peso: ProdutoValidators.parseNumero(_pesoController.text),
      volume: ProdutoValidators.parseNumero(_volumeController.text),
      ativo: _ativo,
      descricao: _descricaoController.text,
      codigoBarras: _codigoBarrasController.text,
      custo: ProdutoValidators.parseNumero(_custoController.text) ?? 0.0,
      // Fotos/vídeos agora são adicionados na tela de galeria logo depois
      // de salvar (precisa do id do produto, que só existe após o insert).
      imagemUrl: '',
      estoqueAtual: int.tryParse(_estoqueController.text) ?? 0,
      estoqueMinimo: int.tryParse(_estoqueMinimoController.text) ?? 0,
      destacar: _destacarProduto,
      exibirNoCatalogo: _exibirNoCatalogo,
      markup: _markupController.text.isNotEmpty ? '${_markupController.text}%' : null,
      lucro: _lucroController.text.isNotEmpty ? _lucroController.text : null,
      precoConcorrencia: ProdutoValidators.parseNumero(_precoConcorrenciaController.text),
      validade: _validadeController.text.isNotEmpty ? _validadeController.text : null,
      empresa: _empresaController.text.isNotEmpty ? _empresaController.text : null,
      fabricante: _fabricanteController.text.isNotEmpty ? _fabricanteController.text : null,
    );

    try {
      if (mounted) {
        // Verifica antes de usar o context
        final produtoProvider =
            Provider.of<ProdutoProvider>(context, listen: false);
        final produtoCriado = await produtoProvider.adicionarProduto(novoProduto);

        // Salva a disponibilidade nos marketplaces só agora, com o id
        // definitivo que o Supabase gerou pro produto.
        if (produtoCriado.id != null) {
          await _canaisKey.currentState
              ?.salvar(produtoCriado.id!, produtoCriado.preco);
        }

        if (mounted) {
          // Verifica novamente antes de interagir com a UI. Produto criado —
          // manda direto pra galeria de mídias, já que fotos/vídeos só podem
          // ser salvos depois que o produto existe (precisam do id).
          if (produtoCriado.id != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Produto adicionado! Agora adicione fotos e vídeos.')),
            );
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (_) => GerenciarMidiasProdutoScreen(produtoId: produtoCriado.id!),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Produto adicionado com sucesso!')),
            );
            Navigator.of(context).pop();
          }
        }
      }
    } catch (e) {
      debugPrint("Erro ao adicionar produto: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao adicionar produto: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isVendedor = context.watch<AuthProvider>().isVendedor;

    return Scaffold(
      appBar: AppBar(title: Text('Cadastrar Novo Produto')),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        width: 120,
                        height: 120,
                        color: colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.add_photo_alternate_outlined,
                          size: 40,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Fotos e vídeos podem ser adicionados\nlogo depois de salvar',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24.0),

              FormSection(
                titulo: 'Identificação',
                children: [
                  TextFormField(
                    controller: _nomeController,
                    decoration: const InputDecoration(labelText: 'Nome do Produto'),
                    validator: ProdutoValidators.nome,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: !_categoriasCarregadas
                            ? const Center(child: CircularProgressIndicator())
                            : _categorias.isEmpty
                                ? const Text("Nenhuma categoria cadastrada")
                                : DropdownButtonFormField<String>(
                                    decoration: const InputDecoration(labelText: 'Categoria'),
                                    value: _categoriaController.text.isNotEmpty &&
                                            _categorias.contains(_categoriaController.text)
                                        ? _categoriaController.text
                                        : null,
                                    items: _categorias.map((categoria) {
                                      return DropdownMenuItem(
                                        value: categoria,
                                        child: Text(categoria),
                                      );
                                    }).toList(),
                                    onChanged: (value) {
                                      setState(() => _categoriaController.text = value!);
                                      _carregarSubcategorias();
                                    },
                                    validator: ProdutoValidators.categoria,
                                  ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Gerenciar categorias',
                        icon: const Icon(Icons.add),
                        onPressed: () async {
                          // Navega para a tela de categorias e usa a que for selecionada lá
                          final categoriaEscolhida = await Navigator.push<String>(
                            context,
                            MaterialPageRoute(
                                builder: (context) => CategoriaScreen(
                                      categoriaSelecionada: _categoriaController.text,
                                    )),
                          );
                          await _carregarCategorias();
                          if (categoriaEscolhida != null && categoriaEscolhida.isNotEmpty) {
                            setState(() => _categoriaController.text = categoriaEscolhida);
                            await _carregarSubcategorias();
                          }
                        },
                      ),
                    ],
                  ),
                  !_subcategoriasCarregadas
                      ? const Center(child: CircularProgressIndicator())
                      : DropdownButtonFormField<String>(
                          decoration: const InputDecoration(labelText: 'Subcategoria (Opcional)'),
                          value: _subcategorias.contains(_subcategoriaController.text)
                              ? _subcategoriaController.text
                              : '',
                          items: [
                            const DropdownMenuItem(value: '', child: Text('Nenhuma')),
                            for (final subcategoria in _subcategorias)
                              DropdownMenuItem(value: subcategoria, child: Text(subcategoria)),
                          ],
                          onChanged: (value) {
                            setState(() => _subcategoriaController.text = value ?? '');
                          },
                        ),
                  TextFormField(
                    controller: _descricaoController,
                    decoration: const InputDecoration(labelText: 'Descrição'),
                    maxLines: 3,
                    validator: ProdutoValidators.descricao,
                  ),
                  TextFormField(
                    controller: _codigoBarrasController,
                    decoration: const InputDecoration(labelText: 'Código de Barras (Opcional)'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [DigitosInputFormatter()],
                    validator: ProdutoValidators.codigoBarras,
                  ),
                  TextFormField(
                    controller: _skuController,
                    decoration: const InputDecoration(
                      labelText: 'SKU (Opcional)',
                      helperText: 'Código interno usado para integrar com marketplaces',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16.0),

              FormSection(
                titulo: 'Preço e custo',
                children: [
                  TextFormField(
                    controller: _precoVendaController,
                    decoration: const InputDecoration(
                      labelText: 'Preço de Venda (R\$)',
                      prefixText: 'R\$ ',
                      helperText: 'Preço no site/app. Marketplaces têm preço próprio abaixo.',
                    ),
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [MoedaInputFormatter()],
                    validator: ProdutoValidators.precoVenda,
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _precoPromocionalController,
                          decoration: const InputDecoration(
                            labelText: 'Preço Promocional (R\$)',
                            prefixText: 'R\$ ',
                            helperText: 'Opcional',
                          ),
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [MoedaInputFormatter()],
                          validator: (value) => ProdutoValidators.precoPromocional(
                              value, _precoVendaController.text),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _descontoPromocionalController,
                          decoration: const InputDecoration(
                            labelText: 'Desconto',
                            suffixText: '%',
                            helperText: 'Calcula o preço',
                          ),
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [DecimalInputFormatter()],
                          validator: ProdutoValidators.descontoPercentual,
                        ),
                      ),
                    ],
                  ),
                  if (!isVendedor) ...[
                    TextFormField(
                      controller: _custoController,
                      decoration: const InputDecoration(labelText: 'Custo (R\$)', prefixText: 'R\$ '),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [MoedaInputFormatter()],
                      validator: ProdutoValidators.custo,
                    ),
                    TextFormField(
                      controller: _markupController,
                      decoration: const InputDecoration(
                        labelText: 'Markup (%) (Opcional)',
                        suffixText: '%',
                        helperText: 'Calculado com preço+custo, ou preencha pra calcular o preço',
                      ),
                      keyboardType: TextInputType.numberWithOptions(decimal: true, signed: true),
                      inputFormatters: [DecimalInputFormatter(permiteSinal: true)],
                      validator: ProdutoValidators.markup,
                    ),
                    TextFormField(
                      controller: _lucroController,
                      decoration: const InputDecoration(
                        labelText: 'Lucro (R\$) (Opcional)',
                        prefixText: 'R\$ ',
                        helperText: 'Calculado com preço+custo, ou preencha pra calcular o preço',
                      ),
                      keyboardType: TextInputType.numberWithOptions(decimal: true, signed: true),
                      inputFormatters: [DecimalInputFormatter(permiteSinal: true)],
                      validator: ProdutoValidators.lucro,
                    ),
                    TextFormField(
                      controller: _precoConcorrenciaController,
                      decoration: const InputDecoration(
                        labelText: 'Preço Concorrência (R\$) (Opcional)',
                        prefixText: 'R\$ ',
                      ),
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [MoedaInputFormatter()],
                      validator: ProdutoValidators.precoOpcional,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16.0),

              FormSection(
                titulo: 'Estoque',
                children: [
                  TextFormField(
                    controller: _estoqueController,
                    decoration: const InputDecoration(labelText: 'Estoque Atual'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [InteiroInputFormatter()],
                    validator: (value) =>
                        ProdutoValidators.estoqueInteiro(value, campo: 'o estoque atual'),
                  ),
                  TextFormField(
                    controller: _estoqueMinimoController,
                    decoration: const InputDecoration(labelText: 'Estoque Mínimo'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [InteiroInputFormatter()],
                    validator: (value) =>
                        ProdutoValidators.estoqueInteiro(value, campo: 'o estoque mínimo'),
                  ),
                ],
              ),
              const SizedBox(height: 16.0),

              FormSection(
                titulo: 'Logística e fornecedor',
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _pesoController,
                          decoration: const InputDecoration(labelText: 'Peso (kg) (Opcional)'),
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [DecimalInputFormatter()],
                          validator: ProdutoValidators.numeroOpcionalNaoNegativo,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: _volumeController,
                          decoration: const InputDecoration(labelText: 'Volume (m³) (Opcional)'),
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                          inputFormatters: [DecimalInputFormatter()],
                          validator: ProdutoValidators.numeroOpcionalNaoNegativo,
                        ),
                      ),
                    ],
                  ),
                  TextFormField(
                    controller: _validadeController,
                    decoration: const InputDecoration(labelText: 'Validade (Ex: DD/MM/AAAA) (Opcional)'),
                    keyboardType: TextInputType.datetime,
                    inputFormatters: [DataInputFormatter()],
                    validator: ProdutoValidators.validade,
                  ),
                  TextFormField(
                    controller: _empresaController,
                    decoration: const InputDecoration(labelText: 'Empresa/Fornecedor (Opcional)'),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: !_fabricantesCarregadas
                            ? const Center(child: CircularProgressIndicator())
                            : DropdownButtonFormField<String>(
                                decoration: const InputDecoration(
                                  labelText: 'Fabricante (Opcional)',
                                  helperText:
                                      'Laboratório/marca que fabrica o produto — pode ser diferente do fornecedor',
                                ),
                                value: _fabricantes.contains(_fabricanteController.text)
                                    ? _fabricanteController.text
                                    : null,
                                items: [
                                  for (final fabricante in _fabricantes)
                                    DropdownMenuItem(value: fabricante, child: Text(fabricante)),
                                ],
                                onChanged: (value) {
                                  setState(() => _fabricanteController.text = value ?? '');
                                },
                              ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        tooltip: 'Gerenciar fabricantes',
                        icon: const Icon(Icons.add),
                        onPressed: () async {
                          final fabricanteEscolhido = await Navigator.push<String>(
                            context,
                            MaterialPageRoute(
                                builder: (context) => FabricanteScreen(
                                      fabricanteSelecionado: _fabricanteController.text,
                                    )),
                          );
                          await _carregarFabricantes();
                          if (fabricanteEscolhido != null && fabricanteEscolhido.isNotEmpty) {
                            setState(() => _fabricanteController.text = fabricanteEscolhido);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16.0),

              CanaisMarketplaceSection(key: _canaisKey),
              const SizedBox(height: 16.0),

              FormSection(
                titulo: 'Opções',
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Produto Ativo'),
                    subtitle: Text('Desative para descontinuar sem excluir o histórico'),
                    value: _ativo,
                    onChanged: (bool value) => setState(() => _ativo = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Destacar Produto'),
                    value: _destacarProduto,
                    onChanged: (bool value) => setState(() => _destacarProduto = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Exibir no Catálogo'),
                    value: _exibirNoCatalogo,
                    onChanged: (bool value) => setState(() => _exibirNoCatalogo = value),
                  ),
                ],
              ),
              const SizedBox(height: 24.0),

              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _adicionarProduto,
                      style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 52)),
                      child: Text('Adicionar Produto'),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
