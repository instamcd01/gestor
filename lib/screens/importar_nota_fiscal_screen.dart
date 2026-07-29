import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/entrada.dart';
import '../models/fornecedor.dart';
import '../models/produto.dart';
import '../providers/auth_provider.dart';
import '../providers/entrada_provider.dart';
import '../providers/fornecedor_provider.dart';
import '../providers/produto_provider.dart';
import '../services/nfe_xml_parser.dart';
import '../utils/formatadores_input.dart';
import '../utils/produto_validators.dart';
import '../widgets/aviso_banner.dart';
import 'cadastro_produto_screen.dart';
import 'despesas_screen.dart';

final _moeda = NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$');
final _data = DateFormat('dd/MM/yyyy');

String _formatarData(DateTime data) =>
    '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}';

/// Só aceita data completa (DD/MM/AAAA) e válida — dígitos parciais
/// enquanto o usuário ainda está digitando retornam null sem reclamar.
DateTime? _parsearData(String texto) {
  final partes = texto.split('/');
  if (partes.length != 3 || partes[2].length != 4) return null;
  final dia = int.tryParse(partes[0]);
  final mes = int.tryParse(partes[1]);
  final ano = int.tryParse(partes[2]);
  if (dia == null || mes == null || ano == null) return null;
  final data = DateTime(ano, mes, dia);
  if (data.day != dia || data.month != mes || data.year != ano) return null;
  return data;
}

String _formatarFator(double fator) => fator.toStringAsFixed(2).replaceAll('.', ',');

String _formatarQuantidade(double q) => q == q.roundToDouble() ? q.toStringAsFixed(0) : q.toStringAsFixed(2).replaceAll('.', ',');

/// Importa uma NF-e (XML) de um fornecedor: casa os itens por código de
/// barras contra os produtos já cadastrados, mostra uma prévia — separada
/// em pendentes/prontos, com o produto vinculado sempre visível por nome
/// (e o vínculo sempre trocável, mesmo já casado, pra corrigir um EAN
/// cadastrado errado), quantidade/custo editáveis, validade digitada,
/// aviso de custo divergente, fator de custo do fornecedor ajustável ali
/// mesmo — e parcelas que virarão boletos/despesas. Um resumo final
/// confirma o que vai acontecer antes de gravar (soma no estoque via
/// trigger no banco + uma `Despesa` por parcela). Só cobre XML direto por
/// enquanto — PDF/DANFE impressa (consulta à Sefaz pela chave de acesso)
/// é uma fase futura, pausada.
class ImportarNotaFiscalScreen extends StatefulWidget {
  const ImportarNotaFiscalScreen({super.key});

  @override
  State<ImportarNotaFiscalScreen> createState() => _ImportarNotaFiscalScreenState();
}

class _ImportarNotaFiscalScreenState extends State<ImportarNotaFiscalScreen> {
  bool _processando = false;
  NfeImportada? _nfe;
  List<ItemEntrada> _itensResolvidos = [];
  Fornecedor? _fornecedorExistente;
  final Map<int, TextEditingController> _validadeControllers = {};
  final Map<int, TextEditingController> _quantidadeControllers = {};
  final Map<int, TextEditingController> _custoControllers = {};
  // Itens com quantidade/custo editados manualmente não são recalculados
  // quando o fator de custo do fornecedor muda — senão um ajuste manual
  // seria silenciosamente perdido ao mexer no fator.
  final Set<int> _itensComValorManual = {};
  late final TextEditingController _fatorController;

  bool get _temPreVia => _nfe != null;

  Map<String, Produto> get _produtosPorId => {
        for (final p in context.read<ProdutoProvider>().produtos)
          if (p.id != null) p.id!: p,
      };

  @override
  void initState() {
    super.initState();
    _fatorController = TextEditingController(text: _formatarFator(1.0));
  }

  @override
  void dispose() {
    _limparControllers();
    _fatorController.dispose();
    super.dispose();
  }

  void _limparControllers() {
    for (final c in [..._validadeControllers.values, ..._quantidadeControllers.values, ..._custoControllers.values]) {
      c.dispose();
    }
    _validadeControllers.clear();
    _quantidadeControllers.clear();
    _custoControllers.clear();
    _itensComValorManual.clear();
  }

  TextEditingController _controllerValidade(int index) {
    return _validadeControllers.putIfAbsent(index, () {
      final validade = _itensResolvidos[index].dataValidade;
      return TextEditingController(text: validade != null ? _formatarData(validade) : '');
    });
  }

  TextEditingController _controllerQuantidade(int index) {
    return _quantidadeControllers.putIfAbsent(
      index,
      () => TextEditingController(text: _formatarQuantidade(_itensResolvidos[index].quantidade)),
    );
  }

  TextEditingController _controllerCusto(int index) {
    return _custoControllers.putIfAbsent(
      index,
      () => TextEditingController(text: ProdutoValidators.formatarMoeda(_itensResolvidos[index].custoUnitario)),
    );
  }

  /// Combina os dados fixos do item (`base`, sempre o valor original da
  /// NF-e, nunca mutado) com o que já foi resolvido pelo usuário (`atual`:
  /// produtoId vinculado, lote/validade digitados) e o fator de custo
  /// vigente — assim reaplicar um novo fator nunca perde vínculo/validade
  /// já preenchidos, e nunca acumula arredondamento de fator sobre fator.
  ItemEntrada _comFator(ItemEntrada base, ItemEntrada atual, double fator) {
    return ItemEntrada(
      id: atual.id,
      produtoId: atual.produtoId,
      eanNfe: base.eanNfe,
      descricaoNfe: base.descricaoNfe,
      ncm: base.ncm,
      quantidade: base.quantidade,
      custoUnitario: base.custoUnitario * fator,
      valorTotal: base.valorTotal * fator,
      numeroLote: atual.numeroLote,
      dataFabricacao: atual.dataFabricacao,
      dataValidade: atual.dataValidade,
    );
  }

  /// Alguns fornecedores faturam a NF-e com um valor unitário diferente do
  /// custo real de aquisição — o fator (padrão vem do cadastro do
  /// fornecedor, mas pode ser ajustado aqui pra essa nota específica, ex:
  /// o fornecedor mudou o desconto nesse pedido) ajusta isso antes de
  /// gravar/comparar. Ajustar aqui vale só pra essa importação, não
  /// sobrescreve o padrão salvo no cadastro do fornecedor. Itens com
  /// quantidade/custo editados à mão ficam de fora do recálculo.
  void _reaplicarFator(double novoFator) {
    final nfe = _nfe;
    if (nfe == null || novoFator <= 0) return;
    setState(() {
      for (var i = 0; i < _itensResolvidos.length; i++) {
        if (_itensComValorManual.contains(i)) continue;
        _itensResolvidos[i] = _comFator(nfe.itens[i], _itensResolvidos[i], novoFator);
        _custoControllers[i]?.text = ProdutoValidators.formatarMoeda(_itensResolvidos[i].custoUnitario);
      }
    });
  }

  /// Tenta casar por EAN só os itens ainda pendentes — usada tanto no
  /// carregamento inicial quanto depois de cadastrar um produto novo a
  /// partir de um item pendente (não mexe nos que já foram vinculados).
  void _recasarPendentes(List<Produto> produtos) {
    final produtoIdPorEan = <String, String>{
      for (final p in produtos)
        if (p.id != null && p.codigoBarras.isNotEmpty) p.codigoBarras: p.id!,
    };

    setState(() {
      _itensResolvidos = _itensResolvidos.map((item) {
        if (item.casado) return item;
        final produtoId = item.eanNfe.isNotEmpty ? produtoIdPorEan[item.eanNfe] : null;
        return produtoId != null ? item.copyWith(produtoId: produtoId, produtoIdDefinir: true) : item;
      }).toList();
    });
  }

  Future<void> _selecionarArquivo() async {
    final resultado = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xml'],
    );
    if (resultado == null || !mounted) return;

    setState(() => _processando = true);
    try {
      final arquivo = File(resultado.files.single.path!);
      final conteudo = await arquivo.readAsString();
      final nfe = NfeXmlParser.parse(conteudo);

      final produtoProvider = context.read<ProdutoProvider>();
      await produtoProvider.carregarProdutos();

      final fornecedorProvider = context.read<FornecedorProvider>();
      await fornecedorProvider.carregar();
      final cnpjNfe = nfe.fornecedorDetectado.cnpjCpf.replaceAll(RegExp(r'[^0-9]'), '');
      Fornecedor? fornecedorExistente;
      for (final f in fornecedorProvider.fornecedores) {
        if (cnpjNfe.isNotEmpty && f.cnpjCpf.replaceAll(RegExp(r'[^0-9]'), '') == cnpjNfe) {
          fornecedorExistente = f;
          break;
        }
      }
      final fator = fornecedorExistente?.fatorCusto ?? 1.0;

      if (!mounted) return;
      _limparControllers();
      _fatorController.text = _formatarFator(fator);
      setState(() {
        _nfe = nfe;
        _itensResolvidos = [for (final item in nfe.itens) _comFator(item, item, fator)];
        _fornecedorExistente = fornecedorExistente;
        _processando = false;
      });
      _recasarPendentes(produtoProvider.produtos);
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() => _processando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      setState(() => _processando = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao ler o XML: $e')));
    }
  }

  Future<void> _vincularProduto(int index) async {
    final item = _itensResolvidos[index];
    final produtoProvider = context.read<ProdutoProvider>();
    final escolhido = await showDialog<Produto>(
      context: context,
      // Sem autofocus (no campo de busca, abaixo) + sem fechar tocando
      // fora: com o teclado aberto e o diálogo fechando por barrier-dismiss
      // no mesmo frame, bate num bug conhecido do framework do Flutter
      // (assert `_dependents.isEmpty` ao desativar o Overlay/IME).
      barrierDismissible: false,
      builder: (ctx) => _BuscarProdutoDialog(produtos: produtoProvider.produtos),
    );
    if (escolhido == null || !mounted) return;

    final atualizarCodigo = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DivergenciaDialog(item: item, produto: escolhido),
    );
    if (atualizarCodigo == null || !mounted) return;

    if (atualizarCodigo && item.eanNfe.isNotEmpty) {
      escolhido.codigoBarras = item.eanNfe;
      await produtoProvider.atualizarProduto(escolhido);
    }

    setState(() {
      _itensResolvidos[index] = item.copyWith(produtoId: escolhido.id, produtoIdDefinir: true);
    });
  }

  Future<void> _cadastrarNovoProduto(int index) async {
    final item = _itensResolvidos[index];
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CadastroProdutoScreen(
          produtoInicial: Produto(
            nome: item.descricaoNfe,
            preco: 0,
            descricao: '',
            categoria: '',
            estoqueAtual: 0,
            estoqueMinimo: 0,
            imagemUrl: '',
            codigoBarras: item.eanNfe,
            custo: item.custoUnitario,
          ),
        ),
      ),
    );
    if (!mounted) return;
    final produtoProvider = context.read<ProdutoProvider>();
    await produtoProvider.carregarProdutos();
    if (!mounted) return;
    _recasarPendentes(produtoProvider.produtos);
  }

  void _digitarValidade(int index, String texto) {
    final item = _itensResolvidos[index];
    final data = _parsearData(texto);
    // Só grava quando a data digitada é completa e válida — dígitos
    // parciais não mexem no item (nem apagam uma validade já preenchida).
    if (data == null) return;
    _itensResolvidos[index] = item.copyWith(dataValidade: data, dataValidadeDefinir: true);
  }

  /// Recalcula `valorTotal` como quantidade × custo sempre que um dos dois
  /// é editado à mão — e marca o item como "manual" pra não ser mais
  /// sobrescrito se o fator de custo do fornecedor mudar depois.
  void _digitarQuantidadeOuCusto(int index) {
    final item = _itensResolvidos[index];
    final quantidade = ProdutoValidators.parseNumero(_controllerQuantidade(index).text);
    final custo = ProdutoValidators.parseNumero(_controllerCusto(index).text);
    if (quantidade == null || custo == null) return;

    setState(() {
      _itensComValorManual.add(index);
      _itensResolvidos[index] = item.copyWith(
        quantidade: quantidade,
        custoUnitario: custo,
        valorTotal: quantidade * custo,
      );
    });
  }

  Future<void> _confirmar() async {
    final nfe = _nfe;
    if (nfe == null) return;

    final produtos = _produtosPorId;
    final pendentes = _itensResolvidos.where((i) => !i.casado).length;
    final vaiParaEstoque = _itensResolvidos.length - pendentes;
    final custosDivergentes = _itensResolvidos.where((i) {
      if (!i.casado || i.custoUnitario <= 0) return false;
      final produto = produtos[i.produtoId];
      return produto != null && produto.custo != i.custoUnitario;
    }).length;

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar importação'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$vaiParaEstoque item(ns) vão somar no estoque.'),
            if (pendentes > 0)
              Text('$pendentes pendente(s) NÃO vão afetar o estoque.', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            if (custosDivergentes > 0) Text('$custosDivergentes produto(s) terão o custo cadastrado atualizado.'),
            if (nfe.parcelas.isNotEmpty)
              Text('${nfe.parcelas.length} boleto(s) serão criados, totalizando ${_moeda.format(nfe.parcelas.fold<double>(0, (s, p) => s + p.valor))}.')
            else
              const Text('Nenhum boleto será criado (nota sem parcela/duplicata).'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Revisar de novo')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (confirmou != true || !mounted) return;

    await _executarImportacao(nfe, produtos);
  }

  Future<void> _executarImportacao(NfeImportada nfe, Map<String, Produto> produtos) async {
    setState(() => _processando = true);
    try {
      final empresaId = context.read<AuthProvider>().empresaId;
      if (empresaId == null) throw StateError('Empresa não identificada.');

      String? fornecedorId = _fornecedorExistente?.id;
      if (fornecedorId == null && nfe.fornecedorDetectado.cnpjCpf.isNotEmpty) {
        final novo = await context.read<FornecedorProvider>().adicionar(nfe.fornecedorDetectado);
        fornecedorId = novo.id;
      }

      // Custo não informado pela nota (<=0) nunca sobrescreve o cadastro —
      // evita zerar o custo real por causa de nota mal preenchida. Só
      // atualiza quando realmente mudou, pra não gerar histórico à toa.
      for (final item in _itensResolvidos) {
        if (!item.casado || item.custoUnitario <= 0) continue;
        final produto = produtos[item.produtoId];
        if (produto == null || produto.custo == item.custoUnitario) continue;
        produto.custo = item.custoUnitario;
        await context.read<ProdutoProvider>().atualizarProduto(produto);
      }

      await context.read<EntradaProvider>().importarNfe(
            nfe: nfe,
            itensResolvidos: _itensResolvidos,
            fornecedorId: fornecedorId,
          );

      if (!mounted) return;
      final pendentes = _itensResolvidos.where((i) => !i.casado).length;
      final temBoletos = nfe.parcelas.isNotEmpty;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          'Nota importada: ${_itensResolvidos.length - pendentes} item(ns) somado(s) ao estoque'
          '${temBoletos ? ', ${nfe.parcelas.length} boleto(s) criado(s)' : ''}'
          '${pendentes > 0 ? ', $pendentes sem produto cadastrado (não afetaram estoque)' : ''}.',
        ),
        action: temBoletos
            ? SnackBarAction(
                label: 'Ver boletos',
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DespesasScreen())),
              )
            : null,
        duration: const Duration(seconds: 6),
      ));
      _limparControllers();
      setState(() {
        _nfe = null;
        _itensResolvidos = [];
        _fornecedorExistente = null;
        _processando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _processando = false);
      final mensagem = e.toString().contains('entradas_empresa_chave_unica')
          ? 'Essa nota fiscal já foi importada antes.'
          : 'Erro ao importar: $e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagem)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Importar Nota Fiscal')),
      body: _processando
          ? const Center(child: CircularProgressIndicator())
          : _temPreVia
              ? _prevoia(context)
              : _estadoInicial(context),
    );
  }

  Widget _estadoInicial(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.description_outlined, size: 56, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'Selecione o XML da NF-e do fornecedor pra dar entrada nos produtos e gerar os boletos automaticamente.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _selecionarArquivo,
              icon: const Icon(Icons.upload_file),
              label: const Text('Selecionar XML'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _prevoia(BuildContext context) {
    final nfe = _nfe!;
    final colorScheme = Theme.of(context).colorScheme;
    final produtos = _produtosPorId;

    final indicesPendentes = <int>[];
    final indicesCasados = <int>[];
    for (var i = 0; i < _itensResolvidos.length; i++) {
      (_itensResolvidos[i].casado ? indicesCasados : indicesPendentes).add(i);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('NF ${nfe.numero ?? "?"} / série ${nfe.serie ?? "?"}',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                          if (nfe.dataEmissao != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text('Emitida em ${_data.format(nfe.dataEmissao!)}',
                                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 13)),
                            ),
                        ],
                      ),
                    ),
                    Text(_moeda.format(nfe.valorTotalNota),
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  ],
                ),
                const Divider(height: 24),
                Text(
                  _fornecedorExistente != null
                      ? 'Fornecedor: ${_fornecedorExistente!.nome}'
                      : 'Fornecedor: ${nfe.fornecedorDetectado.nome} (novo, será cadastrado)',
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 110,
                      child: TextFormField(
                        controller: _fatorController,
                        decoration: const InputDecoration(labelText: 'Fator de custo', isDense: true),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [DecimalInputFormatter()],
                        onChanged: (texto) {
                          final valor = ProdutoValidators.parseNumero(texto);
                          if (valor != null && valor > 0) _reaplicarFator(valor);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Ajusta o custo unitário dos itens abaixo (não muda o valor dos boletos). '
                        'Vale só pra essa nota — pra mudar o padrão do fornecedor, edite em Fornecedores.',
                        style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (indicesPendentes.isNotEmpty) ...[
          Row(
            children: [
              Icon(Icons.error_outline, size: 18, color: colorScheme.error),
              const SizedBox(width: 6),
              Text('Pendentes (${indicesPendentes.length})',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: colorScheme.error)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Sem produto cadastrado com esse código de barras — vincule a um produto existente ou cadastre um novo. Não vão somar no estoque até serem resolvidos.',
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12.5),
          ),
          const SizedBox(height: 8),
          for (final i in indicesPendentes) _itemCard(context, i, produtos[_itensResolvidos[i].produtoId]),
          const SizedBox(height: 16),
        ],
        if (indicesCasados.isNotEmpty) ...[
          Text('Prontos (${indicesCasados.length})', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final i in indicesCasados) _itemCard(context, i, produtos[_itensResolvidos[i].produtoId]),
        ],
        const SizedBox(height: 12),
        Text('Boletos (${nfe.parcelas.length})', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (nfe.parcelas.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text('Nenhuma parcela/duplicata encontrada na nota — nenhuma despesa será criada.',
                style: TextStyle(color: colorScheme.onSurfaceVariant)),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < nfe.parcelas.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text('Parcela ${nfe.parcelas[i].numero}/${nfe.parcelas.length}'),
                    subtitle: Text('Vence em ${_data.format(nfe.parcelas[i].vencimento)}'),
                    trailing: Text(_moeda.format(nfe.parcelas[i].valor)),
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  _limparControllers();
                  setState(() {
                    _nfe = null;
                    _itensResolvidos = [];
                    _fornecedorExistente = null;
                  });
                },
                child: const Text('Cancelar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _confirmar,
                child: const Text('Confirmar importação'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _itemCard(BuildContext context, int index, Produto? produtoCasado) {
    final item = _itensResolvidos[index];
    final colorScheme = Theme.of(context).colorScheme;

    ({String texto, TipoAviso tipo})? avisoCusto;
    if (produtoCasado != null) {
      if (item.custoUnitario <= 0) {
        avisoCusto = (
          texto: 'Custo não informado pela nota — mantém ${_moeda.format(produtoCasado.custo)} do cadastro.',
          tipo: TipoAviso.info,
        );
      } else if (produtoCasado.custo != item.custoUnitario) {
        final subiu = item.custoUnitario > produtoCasado.custo;
        avisoCusto = (
          texto: 'Custo ${subiu ? "subiu" : "caiu"}: era ${_moeda.format(produtoCasado.custo)} → nota traz ${_moeda.format(item.custoUnitario)}.',
          tipo: subiu ? TipoAviso.alerta : TipoAviso.info,
        );
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  item.casado ? Icons.check_circle : Icons.error_outline,
                  color: item.casado ? Colors.green : colorScheme.error,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(item.descricaoNfe, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                const SizedBox(width: 8),
                Text(_moeda.format(item.valorTotal), style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 30, top: 2),
              child: Text(
                item.eanNfe.isEmpty ? 'sem código de barras na nota' : 'EAN ${item.eanNfe}',
                style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12.5),
              ),
            ),
            // Sempre mostra o produto vinculado por nome — sem isso, um EAN
            // cadastrado errado casa "silenciosamente" com o produto errado
            // e não tem como perceber antes de confirmar.
            Padding(
              padding: const EdgeInsets.only(left: 30, top: 4),
              child: item.casado
                  ? (produtoCasado != null
                      ? Row(
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 14, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text('Vinculado a: ${produtoCasado.nome}',
                                  style: TextStyle(color: colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic, fontSize: 12.5)),
                            ),
                          ],
                        )
                      : Text('Produto vinculado não encontrado (pode ter sido excluído) — vincule novamente.',
                          style: TextStyle(color: colorScheme.error, fontSize: 12.5)))
                  : const SizedBox.shrink(),
            ),
            if (avisoCusto != null) ...[
              const SizedBox(height: 10),
              AvisoBanner(texto: avisoCusto.texto, tipo: avisoCusto.tipo),
            ],
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _vincularProduto(index),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  icon: const Icon(Icons.link, size: 16),
                  label: Text(item.casado ? 'Trocar vínculo' : 'Vincular existente'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _cadastrarNovoProduto(index),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  icon: const Icon(Icons.add_box_outlined, size: 16),
                  label: const Text('Cadastrar novo'),
                ),
                SizedBox(
                  width: 90,
                  child: TextFormField(
                    controller: _controllerQuantidade(index),
                    decoration: const InputDecoration(labelText: 'Qtd.', isDense: true),
                    style: const TextStyle(fontSize: 13),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [DecimalInputFormatter()],
                    onChanged: (_) => _digitarQuantidadeOuCusto(index),
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: TextFormField(
                    controller: _controllerCusto(index),
                    decoration: const InputDecoration(labelText: 'Custo unit.', isDense: true),
                    style: const TextStyle(fontSize: 13),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [MoedaInputFormatter()],
                    onChanged: (_) => _digitarQuantidadeOuCusto(index),
                  ),
                ),
                SizedBox(
                  width: 150,
                  child: TextFormField(
                    controller: _controllerValidade(index),
                    decoration: const InputDecoration(
                      labelText: 'Validade',
                      hintText: 'DD/MM/AAAA',
                      isDense: true,
                      prefixIcon: Icon(Icons.event_outlined, size: 18),
                    ),
                    style: const TextStyle(fontSize: 13),
                    keyboardType: TextInputType.datetime,
                    inputFormatters: [DataInputFormatter()],
                    onChanged: (texto) => _digitarValidade(index, texto),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Diálogo de busca simples por nome sobre os produtos já carregados —
/// usado pra vincular um item da nota (pendente ou já casado, pra trocar
/// um vínculo errado) a um produto existente.
class _BuscarProdutoDialog extends StatefulWidget {
  final List<Produto> produtos;

  const _BuscarProdutoDialog({required this.produtos});

  @override
  State<_BuscarProdutoDialog> createState() => _BuscarProdutoDialogState();
}

class _BuscarProdutoDialogState extends State<_BuscarProdutoDialog> {
  String _busca = '';

  @override
  Widget build(BuildContext context) {
    final filtrados = _busca.isEmpty
        ? widget.produtos
        : widget.produtos.where((p) => p.nome.toLowerCase().contains(_busca.toLowerCase())).toList();

    return AlertDialog(
      title: const Text('Vincular a um produto'),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            TextField(
              decoration: const InputDecoration(labelText: 'Buscar por nome', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => _busca = v),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: filtrados.length,
                itemBuilder: (context, i) => ListTile(
                  title: Text(filtrados[i].nome),
                  subtitle: Text(filtrados[i].codigoBarras.isEmpty ? 'Sem código de barras cadastrado' : 'EAN: ${filtrados[i].codigoBarras}'),
                  onTap: () => Navigator.pop(context, filtrados[i]),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
      ],
    );
  }
}

/// Mostra por que o item da nota não casou sozinho com o produto escolhido
/// (EAN da nota vs. EAN cadastrado) e pergunta se deve corrigir o cadastro.
class _DivergenciaDialog extends StatefulWidget {
  final ItemEntrada item;
  final Produto produto;

  const _DivergenciaDialog({required this.item, required this.produto});

  @override
  State<_DivergenciaDialog> createState() => _DivergenciaDialogState();
}

class _DivergenciaDialogState extends State<_DivergenciaDialog> {
  late bool _atualizarCodigo = widget.item.eanNfe.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Confirmar vínculo'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Nota: ${widget.item.descricaoNfe}'),
          Text('EAN na nota: ${widget.item.eanNfe.isEmpty ? "sem código" : widget.item.eanNfe}'),
          const SizedBox(height: 12),
          Text('Cadastro: ${widget.produto.nome}'),
          Text('EAN cadastrado: ${widget.produto.codigoBarras.isEmpty ? "sem código" : widget.produto.codigoBarras}'),
          if (widget.item.eanNfe.isNotEmpty) ...[
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('Atualizar código de barras do produto cadastrado'),
              subtitle: const Text('Assim a próxima nota com esse item casa sozinha'),
              value: _atualizarCodigo,
              onChanged: (v) => setState(() => _atualizarCodigo = v ?? false),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(context, _atualizarCodigo), child: const Text('Vincular')),
      ],
    );
  }
}
