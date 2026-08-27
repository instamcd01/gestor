import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:excel/excel.dart';
import "package:file_picker/file_picker.dart";
import 'package:share_plus/share_plus.dart';
import '../providers/auth_provider.dart';
import '../providers/produto_provider.dart';
import '../models/produto.dart';
import '../repositories/importacao_planilha_repository.dart';
import '../repositories/marketplace_repository.dart';
import '../repositories/produto_canal_repository.dart';
import '../repositories/produto_repository.dart';
import '../screens/historico_importacoes_screen.dart';
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
  // Cadastro estruturado de variante — permite editar em massa pela
  // planilha em vez de produto por produto no app. Célula vazia preserva o
  // valor já salvo (mesmo padrão de custo/preço/estoque abaixo); só troca
  // de verdade o que a pessoa escrever. `nome` continua fora daqui de
  // propósito (ver proteção de nomeManualOverride mais abaixo).
  'fabricante': ['fabricante'],
  'tipo_produto': ['tipo de produto', 'tipo produto'],
  'nome_comercial': ['nome comercial'],
  'especie': ['espécie', 'especie'],
  'fase': ['fase'],
  'porte': ['porte'],
  'sabor': ['sabor'],
  'dose': ['dose'],
  'composicao': ['composição', 'composicao'],
  'apresentacao': ['apresentação', 'apresentacao'],
  'peso': ['peso (kg)', 'peso'],
};

class ImportarProdutosScreen extends StatefulWidget {
  const ImportarProdutosScreen({super.key});

  @override
  State<ImportarProdutosScreen> createState() => _ImportarProdutosScreenState();
}

class _ImportarProdutosScreenState extends State<ImportarProdutosScreen> {
  bool _processando = false;
  // Só a etapa de atualização tem progresso real pra mostrar — é a única
  // que faz uma chamada por produto (criarEmLote insere em blocos de 300
  // numa tacada só, não dá pra acompanhar item a item do mesmo jeito).
  int _progressoAtual = 0;
  int _progressoTotal = 0;
  String? _nomeArquivoAtual;

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

    _nomeArquivoAtual = result.files.single.name;
    setState(() {
      _processando = true;
      _progressoTotal = 0;
    });
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

          // Preço promocional de R$0,00 nunca é uma promoção real (a loja não
          // dá produto de graça) — é sempre planilha de origem preenchendo 0
          // em vez de deixar em branco pra "sem promoção ativa" (achado real:
          // importação de 22/08/2026 zerou 851 dos 967 produtos assim, cada um
          // aparecendo no site como 100% de desconto). Trata igual a célula
          // vazia em vez de confiar que a planilha nunca vai mandar 0 de novo.
          double? valorPromocional(String campo) {
            final v = valor(campo);
            return (v == null || v <= 0) ? null : v;
          }

          // Texto do cadastro estruturado: célula vazia preserva o que já
          // está salvo, mesmo raciocínio do `valor()` acima pra número.
          String? textoOuExistente(String campo, String? atual) => mapa.celula(row, campo) ?? atual;

          final (categoria, subcategoria) = _splitCategoria(mapa.celula(row, 'grupo'));
          final skuExterno = mapa.celula(row, 'id_externo');
          final existente = skuExterno != null ? existentesPorSku[skuExterno] : null;

          // Célula vazia/não reconhecida (ex: fórmula de busca sem match)
          // preserva o custo/preço que já estava salvo em vez de zerar — só
          // um produto NOVO (sem `existente`) cai no 0.0, porque não tem
          // valor anterior pra preservar. Mesma classe do bug real do
          // preco_promocional (ver `valorPromocional` acima): zerar um valor
          // financeiro por falha de leitura é sempre pior que manter o que já
          // estava certo.
          final custo = valor('custo') ?? existente?.custo ?? 0.0;
          final preco = valor('preco') ?? existente?.preco ?? 0.0;
          // Mesmo raciocínio acima, ainda mais crítico aqui: zerar estoque
          // por falha de leitura não só erra o número — o trigger
          // `trg_sincronizar_visibilidade_catalogo` (2026-08-22) tira o
          // produto do catálogo do site sozinho assim que o estoque chega a
          // zero, então uma célula vazia/"CONFERIR" podia derrubar do ar um
          // produto que continua em estoque de verdade.
          final estoqueAtual = valor('estoque_atual')?.round() ?? existente?.estoqueAtual ?? 0;

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
            // Sem isso, ProdutoRepository.atualizar() pula o UPDATE da
            // tabela `estoque` inteiro (ela só roda `if (estoqueId != null)`)
            // — a planilha atualizava nome/preço normalmente, mas a
            // quantidade em estoque nunca mudava de verdade, mesmo o app
            // reportando sucesso na importação.
            estoqueId: existente?.estoqueId,
            sku: skuExterno,
            // Produto com nome travado (nomeManualOverride) nunca aceita o
            // texto da planilha de volta — sem isso, reimportar uma planilha
            // desatualizada (ex: arquivo antigo do fornecedor) sobrescreve
            // silenciosamente o nome estruturado manualmente, mesmo a flag
            // impedindo só a fórmula automática de mexer nele, não o próprio
            // app. Mesma classe do bug já corrigido abaixo pros campos
            // internos (peso, fabricante, cadastro estruturado...).
            nome: (existente?.nomeManualOverride ?? false) ? existente!.nome : nome,
            categoria: categoria,
            subcategoria: subcategoria,
            codigoBarras: mapa.celula(row, 'codigo_barras') ?? '',
            custo: custo,
            preco: preco,
            precoPromocional: valorPromocional('preco_promocional'),
            precoIfood: valor('preco_ifood'),
            precoConcorrencia: valor('preco_concorrencia'),
            validade: mapa.celula(row, 'validade'),
            estoqueAtual: estoqueAtual,
            estoqueMinimo: valor('estoque_minimo')?.round() ?? existente?.estoqueMinimo ?? 0,
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
            // Volume, vínculo de família de variante (produto_pai_id/
            // tipo_variacao/variante_label), ciclo de recompra e flag de kit
            // não têm coluna na planilha — sem preservar o que já existe,
            // toSupabaseMap() mandaria tudo isso como null/false no UPDATE e
            // apagaria silenciosamente esses campos de QUALQUER produto que
            // passasse pela importação (mesmo bug que já existia pro
            // estoqueId). Fabricante e todo o cadastro estruturado (nome
            // comercial, espécie, dose...) agora TÊM coluna própria — ver
            // `textoOuExistente` acima — pra permitir edição em massa pela
            // planilha, mas continuam preservando o valor atual quando a
            // célula vem vazia.
            peso: valor('peso') ?? existente?.peso,
            volume: existente?.volume,
            fabricante: textoOuExistente('fabricante', existente?.fabricante),
            unidadeMedida: existente?.unidadeMedida ?? 'un',
            nomeComercial: textoOuExistente('nome_comercial', existente?.nomeComercial),
            tipoProduto: textoOuExistente('tipo_produto', existente?.tipoProduto),
            especie: textoOuExistente('especie', existente?.especie),
            fase: textoOuExistente('fase', existente?.fase),
            porte: textoOuExistente('porte', existente?.porte),
            sabor: textoOuExistente('sabor', existente?.sabor),
            dose: textoOuExistente('dose', existente?.dose),
            composicao: textoOuExistente('composicao', existente?.composicao),
            apresentacao: textoOuExistente('apresentacao', existente?.apresentacao),
            nomeManualOverride: existente?.nomeManualOverride ?? false,
            produtoPaiId: existente?.produtoPaiId,
            tipoVariacao: existente?.tipoVariacao,
            varianteLabel: existente?.varianteLabel,
            cicloRecompraDias: existente?.cicloRecompraDias,
            ehKit: existente?.ehKit ?? false,
          );

          if (avisoValor) linhasComValorInvalido.add(numeroLinha);
          linhas.add(_LinhaImportada(numeroLinha: numeroLinha, produto: produto, atualizacao: existente != null));

          // "> 0", não só "!= null": um 0 literal aqui não é "sem preço no
          // iFood", vira um preço de verdade sincronizado pro canal real
          // (produto_canal.preco, ver ProdutoCanalRepository/n8n) — mesma
          // classe do bug do preco_promocional, mas aqui o risco é o produto
          // aparecer cobrando R$0,00 no iFood de verdade, não só no site.
          if (produto.precoIfood != null &&
              produto.precoIfood! > 0 &&
              (skuExterno != null || produto.codigoBarras.isNotEmpty)) {
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
      final empresaId = mounted ? context.read<AuthProvider>().empresaId : null;
      if (empresaId != null) {
        await ImportacaoPlanilhaRepository().registrar(
          empresaId: empresaId,
          tipo: 'produtos',
          nomeArquivo: _nomeArquivoAtual,
          totalLinhas: 0,
          novos: 0,
          atualizados: 0,
          linhasIgnoradas: 0,
          status: 'erro',
          mensagemErro: 'Erro ao ler a planilha: $e',
        );
      }
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
    // Duas linhas marcadas como "produto novo" com o mesmo ID quebram o
    // INSERT em lote (unique_sku_loja) com um erro cru do Postgres, sem
    // dizer qual produto é — checa e mostra ANTES de tentar importar, em
    // vez de deixar o usuário caçando duplicata na planilha às cegas.
    final novosPorSku = <String, List<int>>{};
    for (final l in linhas.where((l) => !l.atualizacao)) {
      final sku = l.produto.sku;
      if (sku == null || sku.isEmpty) continue;
      novosPorSku.putIfAbsent(sku, () => []).add(l.numeroLinha);
    }
    final duplicados = novosPorSku.entries.where((e) => e.value.length > 1).toList();
    if (duplicados.isNotEmpty) {
      final empresaIdErro = mounted ? context.read<AuthProvider>().empresaId : null;
      if (empresaIdErro != null) {
        await ImportacaoPlanilhaRepository().registrar(
          empresaId: empresaIdErro,
          tipo: 'produtos',
          nomeArquivo: _nomeArquivoAtual,
          totalLinhas: linhas.length,
          novos: 0,
          atualizados: 0,
          linhasIgnoradas: 0,
          status: 'erro',
          mensagemErro: 'IDs duplicados na planilha: ${duplicados.map((e) => e.key).join(", ")}',
        );
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('IDs duplicados na planilha'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Esses IDs aparecem em mais de uma linha marcada como produto novo — '
                  'deixe só uma linha por ID na planilha e importe de novo:',
                ),
                const SizedBox(height: 8),
                ...duplicados.map((e) => Text('• ID ${e.key} — linhas ${e.value.join(", ")}')),
              ],
            ),
          ),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendi'))],
        ),
      );
      return;
    }

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

    final novosProdutos = linhas.where((l) => !l.atualizacao).map((l) => l.produto).toList();
    final atualizacoesLista = linhas.where((l) => l.atualizacao).toList();

    setState(() {
      _processando = true;
      _progressoAtual = 0;
      _progressoTotal = atualizacoesLista.length;
    });
    try {
      final produtoProvider = Provider.of<ProdutoProvider>(context, listen: false);
      final empresaId = context.read<AuthProvider>().empresaId;
      if (empresaId == null) throw StateError('Empresa não identificada.');

      var inseridos = 0;
      if (novosProdutos.isNotEmpty) {
        inseridos = await ProdutoRepository().criarEmLote(novosProdutos, empresaId: empresaId);
      }

      var atualizados = 0;
      for (final l in atualizacoesLista) {
        await ProdutoRepository().atualizar(l.produto);
        atualizados++;
        if (mounted) setState(() => _progressoAtual = atualizados);
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

      await ImportacaoPlanilhaRepository().registrar(
        empresaId: empresaId,
        tipo: 'produtos',
        nomeArquivo: _nomeArquivoAtual,
        totalLinhas: linhas.length,
        novos: inseridos,
        atualizados: atualizados,
        linhasIgnoradas: linhasSemNome.length + linhasComValorInvalido.length,
        status: 'sucesso',
      );

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
      // 23505 (unique_sku_loja) sobrevivendo ao pré-check acima só acontece
      // se o ID já existir num produto EXCLUÍDO (soft-delete) — o pré-check
      // só pega duplicata dentro da própria planilha, não contra o banco.
      final mensagem = e.toString().contains('23505')
          ? 'Erro ao importar: um dos IDs já existe no Gestor (possivelmente um produto excluído antes). '
              'Confira se algum ID da planilha corresponde a um produto já excluído.'
          : 'Erro ao importar: $e';

      final empresaIdErro = mounted ? context.read<AuthProvider>().empresaId : null;
      if (empresaIdErro != null) {
        await ImportacaoPlanilhaRepository().registrar(
          empresaId: empresaIdErro,
          tipo: 'produtos',
          nomeArquivo: _nomeArquivoAtual,
          totalLinhas: linhas.length,
          novos: 0,
          atualizados: _progressoAtual,
          linhasIgnoradas: 0,
          status: 'erro',
          mensagemErro: mensagem,
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagem)));
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
    setState(() {
      _processando = true;
      _progressoTotal = 0;
    });
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
        TextCellValue('Fabricante'),
        TextCellValue('Tipo de Produto'),
        TextCellValue('Nome Comercial'),
        TextCellValue('Espécie'),
        TextCellValue('Fase'),
        TextCellValue('Porte'),
        TextCellValue('Sabor'),
        TextCellValue('Dose'),
        TextCellValue('Composição'),
        TextCellValue('Apresentação'),
        TextCellValue('Peso (kg)'),
        // Só informativo — não é lido de volta na reimportação, pra não dar
        // brecha de destravar o nome sem querer editando essa célula.
        TextCellValue('Cadastro Manual'),
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
          TextCellValue(p.fabricante ?? ''),
          TextCellValue(p.tipoProduto ?? ''),
          TextCellValue(p.nomeComercial ?? ''),
          TextCellValue(p.especie ?? ''),
          TextCellValue(p.fase ?? ''),
          TextCellValue(p.porte ?? ''),
          TextCellValue(p.sabor ?? ''),
          TextCellValue(p.dose ?? ''),
          TextCellValue(p.composicao ?? ''),
          TextCellValue(p.apresentacao ?? ''),
          p.peso != null ? DoubleCellValue(p.peso!) : TextCellValue(''),
          TextCellValue(p.nomeManualOverride ? 'Sim' : 'Não'),
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
    return PopScope(
      // Sair no meio de uma importação em lote deixa a operação pela
      // metade (parte dos produtos atualizados, parte não) sem nenhum
      // jeito de saber onde parou — bloqueia a saída enquanto _processando,
      // com um aviso, em vez de deixar acontecer sem querer.
      canPop: !_processando,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Aguarde a importação terminar antes de sair desta tela.')),
        );
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Importar Produtos'),
          actions: [
            IconButton(
              tooltip: 'Histórico de importações',
              icon: const Icon(Icons.history),
              onPressed: _processando
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const HistoricoImportacoesScreen(tipo: 'produtos')),
                      ),
            ),
          ],
        ),
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
          if (_processando)
            Container(
              color: Colors.black26,
              child: Center(
                child: _progressoTotal > 0
                    ? Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Atualizando produtos — $_progressoAtual de $_progressoTotal'),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: 220,
                                child: LinearProgressIndicator(value: _progressoAtual / _progressoTotal),
                              ),
                              const SizedBox(height: 4),
                              Text('${((_progressoAtual / _progressoTotal) * 100).toStringAsFixed(0)}%'),
                              const SizedBox(height: 12),
                              const Text(
                                'Não feche esta tela até a importação terminar.',
                                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                              ),
                            ],
                          ),
                        ),
                      )
                    // Sem produtos pra atualizar (só inserção em lote, ou
                    // ainda lendo/validando a planilha) — não tem progresso
                    // item a item pra mostrar, só o aviso + spinner genérico.
                    : Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              CircularProgressIndicator(),
                              SizedBox(height: 12),
                              Text(
                                'Não feche esta tela até a importação terminar.',
                                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
                              ),
                            ],
                          ),
                        ),
                      ),
              ),
            ),
        ],
      ),
      ),
    );
  }
}
