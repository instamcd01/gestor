import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:excel/excel.dart';
import "package:file_picker/file_picker.dart";
import 'package:share_plus/share_plus.dart';
import '../providers/auth_provider.dart';
import '../providers/produto_provider.dart';
import '../models/produto.dart';
import '../repositories/marketplace_repository.dart';
import '../repositories/produto_canal_repository.dart';
import '../repositories/produto_repository.dart';
import '../utils/planilha_utils.dart';

class _LinhaCanalIfood {
  // Correlação por SKU (o "ID" da planilha) em vez de código de barras: o
  // código de barras pode se repetir entre produtos diferentes na planilha
  // real da loja (variação/erro de digitação), o que faria vários produtos
  // colidirem no mesmo canal iFood. SKU é o identificador que a própria
  // planilha usa como único por linha.
  final String? sku;
  final String codigoBarras;
  final double preco;
  final bool disponivel;
  _LinhaCanalIfood({this.sku, required this.codigoBarras, required this.preco, required this.disponivel});
}

/// Uma linha já interpretada da planilha, antes de virar [Produto] de
/// verdade — guarda também o número da linha original (pra mensagens de
/// erro) e se ela vai virar produto novo ou atualização de um existente.
class _LinhaImportada {
  final int numeroLinha;
  final Produto produto;
  final bool atualizacao;
  _LinhaImportada({required this.numeroLinha, required this.produto, required this.atualizacao});
}

/// Aliases de cabeçalho reconhecidos pra planilha de produtos — a planilha
/// real da loja ("Planilha Mestre") tem uma ordem de colunas totalmente
/// diferente do modelo genérico gerado por "Baixar Planilha Base", então
/// mapear por posição fixa quebraria os dados (ver [MapaColunasPlanilha]).
const _aliasesProdutos = {
  'id_externo': ['id'],
  'nome': ['nome', 'nome*'],
  'grupo': ['grupo', 'categoria'],
  'codigo_barras': ['código de barras', 'codigo de barras', 'código', 'codigo'],
  'custo': ['custo', 'custo unitário', 'custo unitario'],
  'preco': ['preço loja', 'preco loja', 'preço unitário*', 'preco unitario', 'preço', 'preco'],
  'preco_promocional': ['preço promoção', 'preco promocao', 'preço promocional', 'preco promocional'],
  'preco_ifood': ['preço ifood', 'preco ifood'],
  'validade': ['validade'],
  'estoque_atual': ['qtd. atual estoque', 'estoque atual', 'qtd atual estoque'],
  'estoque_minimo': ['quantidade minima', 'quantidade mínima', 'estoque mínimo', 'estoque minimo'],
  'markup': ['markup'],
  'lucro': ['lucro'],
  'preco_concorrencia': ['preço concorrencia', 'preco concorrencia', 'preço concorrência'],
  'empresa': ['empresa'],
  'descricao': ['descriçao', 'descrição', 'descricao'],
  'destacar': ['destacar'],
  'exibir_no_catalogo': ['exibir no catálogo', 'exibir no catalogo'],
  'ativo': ['ativo'],
  'fracionado': ['fracionado?', 'fracionado'],
};

class ImportarProdutosScreen extends StatefulWidget {
  const ImportarProdutosScreen({super.key});

  @override
  State<ImportarProdutosScreen> createState() => _ImportarProdutosScreenState();
}

class _ImportarProdutosScreenState extends State<ImportarProdutosScreen> {
  bool _processando = false;

  /// Devolve (categoria, subcategoria) — a planilha real guarda os dois
  /// juntos numa célula só, separados por "|" (ex: "Areia | Granulado").
  (String, String?) _splitCategoria(String? texto) {
    if (texto == null) return ('', null);
    final partes = texto.split('|').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    if (partes.isEmpty) return ('', null);
    if (partes.length == 1) return (partes[0], null);
    return (partes[0], partes.sublist(1).join(' '));
  }

  Future<void> _iniciarImportacao() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      withData: true,
    );
    if (result == null || !mounted) return;

    setState(() => _processando = true);
    try {
      // `bytes` (não `path`) — no Web não existe caminho de arquivo real,
      // `withData: true` acima garante que o file_picker sempre traga os
      // bytes prontos, em qualquer plataforma.
      final bytesArquivo = result.files.single.bytes;
      if (bytesArquivo == null) throw StateError('Não foi possível ler o arquivo selecionado.');
      final bytesCorrigidos = corrigirNumFmtsInvalidos(bytesArquivo);
      final excel = Excel.decodeBytes(bytesCorrigidos);

      final produtoProvider = Provider.of<ProdutoProvider>(context, listen: false);
      await produtoProvider.carregarProdutos();
      final existentesPorSku = <String, Produto>{
        for (final p in produtoProvider.produtos)
          if (p.sku != null && p.sku!.isNotEmpty) p.sku!: p,
      };

      final linhas = <_LinhaImportada>[];
      final linhasSemNome = <int>[];
      final linhasComValorInvalido = <int>[];
      // Preenchido junto com o loop principal: toda linha com "Preço Ifood"
      // preenchido vira uma habilitação de canal (produto_canal), casada
      // por código de barras depois que os produtos já tiverem id.
      final canaisIfood = <_LinhaCanalIfood>[];

      // Só a aba de produtos "principal" vira catálogo — abas derivadas
      // (ex: "Planilha ifood", "Planilha KYTE") são recortes/exportações da
      // mesma base pra outro sistema, não fontes novas de produto. Se
      // tratássemos todas as abas como produtos, o mesmo item apareceria
      // duplicado uma vez por aba. Preferimos uma aba com "mestre" no nome;
      // sem isso, a primeira aba com colunas de produto reconhecíveis que
      // não pareça ser uma exportação de canal (nome contém "ifood"/"kyte").
      Sheet? abaProdutos;
      for (final entry in excel.tables.entries) {
        if (entry.key.toLowerCase().contains('mestre')) {
          abaProdutos = entry.value;
          break;
        }
      }
      if (abaProdutos == null) {
        for (final entry in excel.tables.entries) {
          final nomeAba = entry.key.toLowerCase();
          if (nomeAba.contains('ifood') || nomeAba.contains('kyte')) continue;
          if (entry.value.rows.isEmpty) continue;
          if (MapaColunasPlanilha.deCabecalho(entry.value.rows.first, _aliasesProdutos).indicePorCampo['nome'] !=
              null) {
            abaProdutos = entry.value;
            break;
          }
        }
      }

      if (abaProdutos != null && abaProdutos.rows.isNotEmpty) {
        final rows = abaProdutos.rows;
        final mapa = MapaColunasPlanilha.deCabecalho(rows.first, _aliasesProdutos);

        for (var i = 1; i < rows.length; i++) {
          final row = rows[i];
          final numeroLinha = i + 1;
          final nome = mapa.celula(row, 'nome');
          if (nome == null) {
            linhasSemNome.add(numeroLinha);
            continue;
          }

          bool avisoValor = false;
          double? valor(String campo) {
            final texto = mapa.celula(row, campo);
            if (texto == null) return null;
            final v = parseMoedaPlanilha(texto);
            if (v == null) avisoValor = true;
            return v;
          }

          final (categoria, subcategoria) = _splitCategoria(mapa.celula(row, 'grupo'));
          final skuExterno = mapa.celula(row, 'id_externo');
          final existente = skuExterno != null ? existentesPorSku[skuExterno] : null;

          final custo = valor('custo') ?? 0.0;
          final preco = valor('preco') ?? 0.0;
          final estoqueAtual =
              int.tryParse(parseMoedaPlanilha(mapa.celula(row, 'estoque_atual'))?.toStringAsFixed(0) ?? '') ?? 0;

          // Markup/Lucro/Ativo NÃO são lidos da planilha, mesmo tendo colunas
          // com esses nomes: nessa planilha real, essas três colunas contêm
          // FÓRMULAS (ex: "M2/E2", "IF(J2>0,1,0)"), não valores — o pacote de
          // leitura devolve o texto da fórmula, não o resultado calculado.
          // Lucro/markup seguem a mesma fórmula da planilha (preço − custo).
          // Ativo NÃO segue mais a fórmula da planilha (era "tem estoque"):
          // isso silenciosamente marcava como inativo qualquer produto que
          // estivesse zerado no momento da importação, mesmo quando o
          // lojista continuava vendendo normalmente — "ativo" no Gestor é
          // uma decisão manual (descontinuar ou não), sem relação com
          // estoque momentâneo. Produto já existente preserva o que já
          // estava marcado no Gestor; produto novo nasce ativo, igual ao
          // cadastro manual.
          final lucroValor = preco - custo;

          final produto = Produto(
            id: existente?.id,
            sku: skuExterno,
            nome: nome,
            categoria: categoria,
            subcategoria: subcategoria,
            codigoBarras: mapa.celula(row, 'codigo_barras') ?? '',
            custo: custo,
            preco: preco,
            precoPromocional: valor('preco_promocional'),
            precoIfood: valor('preco_ifood'),
            precoConcorrencia: valor('preco_concorrencia'),
            validade: mapa.celula(row, 'validade'),
            estoqueAtual: estoqueAtual,
            estoqueMinimo:
                int.tryParse(parseMoedaPlanilha(mapa.celula(row, 'estoque_minimo'))?.toStringAsFixed(0) ?? '') ?? 0,
            markup: custo > 0 ? '${(lucroValor / custo * 100).toStringAsFixed(1)}%' : null,
            lucro: lucroValor.toStringAsFixed(2),
            empresa: mapa.celula(row, 'empresa'),
            descricao: mapa.celula(row, 'descricao') ?? '',
            // A planilha nunca carrega foto — sem preservar o que já existe,
            // toda reimportação apagava a imagem (e, por tabela, a capa da
            // galeria de mídias) de qualquer produto já cadastrado.
            imagemUrl: existente?.imagemUrl ?? '',
            imagemUrlSecundaria: existente?.imagemUrlSecundaria,
            destacar: parseBooleanoPlanilha(mapa.celula(row, 'destacar')),
            exibirNoCatalogo: parseBooleanoPlanilha(mapa.celula(row, 'exibir_no_catalogo'), padrao: true),
            ativo: existente?.ativo ?? true,
            permiteFracionamento: parseBooleanoPlanilha(mapa.celula(row, 'fracionado')),
          );

          if (avisoValor) linhasComValorInvalido.add(numeroLinha);
          linhas.add(_LinhaImportada(numeroLinha: numeroLinha, produto: produto, atualizacao: existente != null));

          if (produto.precoIfood != null && (skuExterno != null || produto.codigoBarras.isNotEmpty)) {
            canaisIfood.add(_LinhaCanalIfood(
              sku: skuExterno,
              codigoBarras: produto.codigoBarras,
              preco: produto.precoIfood!,
              disponivel: true,
            ));
          }
        }
      }

      if (!mounted) return;
      setState(() => _processando = false);

      if (linhas.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nenhum produto reconhecido nessa planilha.')),
        );
        return;
      }

      await _confirmarEExecutar(linhas, linhasSemNome, linhasComValorInvalido, canaisIfood);
    } catch (e) {
      if (mounted) {
        setState(() => _processando = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao ler a planilha: $e')));
      }
    }
  }

  Future<void> _confirmarEExecutar(
    List<_LinhaImportada> linhas,
    List<int> linhasSemNome,
    List<int> linhasComValorInvalido,
    List<_LinhaCanalIfood> canaisIfood,
  ) async {
    final novos = linhas.where((l) => !l.atualizacao).length;
    final atualizacoes = linhas.where((l) => l.atualizacao).length;

    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirmar importação'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$novos produto${novos == 1 ? '' : 's'} novo${novos == 1 ? '' : 's'}'),
            if (atualizacoes > 0) Text('$atualizacoes atualização${atualizacoes == 1 ? '' : 'ões'} (mesmo ID já existente)'),
            if (canaisIfood.isNotEmpty)
              Text('${canaisIfood.length} produto${canaisIfood.length == 1 ? '' : 's'} será${canaisIfood.length == 1 ? '' : 'ão'} habilitado${canaisIfood.length == 1 ? '' : 's'} no canal iFood (tinham "Preço Ifood" preenchido)'),
            if (linhasSemNome.isNotEmpty)
              Text('${linhasSemNome.length} linha(s) ignorada(s) por falta de nome', style: const TextStyle(color: Colors.orange)),
            if (linhasComValorInvalido.isNotEmpty)
              Text('${linhasComValorInvalido.length} linha(s) com algum valor não reconhecido (ficou 0)',
                  style: const TextStyle(color: Colors.orange)),
            const SizedBox(height: 12),
            Text('Exemplo (primeira linha): ${linhas.first.produto.nome} — R\$ ${linhas.first.produto.preco.toStringAsFixed(2)}'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Importar')),
        ],
      ),
    );
    if (confirmado != true || !mounted) return;

    setState(() => _processando = true);
    try {
      final produtoProvider = Provider.of<ProdutoProvider>(context, listen: false);
      final empresaId = context.read<AuthProvider>().empresaId;
      if (empresaId == null) throw StateError('Empresa não identificada.');

      final novosProdutos = linhas.where((l) => !l.atualizacao).map((l) => l.produto).toList();
      final atualizacoesLista = linhas.where((l) => l.atualizacao).toList();

      var inseridos = 0;
      if (novosProdutos.isNotEmpty) {
        inseridos = await ProdutoRepository().criarEmLote(novosProdutos, empresaId: empresaId);
      }

      var atualizados = 0;
      for (final l in atualizacoesLista) {
        await ProdutoRepository().atualizar(l.produto);
        atualizados++;
      }

      await produtoProvider.carregarProdutos();

      var canaisHabilitados = 0;
      if (canaisIfood.isNotEmpty) {
        final marketplaces = await MarketplaceRepository().listarAtivos();
        final ifoodMatches = marketplaces.where((m) => m.nome.toLowerCase() == 'ifood');
        final ifood = ifoodMatches.isEmpty ? null : ifoodMatches.first;
        if (ifood != null) {
          // Correlação primária por SKU (único por linha na planilha real) —
          // código de barras é só um fallback pra linhas sem "ID" preenchido,
          // já que ele pode se repetir entre produtos diferentes (variação,
          // erro de digitação) e faria produtos distintos colidirem no mesmo
          // canal iFood se fosse a chave principal.
          final produtoIdPorSku = <String, String>{
            for (final p in produtoProvider.produtos)
              if (p.id != null && p.sku != null && p.sku!.isNotEmpty) p.sku!: p.id!,
          };
          final produtoIdPorBarras = <String, String>{
            for (final p in produtoProvider.produtos)
              if (p.id != null && p.codigoBarras.isNotEmpty) p.codigoBarras: p.id!,
          };
          // Deduplicado por produto_id: o upsert em lote não aceita duas
          // linhas apontando pro mesmo (produto_id, marketplace_id) dentro do
          // mesmo comando (erro do Postgres: "ON CONFLICT DO UPDATE command
          // cannot affect row a second time"). Só deve colidir de verdade se
          // o mesmo produto aparecer 2x na planilha — não mais por código de
          // barras compartilhado entre produtos diferentes.
          final itensCanalPorProduto = <String, ({String produtoId, String marketplaceId, double preco, bool disponivel})>{};
          for (final c in canaisIfood) {
            final produtoId = (c.sku != null ? produtoIdPorSku[c.sku] : null) ?? produtoIdPorBarras[c.codigoBarras];
            if (produtoId == null) continue;
            itensCanalPorProduto[produtoId] =
                (produtoId: produtoId, marketplaceId: ifood.id, preco: c.preco, disponivel: c.disponivel);
          }
          final itensCanal = itensCanalPorProduto.values.toList();
          if (itensCanal.isNotEmpty) {
            await ProdutoCanalRepository().salvarEmLote(itensCanal);
            canaisHabilitados = itensCanal.length;
          }
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$inseridos produtos importados, $atualizados atualizados'
            '${canaisHabilitados > 0 ? ', $canaisHabilitados habilitados no iFood' : ''}.',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao importar: $e')));
      }
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  Future<void> _gerarPlanilhaBase() async {
    final excel = Excel.createExcel();
    final Sheet sheet = excel['Produtos'];

    sheet.appendRow([
      TextCellValue('Nome'),
      // "Grupo" (não "Categoria" sozinho) pra já expor o formato aceito de
      // categoria+subcategoria numa célula só: "Categoria | Subcategoria".
      TextCellValue('Grupo'),
      TextCellValue('Código de Barras'),
      TextCellValue('Custo'),
      TextCellValue('Preço'),
      TextCellValue('Preço Promoção'),
      TextCellValue('Preço Ifood'),
      TextCellValue('Preço Concorrência'),
      TextCellValue('Validade'),
      TextCellValue('Estoque Atual'),
      TextCellValue('Estoque Mínimo'),
      TextCellValue('Empresa'),
      TextCellValue('Descrição'),
      TextCellValue('ID'),
      TextCellValue('Destacar'),
      TextCellValue('Exibir no Catálogo'),
      TextCellValue('Fracionado'),
      // Markup/Lucro ficaram de fora de propósito: a importação não lê
      // essas colunas, calcula os dois a partir de Custo/Preço (ver
      // comentário em _iniciarImportacao) — tê-las aqui só faria a pessoa
      // perder tempo preenchendo algo que seria ignorado.
    ]);

    final bytes = excel.encode() ?? [];

    await SharePlus.instance.share(
      ShareParams(
        files: [
          XFile.fromData(
            Uint8List.fromList(bytes),
            name: 'produtos_template.xlsx',
            mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
          ),
        ],
        text: 'Aqui está a planilha de produtos para preenchimento!',
      ),
    );
  }

  /// Gera uma planilha com o catálogo atual (todos os produtos, com o que
  /// já foi curado manualmente no Gestor — nome, categoria/subcategoria
  /// etc). Serve pra substituir uma "Planilha Mestre" desatualizada: os
  /// cabeçalhos usados aqui já são reconhecidos por [_MapaColunas], então
  /// essa mesma planilha pode voltar a ser reimportada depois de editada,
  /// como atualização (casando pelo ID/SKU).
  Future<void> _exportarCatalogoAtual() async {
    setState(() => _processando = true);
    try {
      final produtoProvider = Provider.of<ProdutoProvider>(context, listen: false);
      await produtoProvider.carregarProdutos();
      final produtos = List<Produto>.from(produtoProvider.produtos)
        ..sort((a, b) => a.nome.compareTo(b.nome));

      final excel = Excel.createExcel();
      final Sheet sheet = excel['Planilha Mestre'];

      sheet.appendRow([
        TextCellValue('Nome'),
        TextCellValue('Grupo'),
        TextCellValue('Código de Barras'),
        TextCellValue('Custo'),
        TextCellValue('Preço'),
        TextCellValue('Preço Promoção'),
        TextCellValue('Preço Ifood'),
        TextCellValue('Validade'),
        TextCellValue('Estoque Atual'),
        TextCellValue('Estoque Mínimo'),
        TextCellValue('Markup'),
        TextCellValue('Lucro'),
        TextCellValue('Preço Concorrência'),
        TextCellValue('Empresa'),
        TextCellValue('ID'),
        TextCellValue('Descrição'),
        TextCellValue('Destacar'),
        TextCellValue('Exibir no Catálogo'),
        TextCellValue('Ativo'),
        TextCellValue('Fracionado'),
      ]);

      for (final p in produtos) {
        // Mesmo formato "Categoria | Subcategoria" que a importação espera
        // de volta numa única célula (ver _splitCategoria).
        final grupo =
            (p.subcategoria != null && p.subcategoria!.isNotEmpty) ? '${p.categoria} | ${p.subcategoria}' : p.categoria;

        sheet.appendRow([
          TextCellValue(p.nome),
          TextCellValue(grupo),
          TextCellValue(p.codigoBarras),
          DoubleCellValue(p.custo),
          DoubleCellValue(p.preco),
          p.precoPromocional != null ? DoubleCellValue(p.precoPromocional!) : TextCellValue(''),
          p.precoIfood != null ? DoubleCellValue(p.precoIfood!) : TextCellValue(''),
          TextCellValue(p.validade ?? ''),
          IntCellValue(p.estoqueAtual),
          IntCellValue(p.estoqueMinimo),
          TextCellValue(p.markup ?? ''),
          TextCellValue(p.lucro ?? ''),
          p.precoConcorrencia != null ? DoubleCellValue(p.precoConcorrencia!) : TextCellValue(''),
          TextCellValue(p.empresa ?? ''),
          TextCellValue(p.sku ?? ''),
          TextCellValue(p.descricao),
          TextCellValue(p.destacar ? 'Sim' : 'Não'),
          TextCellValue(p.exibirNoCatalogo ? 'Sim' : 'Não'),
          TextCellValue(p.ativo ? 'Sim' : 'Não'),
          TextCellValue(p.permiteFracionamento ? 'Sim' : 'Não'),
        ]);
      }

      final bytes = excel.encode() ?? [];

      if (!mounted) return;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(bytes),
              name: 'planilha_mestre_atualizada.xlsx',
              mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
            ),
          ],
          text: 'Planilha mestre atualizada com os ${produtos.length} produtos do catálogo atual.',
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erro ao exportar planilha: $e')));
      }
    } finally {
      if (mounted) setState(() => _processando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Importar Produtos')),
      body: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Aceita a planilha da sua loja do jeito que ela já é — reconhece as colunas pelo '
                    'nome do cabeçalho, então não precisa reordenar nada. Se tiver mais de uma aba, só '
                    'a que tiver uma coluna de nome reconhecível é lida.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: _processando ? null : _iniciarImportacao,
                    child: const Text('Importar Produtos da Planilha'),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton(
                    onPressed: _processando ? null : _exportarCatalogoAtual,
                    child: const Text('Exportar Planilha Mestre Atualizada'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Gera uma planilha com os dados atuais do catálogo (já com o que você editou '
                    'no app) — use pra substituir uma planilha mestre desatualizada.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton(
                    onPressed: _processando ? null : _gerarPlanilhaBase,
                    child: const Text('Baixar Planilha Base (modelo genérico)'),
                  ),
                ],
              ),
            ),
          ),
          if (_processando) Container(color: Colors.black26, child: const Center(child: CircularProgressIndicator())),
        ],
      ),
    );
  }
}
