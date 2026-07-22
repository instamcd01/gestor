import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gestor/screens/produto_categorias_screen.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../config/supabase_config.dart';
import '../models/produto.dart';
import '../providers/produto_provider.dart';
import '../utils/calculadora_desconto.dart';
import '../utils/calculadora_preco.dart';
import '../utils/formatadores_input.dart';
import '../utils/produto_validators.dart';
import '../widgets/canais_marketplace_section.dart';
import '../widgets/form_section.dart';

class CadastroProdutoScreen extends StatefulWidget {
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
  final _precoConcorrenciaController = TextEditingController();

  bool _destacarProduto = false;
  bool _exibirNoCatalogo = true;
  bool _ativo = true;
  XFile? _imagemProdutoFile; // Arquivo da imagem selecionada
  bool _isLoading = false;

  List<String> _categorias = []; // categorias cadastradas na empresa
  bool _categoriasCarregadas = false;

  late final CalculadoraPrecoMarkup _calculadora;
  late final CalculadoraDesconto _calculadoraDesconto;

  @override
  void initState() {
    super.initState();
    _carregarCategorias();
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
          .toSet()
          .toList()
        ..sort();
      setState(() {
        _categorias = categorias;
        _categoriasCarregadas = true;
      });
    } catch (e) {
      debugPrint("Erro ao carregar categorias: $e");
      if (mounted) {
        setState(() => _categoriasCarregadas = true);
      }
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
    _precoConcorrenciaController.dispose();
    super.dispose();
  }

  Future<void> _selecionarImagem() async {
    final picker = ImagePicker();
    try {
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          _imagemProdutoFile = pickedFile;
        });
      }
    } catch (e) {
      debugPrint("Erro ao selecionar imagem: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao selecionar imagem: $e')),
        );
      }
    }
  }

  Future<String?> _uploadImagemProduto(File imageFile) async {
    if (!mounted) return null;
    try {
      String? empresaId;
      final userId = supabase.auth.currentUser?.id;
      if (userId != null) {
        final usuario = await supabase
            .from('usuarios')
            .select('empresa_id')
            .eq('id', userId)
            .maybeSingle();
        empresaId = usuario?['empresa_id'] as String?;
      }

      if (empresaId == null) {
        throw Exception('Empresa não identificada para o upload.');
      }

      final fileName =
          '$empresaId/${DateTime.now().millisecondsSinceEpoch}_${imageFile.path.split('/').last}';

      await supabase.storage.from('produtos').upload(fileName, imageFile);

      return supabase.storage.from('produtos').getPublicUrl(fileName);
    } catch (e) {
      debugPrint("Erro no upload da imagem para o Supabase Storage: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro no upload da imagem: $e')),
        );
      }
      return null;
    }
  }

  Future<void> _adicionarProduto() async {
    if (!_formKey.currentState!.validate()) {
      return; // Se o formulário não for válido, não continue
    }

    setState(() {
      _isLoading = true;
    });

    String? imagemUrlParaSalvar; // URL da imagem após o upload

    if (_imagemProdutoFile != null) {
      imagemUrlParaSalvar =
          await _uploadImagemProduto(File(_imagemProdutoFile!.path));
      if (imagemUrlParaSalvar == null && mounted) {
        // Se o upload falhar e o widget ainda estiver montado, pare o processo
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Falha ao fazer upload da imagem. Tente novamente.')),
        );
        return;
      }
    }

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
      imagemUrl: imagemUrlParaSalvar ?? '',
      // Usa a URL do Storage ou string vazia
      estoqueAtual: int.tryParse(_estoqueController.text) ?? 0,
      estoqueMinimo: int.tryParse(_estoqueMinimoController.text) ?? 0,
      destacar: _destacarProduto,
      exibirNoCatalogo: _exibirNoCatalogo,
      markup: _markupController.text.isNotEmpty ? '${_markupController.text}%' : null,
      lucro: _lucroController.text.isNotEmpty ? _lucroController.text : null,
      precoConcorrencia: ProdutoValidators.parseNumero(_precoConcorrenciaController.text),
      validade: _validadeController.text.isNotEmpty ? _validadeController.text : null,
      empresa: _empresaController.text.isNotEmpty ? _empresaController.text : null,
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
          // Verifica novamente antes de interagir com a UI
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Produto adicionado com sucesso!')),
          );
          Navigator.of(context).pop();
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
                child: GestureDetector(
                  onTap: _selecionarImagem,
                  child: CircleAvatar(
                    radius: 56,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    backgroundImage: _imagemProdutoFile == null
                        ? null
                        : FileImage(File(_imagemProdutoFile!.path)),
                    child: _imagemProdutoFile == null
                        ? Icon(Icons.add_a_photo, size: 40, color: colorScheme.onSurfaceVariant)
                        : null,
                  ),
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
                                      setState(() {
                                        _categoriaController.text = value!;
                                      });
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
                            setState(() {
                              _categoriaController.text = categoriaEscolhida;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                  TextFormField(
                    controller: _subcategoriaController,
                    decoration: const InputDecoration(labelText: 'Subcategoria (Opcional)'),
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
