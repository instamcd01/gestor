import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:excel/excel.dart';
import "package:file_picker/file_picker.dart";
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import '../providers/produto_provider.dart';
import '../models/produto.dart';
import '../utils/produto_validators.dart';

class ImportarProdutosScreen extends StatefulWidget {
  @override
  _ImportarProdutosScreenState createState() => _ImportarProdutosScreenState();
}

class _ImportarProdutosScreenState extends State<ImportarProdutosScreen> {
  /// Lê uma célula com segurança: linhas do Excel podem vir mais curtas que
  /// o cabeçalho quando as últimas colunas estão em branco, então o acesso
  /// direto por índice (row[i]) pode estourar o índice e derrubar a linha
  /// inteira silenciosamente.
  String? _celula(List<Data?> row, int index) {
    return index < row.length ? row[index]?.value?.toString() : null;
  }

  /// Lê um valor monetário/numérico da planilha usando o mesmo parser das
  /// telas de cadastro (trata vírgula decimal). Se a célula tiver conteúdo
  /// mas não for um número válido, marca a linha em [linhasComAviso] em vez
  /// de silenciosamente virar 0.0 — evita zerar preço/custo sem avisar.
  double _parseValorPlanilha(List<Data?> row, int index, int numeroLinha, List<int> linhasComAviso) {
    final texto = _celula(row, index);
    final valor = ProdutoValidators.parseNumero(texto);
    if (texto != null && texto.trim().isNotEmpty && valor == null) {
      linhasComAviso.add(numeroLinha);
    }
    return valor ?? 0.0;
  }

  // Função para importar os produtos
  Future<void> importarProdutos() async {
    // Seleciona o arquivo Excel
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
    );

    if (result != null) {
      if (!mounted) return;
      final path = result.files.single.path!;
      final file = File(path);

      // Lê o arquivo Excel
      final bytes = file.readAsBytesSync();
      final excel = Excel.decodeBytes(bytes);

      if (excel != null) {
        final produtoProvider =
            Provider.of<ProdutoProvider>(context, listen: false);
        // Garante que a lista local está atualizada antes de correlacionar
        // o ID da planilha com produtos já existentes no Supabase.
        await produtoProvider.carregarProdutos();

        int importados = 0;
        final linhasComErro = <int>[];
        final linhasComValorInvalido = <int>[];

        // Itera sobre as planilhas (normalmente temos apenas uma)
        for (var table in excel.tables.values) {
          int rowIndex = 0;  // Índice para rastrear a linha atual

          // Para cada linha da planilha
          for (var row in table.rows) {
            // Pula a primeira linha (cabeçalho)
            if (rowIndex == 0) {
              rowIndex++;
              continue; // Ignora a primeira linha que contém os cabeçalhos
            }

            final numeroLinha = rowIndex + 1; // linha 1-indexada como no Excel

            try {
              // Acessa o valor das células corretamente
              final nome = _celula(row, 0) ?? '';

              // Condicional: Verifica se o nome não está vazio
              if (nome.isEmpty) {
                debugPrint('Nome vazio, ignorando linha: $row');
                rowIndex++;
                continue; // Ignora a linha se o nome estiver vazio
              }

              final categoria = _celula(row, 1) ?? '';
              final codigoBarras = _celula(row, 2) ?? '';
              final custo = _parseValorPlanilha(row, 3, numeroLinha, linhasComValorInvalido);
              final preco = _parseValorPlanilha(row, 4, numeroLinha, linhasComValorInvalido);
              final precoIfood = _parseValorPlanilha(row, 5, numeroLinha, linhasComValorInvalido);
              final validade = _celula(row, 6) ?? '';
              final estoqueAtual = int.tryParse(_celula(row, 7) ?? '0') ?? 0;
              final estoqueMinimo = int.tryParse(_celula(row, 8) ?? '0') ?? 0;
              final markup = _celula(row, 9) ?? '';
              final lucro = _celula(row, 10) ?? '';
              final precoConcorrencia = _parseValorPlanilha(row, 11, numeroLinha, linhasComValorInvalido);
              final empresa = _celula(row, 12) ?? '';
              final idDaPlanilha = _celula(row, 13)?.trim() ?? '';
              final precoPromocional = _parseValorPlanilha(row, 14, numeroLinha, linhasComValorInvalido);
              final destacar = _celula(row, 15)?.toLowerCase() == 'true';
              final exibirNoCatalogo =
                  _celula(row, 16)?.toLowerCase() == 'true';

              // Se a planilha traz um ID que corresponde a um produto já
              // carregado, tratamos como atualização; caso contrário, como
              // um produto novo (o Supabase gera o ID no INSERT).
              final produtoExistente = idDaPlanilha.isNotEmpty
                  ? produtoProvider.getProdutoPorId(idDaPlanilha)
                  : null;

              final produto = Produto(
                nome: nome,
                categoria: categoria,
                codigoBarras: codigoBarras,
                custo: custo,
                preco: preco,
                precoIfood: precoIfood,
                validade: validade,
                estoqueAtual: estoqueAtual,
                estoqueMinimo: estoqueMinimo,
                markup: markup,
                lucro: lucro,
                precoConcorrencia: precoConcorrencia,
                empresa: empresa,
                id: produtoExistente?.id,
                precoPromocional: precoPromocional,
                descricao: '', // Ajuste conforme necessário
                imagemUrl: '', // Ajuste conforme necessário
                destacar: destacar,
                exibirNoCatalogo: exibirNoCatalogo,
              );

              if (produtoExistente != null) {
                await produtoProvider.atualizarProduto(produto);
              } else {
                await produtoProvider.adicionarProduto(produto);
              }
              importados++;
            } catch (e) {
              linhasComErro.add(numeroLinha);
              debugPrint('Erro ao processar linha: $row, erro: $e');
            }

            rowIndex++; // Incrementa o índice da linha
          }
        }

        if (!mounted) return;
        final avisos = <String>[];
        if (linhasComValorInvalido.isNotEmpty) {
          avisos.add('valor inválido (virou 0) nas linhas ${linhasComValorInvalido.join(', ')}');
        }
        if (linhasComErro.isNotEmpty) {
          avisos.add('erro nas linhas ${linhasComErro.join(', ')}');
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              avisos.isEmpty
                  ? '$importados produtos importados com sucesso.'
                  : '$importados produtos importados. Atenção: ${avisos.join(' e ')}.',
            ),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }

  // Função para gerar e baixar a planilha base
  Future<void> gerarPlanilhaBase() async {
    var excel = Excel.createExcel(); // Cria uma nova planilha
    Sheet sheet = excel['Produtos']; // Cria uma aba chamada "Produtos"

    // Definindo as colunas da planilha
    sheet.appendRow([
      TextCellValue('Nome'),
      TextCellValue('Categoria'),
      TextCellValue('Código de Barras'),
      TextCellValue('Custo'),
      TextCellValue('Preço'),
      TextCellValue('Preço Ifood'),
      TextCellValue('Validade'),
      TextCellValue('Estoque Atual'),
      TextCellValue('Estoque Mínimo'),
      TextCellValue('Markup'),
      TextCellValue('Lucro'),
      TextCellValue('Preço Concorrência'),
      TextCellValue('Empresa'),
      TextCellValue('ID'),
      TextCellValue('Preço Promocional'),
      TextCellValue('Destacar'),
      TextCellValue('Exibir no Catálogo'),
    ]);

    // Obter o diretório onde o arquivo será salvo
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/produtos_template.xlsx');

    // Salvar o arquivo Excel no diretório
    final bytes = await excel.encode() ?? [];
    await file.writeAsBytes(bytes);

    // Usando share_plus para compartilhar o arquivo gerado
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Aqui está a planilha de produtos para preenchimento!',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Importar Produtos'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: importarProdutos,
              child: Text('Importar Produtos da Planilha'),
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: gerarPlanilhaBase,
              child: Text('Baixar Planilha Base'),
            ),
          ],
        ),
      ),
    );
  }
}
