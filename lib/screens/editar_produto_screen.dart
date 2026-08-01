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
  late TextEditingController _fabricanteController;
  late TextEditingController _precoConcorrenciaController;

  late final CalculadoraPrecoMarkup _calculadora;
  late final CalculadoraDesconto _calculadoraDesconto;

  bool _destacarProduto = false;
  bool _exibirNoCatalogo = true;
  bool _ativo = true;

  // Imagens/vídeos agora são geridos numa tela dedicada
  // (GerenciarMidiasProdutoScreen, persiste direto no banco). Guardamos só
  // a capa (frente) aqui pra exibir a miniatura e o verso pra não perdê-lo
  // ao salvar o resto do formulário — ambos são recarregados do banco
  // depois de voltar dessa tela, já que ela pode ter alterado os dois.
  String? _imagemUrlAtual;
  String? _imagemUrlVersoAtual;

  bool _isLoading = false;
  List<String> _categoriasExistentes = [];
  bool _categoriasCarregadas = false;

  List<String> _subcategorias = []; // subcategorias da categoria selecionada
  bool _subcategoriasCarregadas = false;

  List<String> _fabricantes = [];
  bool _fabricantesCarregadas = false;

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
    // formatarValidade normaliza formatos vindos de importação de planilha
    // (ex: ISO "2026-04-30T00:00:00.000Z") pro DD/MM/AAAA que este campo
    // espera — sem isso, editar um produto assim mostrava a data crua e o
    // formatador de digitação (DataInputFormatter) bagunçava tudo ao tocar.
    _validadeController =
        TextEditingController(text: ProdutoValidators.formatarValidade(widget.produto.validade));
    _empresaController =
        TextEditingController(text: widget.produto.empresa ?? '');
    _fabricanteController =
        TextEditingController(text: widget.produto.fabricante ?? '');
    _precoConcorrenciaController = TextEditingController(
        text: ProdutoValidators.formatarMoeda(widget.produto.precoConcorrencia));

    _destacarProduto = widget.produto.destacar;
    _exibirNoCatalogo = widget.produto.exibirNoCatalogo;
    _ativo = widget.produto.ativo;

    _imagemUrlAtual = widget.produto.imagemUrl;
    _imagemUrlVersoAtual = widget.produto.imagemUrlSecundaria;

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
    _carregarSubcategorias();
    _carregarFabricantes();
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
    _fabricanteController.dispose();
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
          .toSet();

      // A tabela `categorias` só é preenchida quando alguém abre "Gerenciar
      // categorias" (que faz esse backfill) — até isso acontecer pra todo o
      // catálogo, ela fica incompleta. Unimos com as categorias realmente
      // em uso em `produtos.categoria` (mesma fonte que "Gerenciar
      // categorias" usa) pra sempre listar todas, não só as já cadastradas
      // nessa tabela — isso também cobre a categoria atual do produto.
      final produtosData = await supabase.from('produtos').select('categoria');
      categorias.addAll(
        (produtosData as List)
            .map((p) => (p['categoria'] as String?) ?? '')
            .where((c) => c.isNotEmpty),
      );

      if (!mounted) return;
      setState(() {
        _categoriasExistentes = categorias.toList();
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

  // Abre a galeria de imagens/vídeos do produto — as alterações lá são
  // salvas direto no banco (imediatas, não dependem do botão "Salvar" desta
  // tela). Ao voltar, recarrega a capa/verso porque podem ter mudado.
  Future<void> _abrirGerenciarMidias() async {
    final produtoId = widget.produto.id;
    if (produtoId == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GerenciarMidiasProdutoScreen(produtoId: produtoId)),
    );

    if (!mounted) return;
    try {
      final row = await supabase
          .from('produtos')
          .select('imagem_url, imagem_url_secundaria')
          .eq('id', produtoId)
          .single();
      if (!mounted) return;
      setState(() {
        _imagemUrlAtual = row['imagem_url'] as String? ?? '';
        _imagemUrlVersoAtual = row['imagem_url_secundaria'] as String?;
      });
    } catch (e) {
      debugPrint('Erro ao recarregar imagens do produto: $e');
    }
  }

  // Salva as alterações do produto no Supabase.
  Future<void> _salvarEdicao() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

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
      imagemUrl: _imagemUrlAtual ?? widget.produto.imagemUrl,
      imagemUrlSecundaria: _imagemUrlVersoAtual,
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
      fabricante: _fabricanteController.text.isNotEmpty
          ? _fabricanteController.text
          : widget.produto.fabricante,
      precoConcorrencia: ProdutoValidators.parseNumero(_precoConcorrenciaController.text) ??
          widget.produto.precoConcorrencia,
      estoqueId: widget.produto.estoqueId,
      unidadeMedida: widget.produto.unidadeMedida,
      permiteFracionamento: widget.produto.permiteFracionamento,
    );

    if (!mounted) return;

    try {
      await Provider.of<ProdutoProvider>(context, listen: false)
          .atualizarProduto(produtoAtualizado);

      if (widget.produto.id != null) {
        await _canaisKey.currentState
            ?.salvar(widget.produto.id!, produtoAtualizado.preco);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Produto atualizado com sucesso!')));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao atualizar produto: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Custo/margem/preço de concorrência não aparecem pra vendedor — o
    // controller continua com o valor original carregado, então salvar
    // sem esses campos visíveis não perde/zera o dado, só não mostra.
    final isVendedor = context.watch<AuthProvider>().isVendedor;

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
                    GestureDetector(
                      onTap: _abrirGerenciarMidias,
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Container(
                              width: 120,
                              height: 120,
                              color: colorScheme.surfaceContainerHighest,
                              child: (_imagemUrlAtual != null && _imagemUrlAtual!.isNotEmpty)
                                  ? Image.network(
                                      _imagemUrlAtual!,
                                      width: 120,
                                      height: 120,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Icon(
                                        Icons.image,
                                        size: 40,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    )
                                  : Icon(
                                      Icons.add_photo_alternate_outlined,
                                      size: 40,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                            ),
                          ),
                          Positioned(
                            bottom: 4,
                            right: 4,
                            child: Material(
                              color: colorScheme.primary,
                              shape: const CircleBorder(),
                              child: Padding(
                                padding: const EdgeInsets.all(6),
                                child: Icon(Icons.edit, size: 16, color: colorScheme.onPrimary),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Toque pra gerenciar imagens e vídeos',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
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
                                setState(() => _categoriaController.text = value!);
                                _carregarSubcategorias();
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
