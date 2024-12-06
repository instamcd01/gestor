import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:excel/excel.dart';
import "package:file_picker/file_picker.dart";
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/produto_provider.dart';
import '../models/produto.dart';

class ImportarProdutosScreen extends StatefulWidget {
  @override
  _ImportarProdutosScreenState createState() => _ImportarProdutosScreenState();
}

class _ImportarProdutosScreenState extends State<ImportarProdutosScreen> {
  // Função para importar os produtos
  Future<void> importarProdutos() async {
    // Seleciona o arquivo Excel
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
    );

    if (result != null) {
      final path = result.files.single.path!;
      final file = File(path);

      // Lê o arquivo Excel
      final bytes = file.readAsBytesSync();
      final excel = Excel.decodeBytes(bytes);

      if (excel != null) {
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

            if (row.length < 16) {
              debugPrint('Linha inválida ou incompleta: $row');
              continue; // Ignora a linha se não tiver colunas suficientes
            }

            try {
              // Acessa o valor das células corretamente
              final nome = row[0]?.value?.toString() ?? '';

              // Condicional: Verifica se o nome não está vazio
              if (nome.isEmpty) {
                debugPrint('Nome vazio, ignorando linha: $row');
                continue; // Ignora a linha se o nome estiver vazio
              }

              final categoria = row[1]?.value?.toString() ?? '';
              final codigoBarras = row[2]?.value?.toString() ?? '';
              final custo = double.tryParse(row[3]?.value?.toString() ?? '0') ?? 0.0;
              final preco = double.tryParse(row[4]?.value?.toString() ?? '0') ?? 0.0;
              final precoIfood = double.tryParse(row[5]?.value?.toString() ?? '0') ?? 0.0;
              final validade = row[6]?.value?.toString() ?? '';
              final estoqueAtual = int.tryParse(row[7]?.value?.toString() ?? '0') ?? 0;
              final estoqueMinimo = int.tryParse(row[8]?.value?.toString() ?? '0') ?? 0;
              final markup = row[9]?.value?.toString() ?? '0';
              final lucro = row[10]?.value?.toString() ?? '0';
              final precoConcorrencia = row[11]?.value?.toString() ?? '0';
              final empresa = row[12]?.value?.toString() ?? '';
              final id = row[13]?.value?.toString().trim() ?? '';
              final precoPromocional = double.tryParse(row[14]?.value?.toString() ?? '0') ?? 0.0;
              final destacar = row[15]?.value?.toString().toLowerCase() == 'true';
              final exibirNoCatalogo = row[16]?.value?.toString().toLowerCase() == 'true';

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
                id: id,
                precoPromocional: precoPromocional,
                descricao: '', // Ajuste conforme necessário
                imagemUrl: '', // Ajuste conforme necessário
                destacar: destacar,
                exibirNoCatalogo: exibirNoCatalogo,
              );

              // Adiciona o produto ao provider
              Provider.of<ProdutoProvider>(context, listen: false).adicionarProduto(produto);
            } catch (e) {
              debugPrint('Erro ao processar linha: $row, erro: $e');
            }

            rowIndex++; // Incrementa o índice da linha
          }
        }
      }
    }
  }

  // Função para gerar e baixar a planilha base
  Future<void> gerarPlanilhaBase() async {
    var excel = Excel.createExcel(); // Cria uma nova planilha
    Sheet sheet = excel['Produtos']; // Cria uma aba chamada "Produtos"

    // Definindo as colunas da planilha
    sheet.appendRow([
      'Nome',
      'Categoria',
      'Código de Barras',
      'Custo',
      'Preço',
      'Preço Ifood',
      'Validade',
      'Estoque Atual',
      'Estoque Mínimo',
      'Markup',
      'Lucro',
      'Preço Concorrência',
      'Empresa',
      'ID',
      'Preço Promocional',
      'Destacar',
      'Exibir no Catálogo'
    ]);

    // Obter o diretório onde o arquivo será salvo
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/produtos_template.xlsx');

    // Salvar o arquivo Excel no diretório
    final bytes = await excel.encode() ?? [];
    await file.writeAsBytes(bytes);

    // Usando share_plus para compartilhar o arquivo gerado
    await Share.shareFiles([file.path], text: 'Aqui está a planilha de produtos para preenchimento!');
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
