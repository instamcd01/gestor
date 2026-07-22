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
import '../widgets/buscar_imagem_produto.dart';
import '../widgets/form_section.dart';

class EditarProdutoScreen extends StatefulWidget {
  final Produto produto;

  EditarProdutoScreen({required this.produto});

  @override
  _EditarProdutoScreenState createState() => _EditarProdutoScreenState();
}

class _EditarProdutoScreenState extends State<EditarProdutoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _canaisKey = GlobalKey<CanaisMarketplaceSectionState>();

  // Controladores para os campos do formulário
  late TextEditingController _nomeController;
  late TextEditingController _categoriaController;
  late TextEditingController _subcategoriaController;
  late TextEditingController _skuController;
  late TextEditingController _pesoController;
  late TextEditingController _volumeController;
  late TextEditingController _precoController;
  late TextEditingController _precoPromocionalController;
  late TextEditingController _descontoPromocionalController;
  late TextEditingController _descricaoController;
  late TextEditingController _codigoBarrasController;
  late TextEditingController _custoController;
  late TextEditingController _estoqueAtualController;
  late TextEditingController _estoqueMinimoController;
  late TextEditingController _markupController;
  late TextEditingController _lucroController;
  late TextEditingController _validadeController;
  late TextEditingController _empresaController;
  late TextEditingController _precoConcorrenciaController;

  late final CalculadoraPrecoMarkup _calculadora;
  late final CalculadoraDesconto _calculadoraDesconto;

  bool _destacarProduto = false;
  bool _exibirNoCatalogo = true;
  bool _ativo = true;

  XFile? _novaImagemFile; // Para imagem escolhida do dispositivo
  String? _imagemUrlAtual; // URL atual do produto
  String? _imagemAutomaticaUrl; // URL automática pelo código de barras

  bool _isLoading = false;
  List<String> _categoriasExistentes = [];
  bool _categoriasCarregadas = false;

  @override
  void initState() {
    super.initState();

    // Preenche os controladores com os dados atuais do produto
    _nomeController = TextEditingController(text: widget.produto.nome);
    _categoriaController =
        TextEditingController(text: widget.produto.categoria);
    _subcategoriaController =
        TextEditingController(text: widget.produto.subcategoria ?? '');
    _skuController = TextEditingController(text: widget.produto.sku ?? '');
    _pesoController = TextEditingController(
        text: widget.produto.peso?.toString().replaceAll('.', ',') ?? '');
    _volumeController = TextEditingController(
        text: widget.produto.volume?.toString().replaceAll('.', ',') ?? '');
    _precoController = TextEditingController(
        text: ProdutoValidators.formatarMoeda(widget.produto.preco));
    _precoPromocionalController = TextEditingController(
        text: ProdutoValidators.formatarMoeda(widget.produto.precoPromocional));
    _descontoPromocionalController = TextEditingController(
        text: ProdutoValidators.formatarMoeda(ProdutoValidators.calcularDescontoPercentual(
            widget.produto.preco, widget.produto.precoPromocional)));
    _descricaoController =
        TextEditingController(text: widget.produto.descricao);
    _codigoBarrasController =
        TextEditingController(text: widget.produto.codigoBarras);
    _custoController = TextEditingController(
        text: ProdutoValidators.formatarMoeda(widget.produto.custo));
    _estoqueAtualController =
        TextEditingController(text: widget.produto.estoqueAtual.toString());
    _estoqueMinimoController =
        TextEditingController(text: widget.produto.estoqueMinimo.toString());
    // markup vem formatado como "35.0%" do backend — o campo aqui é
    // editável e numérico, então guardamos só o número (com vírgula).
    _markupController = TextEditingController(
        text: widget.produto.markup?.replaceAll('%', '').replaceAll('.', ',') ?? '');
    _lucroController = TextEditingController(
        text: widget.produto.lucro?.replaceAll('.', ',') ?? '');
    _validadeController =
        TextEditingController(text: widget.produto.validade ?? '');
    _empresaController =
        TextEditingController(text: widget.produto.empresa ?? '');
    _precoConcorrenciaController = TextEditingController(
        text: ProdutoValidators.formatarMoeda(widget.produto.precoConcorrencia));

    _destacarProduto = widget.produto.destacar;
    _exibirNoCatalogo = widget.produto.exibirNoCatalogo;
    _ativo = widget.produto.ativo;

    _imagemUrlAtual = widget.produto.imagemUrl;
    _imagemAutomaticaUrl = widget.produto.imagemAutomaticaUrl;

    _calculadora = CalculadoraPrecoMarkup(
      precoController: _precoController,
      custoController: _custoController,
      markupController: _markupController,
      lucroController: _lucroController,
    );
    _calculadoraDesconto = CalculadoraDesconto(
      precoController: _precoController,
      promocionalController: _precoPromocionalController,
      descontoController: _descontoPromocionalController,
    );

    _carregarCategoriasDoSupabase();
  }

  @override
  void dispose() {
    _calculadora.dispose();
    _calculadoraDesconto.dispose();
    _nomeController.dispose();
    _categoriaController.dispose();
    _subcategoriaController.dispose();
    _skuController.dispose();
    _pesoController.dispose();
    _volumeController.dispose();
    _precoController.dispose();
    _precoPromocionalController.dispose();
    _descontoPromocionalController.dispose();
    _descricaoController.dispose();
    _codigoBarrasController.dispose();
    _custoController.dispose();
    _estoqueAtualController.dispose();
    _estoqueMinimoController.dispose();
    _markupController.dispose();
    _lucroController.dispose();
    _validadeController.dispose();
    _empresaController.dispose();
    _precoConcorrenciaController.dispose();
    super.dispose();
  }

  Future<void> _carregarCategoriasDoSupabase() async {
    try {
      final data = await supabase
          .from('categorias')
          .select('nome')
          .order('ordem');
      final categorias = (data as List)
          .map((row) => row['nome'] as String? ?? '')
          .where((c) => c.isNotEmpty)
          .toSet()
          .toList();
      setState(() {
        _categoriasExistentes = categorias;
        _categoriasCarregadas = true;
      });
    } catch (e) {
      debugPrint("Erro ao carregar categorias: $e");
      if (mounted) {
        setState(() => _categoriasCarregadas = true);
      }
    }
  }

  // Seleciona nova imagem da galeria
  Future<void> _selecionarNovaImagem() async {
    final picker = ImagePicker();
    try {
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          _novaImagemFile = pickedFile;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao selecionar imagem: $e')),
      );
    }
  }

  // Faz upload de verdade pro Supabase Storage (mesmo fluxo do cadastro) —
  // antes isso só montava uma URL pra um domínio que nunca recebia o arquivo.
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
      debugPrint('Erro no upload da imagem para o Supabase Storage: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro no upload da imagem: $e')),
        );
      }
      return null;
    }
  }

  // Busca imagem automaticamente usando código de barras, via OpenFoodFacts
  // (mesma função já usada em outras partes do app) — antes isso só montava
  // uma URL pra um domínio que nunca teve a imagem de verdade.
  Future<void> _buscarImagemAutomatica() async {
    final codigo = _codigoBarrasController.text.trim();
    if (codigo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Informe o código de barras para buscar a imagem')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final urlEncontrada = await buscarImagemProdutoPetPorCodigoBarras(codigo);
      if (!mounted) return;

      if (urlEncontrada == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhuma imagem encontrada para esse código de barras.')),
        );
        return;
      }

      setState(() {
        _imagemAutomaticaUrl = urlEncontrada;
        if (_novaImagemFile == null) {
          _imagemUrlAtual = _imagemAutomaticaUrl;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Imagem automática atribuída!')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Salva as alterações do produto no Supabase.
  Future<void> _salvarEdicao() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    String? imagemUrlParaSalvar = _imagemUrlAtual;

    if (_novaImagemFile != null) {
      String? novaUrl = await _uploadImagemProduto(File(_novaImagemFile!.path));
      if (novaUrl != null) {
        imagemUrlParaSalvar = novaUrl;
      } else {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Falha ao fazer upload da imagem. Tente novamente.')));
        return;
      }
    }

    final produtoAtualizado = Produto(
      id: widget.produto.id,
      nome: _nomeController.text,
      categoria: _categoriaController.text,
      subcategoria: _subcategoriaController.text.isNotEmpty
          ? _subcategoriaController.text
          : null,
      sku: _skuController.text.isNotEmpty ? _skuController.text : null,
      peso: ProdutoValidators.parseNumero(_pesoController.text),
      volume: ProdutoValidators.parseNumero(_volumeController.text),
      ativo: _ativo,
      preco: ProdutoValidators.parseNumero(_precoController.text) ??
          widget.produto.preco,
      precoPromocional: ProdutoValidators.parseNumero(_precoPromocionalController.text) ??
          widget.produto.precoPromocional,
      descricao: _descricaoController.text,
      codigoBarras: _codigoBarrasController.text,
      custo: ProdutoValidators.parseNumero(_custoController.text) ??
          widget.produto.custo,
      estoqueAtual: int.tryParse(_estoqueAtualController.text) ??
          widget.produto.estoqueAtual,
      estoqueMinimo: int.tryParse(_estoqueMinimoController.text) ??
          widget.produto.estoqueMinimo,
      imagemUrl: imagemUrlParaSalvar ?? widget.produto.imagemUrl,
      imagemAutomaticaUrl: _imagemAutomaticaUrl,
      destacar: _destacarProduto,
      exibirNoCatalogo: _exibirNoCatalogo,
      // Campo de preço fixo por marketplace descontinuado no formulário —
      // preço por canal agora vive em "Disponibilidade em Marketplaces".
      // Mantém o valor legado (se houver) só pra não perder dado antigo.
      precoIfood: widget.produto.precoIfood,
      markup: _markupController.text.isNotEmpty
          ? '${_markupController.text}%'
          : widget.produto.markup,
      lucro: _lucroController.text.isNotEmpty
          ? _lucroController.text
          : widget.produto.lucro,
      validade: _validadeController.text.isNotEmpty
          ? _validadeController.text
          : widget.produto.validade,
      empresa: _empresaController.text.isNotEmpty
          ? _empresaController.text
          : widget.produto.empresa,
      precoConcorrencia: ProdutoValidators.parseNumero(_precoConcorrenciaController.text) ??
          widget.produto.precoConcorrencia,
      estoqueId: widget.produto.estoqueId,
      unidadeMedida: widget.produto.unidadeMedida,
      permiteFracionamento: widget.produto.permiteFracionamento,
    );

    try {
      await Provider.of<ProdutoProvider>(context, listen: false)
          .atualizarProduto(produtoAtualizado);

      if (widget.produto.id != null) {
        await _canaisKey.currentState
            ?.salvar(widget.produto.id!, produtoAtualizado.preco);
      }

      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Produto atualizado com sucesso!')));
      Navigator.of(context).pop();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao atualizar produto: $e')));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Editar Produto'),
        actions: [
          _isLoading
              ? Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary),
                  ),
                )
              : IconButton(icon: Icon(Icons.save), tooltip: 'Salvar', onPressed: _salvarEdicao),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 56,
                      backgroundColor: colorScheme.surfaceContainerHighest,
                      backgroundImage: _novaImagemFile != null
                          ? FileImage(File(_novaImagemFile!.path)) as ImageProvider
                          : (_imagemUrlAtual != null && _imagemUrlAtual!.isNotEmpty
                              ? NetworkImage(_imagemUrlAtual!)
                              : null),
                      child: (_novaImagemFile == null &&
                              (_imagemUrlAtual == null || _imagemUrlAtual!.isEmpty))
                          ? Icon(Icons.image, size: 40, color: colorScheme.onSurfaceVariant)
                          : null,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        TextButton.icon(
                          icon: Icon(Icons.photo, size: 18),
                          label: Text('Nova imagem'),
                          onPressed: _selecionarNovaImagem,
                        ),
                        TextButton.icon(
                          icon: Icon(Icons.search, size: 18),
                          label: Text('Buscar automática'),
                          onPressed: _buscarImagemAutomatica,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8.0),

              FormSection(
                titulo: 'Identificação',
                children: [
                  TextFormField(
                    controller: _nomeController,
                    decoration: const InputDecoration(labelText: 'Nome'),
                    validator: ProdutoValidators.nome,
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Builder(
                          builder: (context) {
                            if (!_categoriasCarregadas) {
                              return const Center(child: CircularProgressIndicator());
                            }
                            if (_categoriasExistentes.isEmpty) {
                              return const Text("Nenhuma categoria encontrada");
                            }

                            final categorias = List<String>.from(_categoriasExistentes)..sort();

                            return DropdownButtonFormField<String>(
                              decoration: const InputDecoration(labelText: 'Categoria'),
                              value: _categoriaController.text.isNotEmpty &&
                                      categorias.contains(_categoriaController.text)
                                  ? _categoriaController.text
                                  : null,
                              items: categorias.map((categoria) {
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
                            );
                          },
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
                          await _carregarCategoriasDoSupabase();
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
                    controller: _precoController,
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
                              value, _precoController.text),
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
                    controller: _estoqueAtualController,
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
                    decoration: const InputDecoration(
                      labelText: 'Validade (Opcional)',
                      hintText: 'DD/MM/AAAA',
                    ),
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

              CanaisMarketplaceSection(key: _canaisKey, produtoId: widget.produto.id),
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
              const SizedBox(height: 16.0),
            ],
          ),
        ),
      ),
    );
  }
}
